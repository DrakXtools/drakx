package common; # $Id$

use MDK::Common;
use diagnostics;
use strict;

use log;
use run_program;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw($SECTORSIZE N N_ check_for_xserver files_exist formatTime formatXiB is_xbox makedev mandrake_release removeXiBSuffix require_root_capability salt setVirtual set_alternative set_l10n_sort set_permissions translate unmakedev);

# perl_checker: RE-EXPORT-ALL
push @EXPORT, @MDK::Common::EXPORT;


$::prefix ||= ""; # no warning

#-#####################################################################################
#- Globals
#-#####################################################################################
our $SECTORSIZE  = 512;

#-#####################################################################################
#- Functions
#-#####################################################################################


sub sprintf_fixutf8 {
    my $need_upgrade;
    $need_upgrade |= to_bool(c::is_tagged_utf8($_)) + 1 foreach @_;
    if ($need_upgrade == 3) { c::upgrade_utf8($_) foreach @_ }
    sprintf shift, @_;
}

sub N {
    $::one_message_has_been_translated ||= join(':', (caller(0))[1,2]); #- see mygtk2.pm
    my $s = shift @_; my $t = translate($s);
    sprintf_fixutf8 $t, @_;
}
sub N_ { $_[0] }


sub salt {
    my ($nb) = @_;
    require devices;
    open(my $F, devices::make("random")) or die "missing random";
    my $s; read $F, $s, $nb;
    $s = pack("b8" x $nb, unpack "b6" x $nb, $s);
    $s =~ tr|\0-\x3f|0-9a-zA-Z./|;
    $s;
}

sub makedev { ($_[0] << 8) | $_[1] }
sub unmakedev { $_[0] >> 8, $_[0] & 0xff }

sub translate_real {
    my ($s) = @_;
    $s or return '';
    foreach (@::textdomains, 'libDrakX') {
	my $s2 = c::dgettext($_, $s);
	return $s2 if $s ne $s2;
    }
    $s;
}

sub translate {
    my $s = translate_real(@_);
    $::need_utf8_i18n and c::set_tagged_utf8($s);

    #- translation with context, kde-like 
    $s =~ s/^_:.*\n//;
    $s;
}

#- This is needed because text printed by Gtk2 will always be encoded
#- in UTF-8;
#- we first check if LC_ALL is defined, because if it is, changing
#- only LC_COLLATE will have no effect.
sub set_l10n_sort() {
    my $collation_locale = $ENV{LC_ALL};
    if (!$collation_locale) {
	require POSIX;
        $collation_locale = POSIX::setlocale(POSIX::LC_COLLATE());
        $collation_locale =~ /UTF-8/ or POSIX::setlocale(POSIX::LC_COLLATE(), "$collation_locale.UTF-8");
    }
}


BEGIN { undef *availableRamMB }
sub availableRamMB()  { 
    my $s = MDK::Common::System::availableRamMB();
    #- HACK HACK: if i810 and memsize
    require detect_devices;
    return $s - 1 if $s == 128 && detect_devices::matching_driver__regexp('^Card:Intel 810$');
    $s;
}

sub setVirtual {
    my ($vt_number) = @_;
    my $vt = '';
    sysopen(my $C, "/dev/console", 2) or die "failed to open /dev/console: $!";
    ioctl($C, c::VT_GETSTATE(), $vt) &&
      ioctl($C, c::VT_ACTIVATE(), $vt_number) &&
	ioctl($C, c::VT_WAITACTIVE(), $vt_number) or die "setVirtual failed";
    unpack "S", $vt;
}

sub nonblock {
    my ($F) = @_;
    fcntl($F, c::F_SETFL(), fcntl($F, c::F_GETFL(), 0) | c::O_NONBLOCK());
}

sub removeXiBSuffix {
    local $_ = shift;

    /(\d+)\s*kB?$/i and return $1 * 1024;
    /(\d+)\s*MB?$/i and return $1 * 1024 * 1024;
    /(\d+)\s*GB?$/i and return $1 * 1024 * 1024 * 1024;
    /(\d+)\s*TB?$/i and return $1 * 1024 * 1024 * 1024 * 1024;
    $_;
}
sub formatXiB {
    my ($newnb, $o_newbase) = @_;
    my $newbase = $o_newbase || 1;
    my ($nb, $base);
    my $decr = sub { 
	($nb, $base) = ($newnb, $newbase);
	$base >= 1024 ? ($newbase = $base / 1024) : ($newnb = $nb / 1024);
    };
    foreach ('', N("KB"), N("MB"), N("GB")) {
	$decr->(); 
	if ($newnb < 1 && $newnb * $newbase < 1) {
	    my $v = $nb * $base;
	    my $s = $v < 10 && int(10 * $v - 10 * int($v));
	    return int($v) . ($s ? ".$s" : '') . $_;
	}
    }
    int($newnb * $newbase) . N("TB");
}

sub formatTime {
    my ($s, $m, $h) = gmtime($_[0]);
    if ($h) {
	sprintf "%02d:%02d", $h, $m;
    } elsif ($m > 1) {
	N("%d minutes", $m);
    } elsif ($m == 1) {
	N("1 minute");
    } else {
	N("%d seconds", $s);
    }
}

sub expand_symlinks_but_simple {
    my ($f) = @_;
    my $link = readlink($f);
    my $f2 = expand_symlinks($f);
    if ($link && $link !~ m|/|) {
	# put back the last simple symlink
	$f2 =~ s|\Q$link\E$|basename($f)|e;
    }
    $f2;
}

sub sync { &MDK::Common::System::sync }

BEGIN { undef *formatError }
sub formatError {
    my ($err) = @_;
    ref($err) eq 'SCALAR' and $err = $$err;
    log::l("error: $err");
    &MDK::Common::String::formatError($err);
}

# Group the list by n. Returns a reference of lists of length n
sub group_n_lm {
    my $n = shift;
    my @l;
    push @l, [ splice(@_, 0, $n) ] while @_;
    @l;
}

sub join_lines {
    my @l;
    my $s;
    foreach (@_) {
	if (/^\s/) {
	    $s .= $_;
	} else {
	    push @l, $s if $s;
	    $s = $_;
	}
    }
    @l, if_($s, $s);
}


sub set_alternative {
    my ($command, $executable) = @_;

    #- check the existance of $executable as an alternative for $command
    #- (is this needed???)
    run_program::rooted_get_stdout($::prefix, 'update-alternatives', '--display', $command) =~ /^\Q$executable /m or return;

    #- this does not handle relative symlink, but neither does update-alternatives ;p
    symlinkf $executable, "$::prefix/etc/alternatives/$command";
}

sub files_exist { and_(map { -f "$::prefix$_" } @_) }

sub secured_file {
    my ($f) = @_;
    c::is_secure_file($f) or die "can not ensure a safe $f";
    $f;
}

sub set_permissions {
    my ($file, $perms, $o_owner, $o_group) = @_;
    # We only need to set the permissions during installation to be able to
    # print test pages. After installation the devfsd daemon does the business
    # automatically.
    return 1 unless $::isInstall;
    if ($o_owner && $o_group) {
        run_program::rooted($::prefix, "/bin/chown", "$o_owner.$o_group", $file)
	    or die "Could not start chown!";
    } elsif ($o_owner) {
        run_program::rooted($::prefix, "/bin/chown", $o_owner, $file)
	    or die "Could not start chown!";
    } elsif ($o_group) {
        run_program::rooted($::prefix, "/bin/chgrp", $o_group, $file)
	    or die "Could not start chgrp!";
    }
    run_program::rooted($::prefix, "/bin/chmod", $perms, $file)
	or die "Could not start chmod!";
}

sub release_file {
    my ($o_dir) = @_;
    find { -r "$o_dir$_" } map { "/etc/$_" } 'mandrakelinux-release', 'mandrake-release', 'release', 'redhat-release';
}

sub mandrake_release {
    my ($o_dir) = @_;
    my $f = release_file($o_dir);
    $f && chomp_(cat_("$o_dir$f"));
}

sub require_root_capability() {
    return if $::testing || !$>; # we're already root
    if (check_for_xserver()) {
	if (fuzzy_pidofs(qr/\bkwin\b/) > 0) {
	    exec("kdesu", "--ignorebutton", "-c", "$0 @ARGV") or die N("kdesu missing");
	}
    }
    exec { 'consolehelper' } $0, @ARGV or die N("consolehelper missing");

    # still not root ?
    die "you must be root to run this program" if $>;
}

sub check_for_xserver() {
    if (!defined $::xtest) {
	$::xtest = 0;         
	eval { 
	    require xf86misc::main; 
	    $::xtest = xf86misc::main::Xtest($ENV{DISPLAY});
	} if $ENV{DISPLAY};
    }
    return $::xtest;
}

sub is_xbox() {
    require detect_devices;
    any { $_->{vendor} == 0x10de && $_->{id} == 0x02a5 } detect_devices::pci_probe();
}

#- special unpack
#- - returning an array refs for each element like "s10"
#- - handling things like s10* at the end of the format
sub unpack_with_refs {
    my ($format, $s) = @_;
    my $initial_format = $format;
    my @r;
    while ($format =~ s/\s*(\w(\d*))(\*?)\s*//) {
	my ($sub_format, $nb, $many) = ($1, $2, $3);
	$many && $format and internal_error("bad * in the middle of format in $initial_format");

	my $done = $many && !length($s);
	while (!$done) {
	    my @l = unpack("$sub_format a*", $s);
	    $s = pop @l;
	    push @r, $nb ? \@l : @l;
	    $done = !$many || !length($s);
	}
    }
    @r;
}

1;
