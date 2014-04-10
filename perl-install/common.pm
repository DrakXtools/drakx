package common; # $Id$

use MDK::Common;
use diagnostics;
use strict;
BEGIN { eval { require Locale::gettext } } #- allow common.pm to be used in drakxtools-backend without perl-Locale-gettext

use log;
use run_program;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw($SECTORSIZE N P N_ check_for_xserver files_exist formatTime MB formatXiB get_parent_uid is_running makedev mandrake_release mandrake_release_info removeXiBSuffix require_root_capability setVirtual set_alternative set_l10n_sort set_permissions to_utf8  translate unmakedev);

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

sub P {
    my ($s_singular, $s_plural, $nb, @para) = @_; 
    sprintf(translate($s_singular, $s_plural, $nb), @para);
}

sub N {
    my ($s, @para) = @_; 
    sprintf(translate($s), @para);
}
sub N_ { $_[0] }


sub makedev { ($_[0] << 8) | $_[1] }
sub unmakedev { $_[0] >> 8, $_[0] & 0xff }

sub translate_real {
    my ($s, $o_plural, $o_nb) = @_;
    $s or return '';
    my $s2;
    foreach (@::textdomains, 'libDrakX') {
     if ($o_plural) {
         $s2 = Locale::gettext::dngettext($_, $s, $o_plural, $o_nb);
     } else {
         $s2 = Locale::gettext::dgettext($_, $s);
     }
	# when utf8 pragma is in use, Locale::gettext() returns an utf8 string not tagged as such:
	c::set_tagged_utf8($s2) if !utf8::is_utf8($s2) && utf8::is_utf8($s);
	return $s2 if $s ne $s2 && $s2 ne $o_plural;
    }
    # didn't lookup anything or locale is "C":
    $s2;
}

sub remove_translate_context {
    my ($s) = @_;
    #- translation with context, kde-like 
    $s =~ s/^_:.*(?:\n)?//g;
    $s;
}

sub translate {
    my $s = translate_real(@_);
    $::one_message_has_been_translated ||= join(':', (caller(1))[1,2]); #- see mygtk3.pm
    remove_translate_context($s);
}

sub from_utf8 {
    my ($s) = @_;
    Locale::gettext::iconv($s, "utf-8", undef); #- undef = locale charmap = nl_langinfo(CODESET)
}
sub to_utf8 { 
    my ($s) = @_;
    my $str = Locale::gettext::iconv($s, undef, "utf-8"); #- undef = locale charmap = nl_langinfo(CODESET)
    c::set_tagged_utf8($str);
    $str;
}

#- This is needed because text printed by Gtk3 will always be encoded
#- in UTF-8;
#- we first check if LC_ALL is defined, because if it is, changing
#- only LC_COLLATE will have no effect.
sub set_l10n_sort() {
    my $collation_locale = $ENV{LC_ALL};
    if (!$collation_locale) {
        $collation_locale = c::setlocale(c::LC_COLLATE());
        $collation_locale =~ /UTF-8/ or c::setlocale(c::LC_COLLATE(), "$collation_locale.UTF-8");
    }
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
    fcntl($F, c::F_SETFL(), fcntl($F, c::F_GETFL(), 0) | c::O_NONBLOCK()) or die "cannot fcntl F_SETFL: $!";
}

#- return a size in sector
#- ie MB(1) is 2048 sectors, which is 1MB
sub MB {
    my ($nb_MB) = @_;
    $nb_MB * 2048;
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
    my $sign = $newnb < 0 ? -1 : 1;
    $newnb = abs(int($newnb));
    my ($nb, $base);
    my $decr = sub { 
	($nb, $base) = ($newnb, $newbase);
	$base >= 1024 ? ($newbase = $base / 1024) : ($newnb = $nb / 1024);
    };
    my $suffix;
    foreach (N("B"), N("KB"), N("MB"), N("GB"), N("TB")) {
	$decr->(); 
	if ($newnb < 1 && $newnb * $newbase < 1) {
	    $suffix = $_;
	    last;
	}
    }
    my $v = $nb * $base;
    my $s = $v < 10 && int(10 * $v - 10 * int($v));
    int($v * $sign) . ($s ? "." . abs($s) : '') . ($suffix || N("TB"));
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

sub expand_symlinks_with_absolute_symlinks_in_prefix {
    my ($prefix, $link) = @_;

    my ($first, @l) = split '/', $link;
    $first eq '' or die "expand_symlinks: $link is relative\n";
    my ($f, $l);
    foreach (@l) {
	$f .= "/$_";
	while ($l = readlink "$prefix$f") {
	    $f = $l =~ m!^/! ? $l : MDK::Common::File::concat_symlink($f, "../$l");
	}
    }
    "$prefix$f";
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

sub group_by(&@) {
    my $f = shift;
    @_ or return;
    my $e = shift;
    my @l = my $last_l = [$e];
    foreach (@_) {
	if ($f->($e, $_)) {
	    push @$last_l, $_;
	} else {
	    push @l, $last_l = [$_];
	    $e = $_;
	}
    }
    @l;
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


sub read_alternative {
    my ($name) = @_;
    my $alt = readlink("$::prefix/etc/alternatives/$name");
    $alt && $::prefix . $alt;
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

sub open_file {
    my ($file) = @_;
    my $F;
    open($F, $file) ? $F : do { log::l("Cannot open $file: $!"); undef };
}

# FIXME: callers should just use mkstemp in /tmp instead of relying on $TMPDIR || $ENV{HOME}/tmp
# or we should just move the choice of directoyr from callers to here:
# my $tmpdir = find { -d $_ } $ENV{TMPDIR}, "$ENV{HOME}/tmp", "$::prefix/tmp";
sub secured_file {
    my ($f) = @_;
    my $d = dirname($f);
    if (! -d $d) {
        mkdir_p($d);
	if ($d =~ /^$ENV{HOME}/) {
	   my ($user) = grep { $_->[7] eq $ENV{HOME} } list_passwd();
           chown($user->[2], $user->[3], $d);
	}
    }
    c::is_secure_file($f) or die "cannot ensure a safe $f";
    $f;
}

sub unwind_protect {
    my ($to_do, $cleanup) = @_;
    my @l = eval { $to_do->() };
    my $err = $@;
    $cleanup->();
    $err and die $err;
    wantarray() ? @l : $l[0];
}

sub with_private_tmp_file {
    my ($file, $content, $f) = @_;

    my $prev_umask = umask 077;

    unwind_protect(sub { 
	MDK::Common::File::secured_output($file, $content);
	$f->($file);
    }, sub {
	umask $prev_umask;
	unlink $file;
    });
}

sub chown_ {
    my ($b_recursive, $name, $group, @files) = @_;

    my ($uid, $gid) = (getpwnam($name) || $name, getgrnam($group) || $group);
      
    require POSIX;
    my $chown; $chown = sub {
	foreach (@_) {
	    POSIX::lchown($uid, $gid, $_) or die "chown of file $_ failed: $!\n";
	    ! -l $_ && -d $_ && $b_recursive and &$chown(glob_($_));
	}
    };
    $chown->(@files);
}


sub set_permissions {
    my ($file, $perms, $o_owner, $o_group) = @_;
    # We only need to set the permissions during installation to be able to
    # print test pages. After installation udev does the business automatically.
    return 1 unless $::isInstall;
    if ($o_owner || $o_group) {
	$o_owner ||= (lstat($file))[4];
	$o_group ||= (lstat($file))[5];
	chown_(0, $o_owner, $o_group, $file);
    }
    chmod(oct($perms), $file) or die "chmod of file $file failed: $!\n";
}

sub is_running {
    my ($name, $o_user) = @_;
    my $user = $o_user || $ENV{USER};
    foreach (`ps -o '%P %p %c' -u $user`) {
	my ($ppid, $pid, $n) = /^\s*(\d+)\s+(\d+)\s+(.*)/;
	return $pid if $ppid != 1 && $pid != $$ && $n eq $name;
    }
}

sub parse_release_file {
    my ($prefix, $f, $part) = @_;
    chomp(my $s = cat_("$prefix$f"));
    my $version = $s =~ s/\s+release\s+(\S+)// && $1;
    my $arch = $s =~ s/\s+for\s+(\S+)// && $1;
    log::l("find_root_parts found $part->{device}: $s for $arch" . ($f !~ m!/etc/! ? " in special release file $f" : ''));
    { release => $s, version => $version, 
      release_file => $f, part => $part, arch => $arch };
}

sub release_file {
    my ($o_dir) = @_;
    my @names = ('mandrakelinux-release', 'mandrake-release', 'conectiva-release', 'release', 'redhat-release', 'fedora-release', 'SuSE-release');
    find { -r "$o_dir$_" } (
	(map { "/root/drakx/$_.upgrading" } @names), 
	(map { "/etc/$_" } @names),
    );
}

sub mandrake_release_info() {
    parse_LDAP_namespace_structure(cat_('/etc/product.id'));
}

sub parse_LDAP_namespace_structure {
    my ($s) = @_;
    my %h = map { if_(/(.*?)=(.*)/, $1 => $2) } split(',', $s);
    \%h;
}

sub mandrake_release {
    my ($o_dir) = @_;
    my $f = release_file($o_dir);
    $f && chomp_(cat_("$o_dir$f"));
}

sub get_parent_uid() {
    cat_('/proc/' . getppid() . '/status') =~ /Uid:\s*(\d+)/ ? $1 : undef;
}

sub require_root_capability() {
    return if $::testing || !$>; # we're already root

    die "you must be root to run this program";
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

#- used in userdrake and mdkonline
sub md5file {
    require Digest::MD5;
    my @md5 = map {
        my $sum;
	if (open(my $FILE, $_)) {
            binmode($FILE);
            $sum = Digest::MD5->new->addfile($FILE)->hexdigest;
            close($FILE);
        }
        $sum;
    } @_;
    return wantarray() ? @md5 : $md5[0];
}

sub load_modules_from_base {
    my ($base) = @_;
    $base =~ s|::|/|g;
    my $base_file = $base . ".pm";
    require $base_file;
    my ($inc_path) = substr($INC{$base_file}, 0, -length($base_file));
    my @files = map { substr($_, length($inc_path)) } glob_($inc_path . $base . '/*.pm');
    require $_ foreach @files;
    #- return the matching modules list
    map { local $_ = $_; s|/|::|g; s|\.pm$||g; $_ } @files;
}

sub get_alternatives {
    my ($name) = @_;

    my $dir = $::prefix . '/var/lib/rpm/alternatives';
    my ($state, $main_link, @l) = chomp_(cat_("$dir/$name")) or return;
    my @slaves;
    while (@l && $l[0] ne '') {
	my ($name, $link) = splice(@l, 0, 2);
	push @slaves, { name => $name, link => $link };
    }
    shift @l; #- empty line
    my @alternatives;
    while (@l && $l[0] ne '') {
	my ($file, $weight, @slave_files) = splice(@l, 0, 2 + @slaves);
	
	push @alternatives, { file => $file, weight => $weight, slave_files => \@slave_files };
    }
    { name => $name, link => $main_link, state => $state, slaves => \@slaves, alternatives => \@alternatives };
}

sub symlinkf_update_alternatives {
    my ($name, $wanted_file) = @_;
    run_program::rooted($::prefix, 'update-alternatives', '--set', $name, $wanted_file);
}

sub update_gnomekderc_no_create {
    my ($file, $category, %subst_) = @_;
    if (-e $file) {
	update_gnomekderc($file, $category, %subst_);
    }
}

sub cmp_kernel_versions {
    my ($va, $vb) = @_;
    my $rel_a = $va =~ s/-(.*)$// && $1;
    my $rel_b = $vb =~ s/-(.*)$// && $1;
    ($va, $vb) = map { [ split /[.-]/ ] } $va, $vb;
    my $r = 0;
    mapn_ {
	$r ||= $_[0] <=> $_[1];
    } $va, $vb;
    $r || $rel_a <=> $rel_b || $rel_a cmp $rel_b;
}

1;
