package common; # $Id$

use MDK::Common;
use MDK::Common::System;
use diagnostics;
use strict;
use run_program;
use vars qw(@ISA @EXPORT $SECTORSIZE);

@ISA = qw(Exporter);
# no need to export ``_''
@EXPORT = qw($SECTORSIZE N N_ translate untranslate formatXiB removeXiBSuffix formatTime setVirtual makedev unmakedev salt set_permissions files_exist set_alternative mandrake_release);

# perl_checker: RE-EXPORT-ALL
push @EXPORT, @MDK::Common::EXPORT;


#-#####################################################################################
#- Globals
#-#####################################################################################
$SECTORSIZE      = 512;

#-#####################################################################################
#- Functions
#-#####################################################################################


sub sprintf_fixutf8 {
    my $need_upgrade;
    $need_upgrade |= to_bool(c::is_tagged_utf8($_)) + 1 foreach @_;
    if ($need_upgrade == 3) { c::upgrade_utf8($_) foreach @_ };
    sprintf shift, @_;
}

sub N {
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

sub translate {
    my ($s) = @_;
    $s or return '';
    foreach ('libDrakX', @::textdomains) {
	my $s2 = $::isInstall && eval { $::o->isa('interactive::gtk') } ? c::dgettext_utf8($_, $s) : c::dgettext($_, $s);
	return $s2 if $s ne $s2;
    }
    $s;
}

sub untranslate {
    my $s = shift || return;
    foreach (@_) { translate($_) eq $s and return $_ }
    die "untranslate failed";
}

BEGIN { undef *availableRamMB }
sub availableRamMB()  { 
    my $s = MDK::Common::System::availableRamMB();
    #- HACK HACK: if i810 and memsize
    require detect_devices;
    return $s - 1 if $s == 128 && any { $_->{driver} eq 'Card:Intel 810' } detect_devices::probeall();
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


sub removeXiBSuffix {
    local $_ = shift;

    /(\d+)\s*kB?$/i and return $1 * 1024;
    /(\d+)\s*MB?$/i and return $1 * 1024 * 1024;
    /(\d+)\s*GB?$/i and return $1 * 1024 * 1024 * 1024;
    /(\d+)\s*TB?$/i and return $1 * 1024 * 1024 * 1024 * 1024;
    $_;
}
sub formatXiB {
    my ($newnb, $newbase) = @_;
    $newbase ||= 1;
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

sub usingRamdisk { any { /ram3/ } cat_("/proc/mounts") }

sub expand_symlinks_but_simple {
    my ($f) = @_;
    my $link = readlink($f);
    my $f2 = expand_symlinks($f);
    if ($link && $link !~ m|/|) {
	# put back the last simple symlink
	$f2 =~ s|\Q$link\E$|basename($f)|e;
    }
    $f2
}

sub sync { &MDK::Common::System::sync }

# Group the list by n. Returns a reference of lists of length n
sub group_n_lm {
    my $n = shift;
    my @l;
    push @l, [ splice(@_, 0, $n) ] while @_;
    @l
}

sub screenshot_dir__and_move {
    my ($dir1, $dir2) = ("$::prefix/root", '/tmp/stage2');
    if (-e $dir1) {
	if (-e "$dir2/DrakX-screenshots") {
	    cp_af("$dir2/DrakX-screenshots", $dir1);
	    rm_rf("$dir2/DrakX-screenshots");
	}
	$dir1;
    } else {
	$dir2;
    }
}

sub take_screenshot {
    my $dir = screenshot_dir__and_move() . '/DrakX-screenshots';
    my $warn;
    if (!-e $dir) {
	mkdir $dir or $::o->ask_warn('', N("Can't make screenshots before partitioning")), return;
	$warn = 1;
    }
    my $nb = 1;
    $nb++ while -e "$dir/$nb.png";
    system("fb2png /dev/fb0 $dir/$nb.png 0");

    $::o->ask_warn('', N("Screenshots will be available after install in %s", "/root/DrakX-screenshots")) if $warn;
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

    #- this doesn't handle relative symlink, but neither does update-alternatives ;p
    symlinkf $executable, "$::prefix/etc/alternatives/$command";
}

sub files_exist { and_(map { -f "$::prefix$_" } @_) }

sub secured_file {
    my ($f) = @_;
    c::is_secure_file($f) or die "can't ensure a safe $f";
    $f;
}

sub set_permissions {
    my ($file, $perms, $owner, $group) = @_;
    # We only need to set the permissions during installation to be able to
    # print test pages. After installation the devfsd daemon does the business
    # automatically.
    return 1 unless $::isInstall;
    if ($owner && $group) {
        run_program::rooted($::prefix, "/bin/chown", "$owner.$group", $file)
	    or die "Could not start chown!";
    } elsif ($owner) {
        run_program::rooted($::prefix, "/bin/chown", $owner, $file)
	    or die "Could not start chown!";
    } elsif ($group) {
        run_program::rooted($::prefix, "/bin/chgrp", $group, $file)
	    or die "Could not start chgrp!";
    }
    run_program::rooted($::prefix, "/bin/chmod", $perms, $file)
	or die "Could not start chmod!";
}

sub mandrake_release {
    chomp_(cat_("/etc/mandrake-release"))
}

1;
