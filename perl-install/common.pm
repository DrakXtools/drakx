package common; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $printable_chars $sizeof_int $bitof_int $cancel $SECTORSIZE %compat_arch);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    common     => [ qw(__ even odd arch better_arch compat_arch min max sqr sum and_ or_ sign product bool invbool listlength bool2text bool2yesno text2bool to_int to_float ikeys member divide is_empty_array_ref is_empty_hash_ref add2hash add2hash_ set_new set_add round round_up round_down first second top uniq translate untranslate warp_text formatAlaTeX formatLines deref next_val_in_array) ],
    functional => [ qw(fold_left compose mapgrep map_index grep_index find_index map_each grep_each list2kv map_tab_hash mapn mapn_ difference2 before_leaving catch_cdie cdie combine) ],
    file       => [ qw(dirname basename touch all glob_ cat_ cat__ output symlinkf chop_ mode typeFromMagic expand_symlinks) ],
    system     => [ qw(sync makedev unmakedev psizeof strcpy gettimeofday syscall_ salt getVarsFromSh setVarsInSh setVarsInCsh substInFile availableMemory availableRamMB removeXiBSuffix template2file template2userfile update_userkderc list_skels formatTime formatTimeRaw unix2dos setVirtual) ],
    constant   => [ qw($printable_chars $sizeof_int $bitof_int $SECTORSIZE %compat_arch) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


#-#####################################################################################
#- Globals
#-#####################################################################################
$printable_chars = "\x20-\x7E";
$sizeof_int      = psizeof("i");
$bitof_int       = $sizeof_int * 8;
$SECTORSIZE      = 512;
%compat_arch     = ( #- compatibilty arch mapping.
		     'noarch'  => undef,
		     'i386'    => 'noarch',
		     'i486'    => 'i386',
		     'i586'    => 'i486',
		     'i686'    => 'i586',
		     'i786'    => 'i686',
		     'k6'      => 'i586',
		     'k7'      => 'k6',
		     'k8'      => 'k7',
		     'ppc'     => 'noarch',
		     'alpha'   => 'noarch',
		     'sparc'   => 'noarch',
		     'sparc32' => 'sparc',
		     'sparc64' => 'sparc32',
		   );

#-#####################################################################################
#- Functions
#-#####################################################################################

sub fold_left(&@) {
    my $f = shift;
    local $a = shift;
    foreach $b (@_) { $a = &$f() }
    $a
}

sub _ {
    my $s = shift @_; my $t = translate($s);
    $t && ref $t or return sprintf $t, @_;
    my ($T, @p) = @$t;
    sprintf $T, @_[@p];
}
#-delete $main::{'_'};
sub __ { $_[0] }
sub even($) { $_[0] % 2 == 0 }
sub odd($)  { $_[0] % 2 == 1 }
sub min { fold_left { $a < $b ? $a : $b } @_ }
sub max { fold_left { $a > $b ? $a : $b } @_ }
sub sum { fold_left { $a + $b } @_ }
sub and_{ fold_left { $a && $b } @_ }
sub or_ { fold_left { $a || $b } @_ }
sub sqr { $_[0] * $_[0] }
sub sign { $_[0] <=> 0 }
sub product { fold_left { $a * $b } @_ }
sub first { $_[0] }
sub second { $_[1] }
sub top { $_[-1] }
sub uniq { my %l; @l{@_} = (); keys %l }
sub to_int { $_[0] =~ /(\d*)/; $1 }
sub to_float { $_[0] =~ /(\d*(\.\d*)?)/; $1 }
sub ikeys { my %l = @_; sort { $a <=> $b } keys %l }
sub add2hash($$)  { my ($a, $b) = @_; while (my ($k, $v) = each %{$b || {}}) { $a->{$k} ||= $v } $a }
sub add2hash_($$) { my ($a, $b) = @_; while (my ($k, $v) = each %{$b || {}}) { exists $a->{$k} or $a->{$k} = $v } $a }
sub member { my $e = shift; foreach (@_) { $e eq $_ and return 1 } 0 }
sub dirname { @_ == 1 or die "usage: dirname <name>\n"; local $_ = shift; s|[^/]*/*\s*$||; s|(.)/*$|$1|; $_ || '.' }
sub basename { @_ == 1 or die "usage: basename <name>\n"; local $_ = shift; s|/*\s*$||; s|.*/||; $_ }
sub bool($) { $_[0] ? 1 : 0 }
sub invbool { my $a = shift; $$a = !$$a; $$a }
sub listlength { scalar @_ }
sub bool2text { $_[0] ? "true" : "false" }
sub bool2yesno { $_[0] ? "yes" : "no" }
sub text2bool { my $t = lc($_[0]); $t eq "true" || $t eq "yes" ? 1 : 0 }
sub strcpy { substr($_[0], $_[2] || 0, length $_[1]) = $_[1] }
sub cat_ { local *F; open F, $_[0] or $_[1] ? die "cat of file $_[0] failed: $!\n" : return; my @l = <F>; wantarray ? @l : join '', @l }
sub cat__ { my ($f) = @_; my @l = <$f>; wantarray ? @l : join '', @l }
sub output { my $f = shift; local *F; open F, ">$f" or die "output in file $f failed: $!\n"; print F foreach @_; }
sub deref { ref $_[0] eq "ARRAY" ? @{$_[0]} : ref $_[0] eq "HASH" ? %{$_[0]} : $_[0] }
sub linkf { unlink $_[1]; link $_[0], $_[1] }
sub symlinkf { unlink $_[1]; symlink $_[0], $_[1] }
sub chop_ { map { my $l = $_; chomp $l; $l } @_ }
sub divide { my $d = int $_[0] / $_[1]; wantarray ? ($d, $_[0] % $_[1]) : $d }
sub round { int ($_[0] + 0.5) }
sub round_up { my ($i, $r) = @_; $i += $r - ($i + $r - 1) % $r - 1; }
sub round_down { my ($i, $r) = @_; $i -= $i % $r; }
sub is_empty_array_ref { my $a = shift; !defined $a || @$a == 0 }
sub is_empty_hash_ref { my $a = shift; !defined $a || keys(%$a) == 0 }
sub difference2 { my %l; @l{@{$_[1]}} = (); grep { !exists $l{$_} } @{$_[0]} }
sub intersection { my (%l, @m); @l{@{shift @_}} = (); foreach (@_) { @m = grep { exists $l{$_} } @$_; %l = (); @l{@m} = (); } keys %l }

sub set_new(@) { my %l; @l{@_} = undef; { list => [ @_ ], hash => \%l } }
sub set_add($@) { my $o = shift; foreach (@_) { exists $o->{hash}{$_} and next; push @{$o->{list}}, $_; $o->{hash}{$_} = undef } }

sub sync { syscall_('sync') }
sub gettimeofday { my $t = pack "LL"; syscall_('gettimeofday', $t, 0) or die "gettimeofday failed: $!\n"; unpack("LL", $t) }
sub unix2dos { local $_ = $_[0]; s/\015$//mg; s/$/\015/mg; $_ }

sub remove_spaces { local $_ = shift; s/^ +//; s/ +$//; $_ }
sub mode { my @l = stat $_[0] or die "unable to get mode of file $_[0]: $!\n"; $l[2] }
sub psizeof { length pack $_[0] }

sub concat_symlink {
    my ($f, $l) = @_;
    $l =~ m|^\.\./(/.*)| and return $1;

    $f =~ s|/$||;
    while ($l =~ s|^\.\./||) { 
	$f =~ s|/[^/]+$|| or die "concat_symlink: $f $l\n";
    }
    "$f/$l";
}

sub expand_symlinks {
    my ($first, @l) = split '/', $_[0];
    $first eq '' or die "expand_symlinks: $_[0] is relative\n";
    my ($f, $l);
    foreach (@l) {
	$f .= "/$_";
	$f = concat_symlink($f, "../$l") while $l = readlink $f;
    }
    $f;
}

sub arch() {
    require c;
    c::kernel_arch();
}
sub better_arch {
    my ($new, $old) = @_;
    while ($new && $new ne $old) { $new = $compat_arch{$new} }
    $new;
}
sub compat_arch { better_arch(arch(), $_[0]) }

sub touch {
    my ($f) = @_;
    unless (-e $f) {
	local *F;
	open F, ">$f";
    }
    my $now = time;
    utime $now, $now, $f;
}

sub mapgrep(&@) {
    my $f = shift;
    my @l;
    foreach (@_) {
	my ($b, $v) = $f->($_);
	push @l, $v if $b;
    }
    @l;
}

sub map_index(&@) {
    my $f = shift;
    my @v; local $::i = 0;
    map { @v = &$f($::i); $::i++; @v } @_;
}
sub grep_index(&@) {
    my $f = shift;
    my $v; local $::i = 0;
    grep { $v = &$f($::i); $::i++; $v } @_;
}
sub find_index(&@) {
    my $f = shift;
    local $_;
    for (my $i = 0; $i < @_; $i++) {
	$_ = $_[$i];
	&$f and return $i;
    }
    die "find_index failed in @_";
}

sub map_each(&%) {
    my ($f, %h) = @_;
    my @l;
    local ($::a, $::b);
    while (($::a, $::b) = each %h) { push @l, &$f($::a, $::b) }
    @l;
}
sub grep_each(&%) {
    my ($f, %h) = @_;
    my %l;
    local ($::a, $::b);
    while (($::a, $::b) = each %h) { $l{$::a} = $::b if &$f($::a, $::b) }
    %l;
}
sub list2kv(@) { [ grep_index { even($::i) } @_ ], [ grep_index { odd($::i) } @_ ] }

sub combine {
    my $nb = shift;
    my @l; while (my @m = splice(@_, 0, $nb)) { push @l, \@m }
    @l;
}

#- pseudo-array-hash :)
sub map_tab_hash(&$@) {
    my ($f, $fields, @tab_hash) = @_;
    my %hash;
    my $key = { map_index {($_, $::i + 1)} @{$fields} };

    for (my $i = 0; $i < @tab_hash; $i += 2) {
	my $h = [$key, @{$tab_hash[$i + 1]}];
	&$f($i, $h) if $f;
	$hash{ $tab_hash[$i] } = $h;
      }
    %hash;
}

sub smapn {
    my $f = shift;
    my $n = shift;
    my @r = ();
    for (my $i = 0; $i < $n; $i++) { push @r, &$f(map { $_->[$i] } @_); }
    @r
}
sub mapn(&@) {
    my $f = shift;
    smapn($f, min(map { scalar @$_ } @_), @_);
}
sub mapn_(&@) {
    my $f = shift;
    smapn($f, max(map { scalar @$_ } @_), @_);
}


sub add_f4before_leaving {
    my ($f, $b, $name) = @_;

    unless ($common::before_leaving::{$name}) {
	no strict 'refs';
	${"common::before_leaving::$name"} = 1;
	${"common::before_leaving::list"} = 1;
    }
    local *N = *{$common::before_leaving::{$name}};
    my $list = *common::before_leaving::list;
    $list->{$b}{$name} = $f;
    *N = sub {
	my $f = $list->{$_[0]}{$name} or die '';
	$name eq 'DESTROY' and delete $list->{$_[0]};
	goto $f;
    } unless defined &{*N};

}

#- ! the functions are not called in the order wanted, in case of multiple before_leaving :(
sub before_leaving(&) {
    my ($f) = @_;
    my $b = bless {}, 'common::before_leaving';
    add_f4before_leaving($f, $b, 'DESTROY');
    $b;
}

sub catch_cdie(&&) {
    my ($f, $catch) = @_;

    local @common::cdie_catches;
    unshift @common::cdie_catches, $catch;
    &$f();
}

sub cdie($;&) {
    my ($err, $f) = @_;
    foreach (@common::cdie_catches) {
	$@ = $err;
	&{$_}(\$err) and return;
    }
    die $err;
}

sub all {
    my $d = shift;

    local *F;
    opendir F, $d or return;
    my @l = grep { $_ ne '.' && $_ ne '..' } readdir F;
    closedir F;

    @l;
}

sub glob_ {
    my ($d, $f) = ($_[0] =~ /\*/) ? (dirname($_[0]), basename($_[0])) : ($_[0], '*');

    $d =~ /\*/ and die "glob_: wildcard in directory not handled ($_[0])\n";
    ($f = quotemeta $f) =~ s/\\\*/.*/g;

    $d =~ m|/$| or $d .= '/';
    map { $d eq './' ? $_ : "$d$_" } grep { /^$f$/ } all($d);
}


sub syscall_ {
    my $f = shift;

    require 'syscall.ph';
    syscall(&{$common::{"SYS_$f"}}, @_) == 0;
}

sub salt($) {
    my ($nb) = @_;
    require 'devices.pm';
    open F, devices::make("random") or die "missing random";
    my $s; read F, $s, $nb;
    local $_ = pack "b8" x $nb, unpack "b6" x $nb, $s;
    tr [\0-\x3f] [0-9a-zA-Z./];
    $_;
}

sub makedev { ($_[0] << 8) | $_[1] }
sub unmakedev { $_[0] >> 8, $_[0] & 0xff }

sub list_passwd() {
    my (@l, @e);
    setpwent();
    while (@e = getpwent()) { push @l, [ @e ] }
    endpwent();
    @l;
}
sub list_home() {
    map { $_->[7] } grep { $_->[2] >= 500 } list_passwd();
}
sub list_skels { 
    my ($prefix, $suffix) = @_;
    map { "$prefix$_/$suffix" } '/etc/skel', '/root', list_home() }

sub translate {
    my ($s) = @_;
    my ($lang) = $ENV{LANGUAGE} || $ENV{LC_MESSAGES} || $ENV{LC_ALL} || $ENV{LANG} || 'en';

    require lang;
    foreach (split ':', $lang) {
	lang::load_po($_) unless defined $po::I18N::{$_};
	if (%{$po::I18N::{$_}}) {
	    return if $s eq '_I18N_';
	    return ${$po::I18N::{$_}}{$s} || $s 
	}
    }
    $s;
}

sub untranslate($@) {
    my $s = shift || return;
    foreach (@_) { translate($_) eq $s and return $_ }
    die "untranslate failed";
}

sub warp_text($;$) {
    my ($text, $width) = @_;
    $width ||= 80;

    my @l;
    foreach (split "\n", $text) {
	my $t = '';
	foreach (split /\s+/, $_) {
	    if (length "$t $_" > $width) {
		push @l, $t;
		$t = $_;
	    } else {
		$t = "$t $_";
	    }
	}
	push @l, $t;
    }
    @l;
}

sub formatAlaTeX($) {
    my ($t, $tmp);
    foreach (split "\n", $_[0]) {
	if (/^$/) {
	    $t .= ($t && "\n") . $tmp;
	    $tmp = '';
	} else {
	    $tmp = ($tmp && "$tmp ") . first(/^\s*(.*?)\s*$/);
	}
    }
    $t . ($t && $tmp && "\n") . $tmp;
}

sub formatLines($) {
    my ($t, $tmp);
    foreach (split "\n", $_[0]) {
	if (/^\s/) {
	    $t .= "$tmp\n";
	    $tmp = $_;
	} else {
	    $tmp = ($tmp ? "$tmp " : ($t && "\n") . $tmp) . $_;
	}
    }
    "$t$tmp\n";
}

sub getVarsFromSh($) {
    my %l;
    local *F;
    open F, $_[0] or return;
    foreach (<F>) {
	my ($v, $val, $val2) =
	  /^\s*			# leading space
	   (\w+) =		# variable
	   (
   	       "([^"]*)"	# double-quoted text
   	     | '([^']*)'	# single-quoted text
   	     | [^'"\s]+		# normal text
           )
           \s*$			# end of line
          /x or next;
	$l{$v} = $val2 || $val;
    }
    %l;
}

sub setVarsInSh {
    my ($file, $l, @fields) = @_;
    @fields = keys %$l unless @fields;

    local *F;
    open F, "> $_[0]" or die "cannot create config file $file";
    $l->{$_} and print F "$_=$l->{$_}\n" foreach @fields;
}
sub setVarsInCsh {
    my ($file, $l, @fields) = @_;
    @fields = keys %$l unless @fields;

    local *F;
    open F, "> $_[0]" or die "cannot create config file $file";
    $l->{$_} and print F "setenv $_ $l->{$_}\n" foreach @fields;
}

sub template2file {
    my ($in, $out, %toreplace) = @_;
    output $out, map { s/@@@(.*?)@@@/$toreplace{$1}/g; $_ } cat_($in);
}
sub template2userfile {
    my ($prefix, $in, $out_rel, $force, %toreplace) = @_;

    foreach (list_skels($prefix, $out_rel)) {
	-d dirname($_) or !-e $_ or $force or next;

	template2file($in, $_, %toreplace);
	m|/home/(.+?)/| and chown(getpwnam($1), getgrnam($1), $_);
    }
}
sub update_userkderc {
    my ($prefix, $category, %subst) = @_;

    foreach my $file (list_skels($prefix, '.kderc')) {
	output $file,
	  (map {
	      my $l = $_;
	      s/^\s*//;
	      if (my $i = /^\[$category\]/i ... /^\[/) {
		  if ($i =~ /E/) { #- for last line of category
		      $l = join('', values %subst) . $l;
		      %subst = ();
		  } elsif (/^(\w*?)=/) {
		      if (my $e = delete $subst{lc($1)}) {
			  $l = "$1=$e\n";
		      }
		  }
	      }
	      $l;
	  } cat_($file)),
	  (%subst && "[$category]\n", values %subst); #- if category has not been found above.
    }
}

sub substInFile(&@) {
    my $f = shift;
    foreach my $file (@_) {
	if (-e $file) {
	    local @ARGV = $file;
	    local ($^I, $_) = '';
	    while (<>) { &$f($_); print }
	} else {
	    local *F; my $old = select F; # that way eof return true
	    local $_ = '';
	    &$f($_);
	    select $old;
	    eval { output($file, $_) };
	}
    }
}

sub best_match {
    my ($str, @lis) = @_;
    my @words = split /\W+/, $str;
    my ($max, $res) = 0;

    foreach (@lis) {
	my $count = 0;
	foreach my $i (@words) {
	    $count++ if /$i/i;
	}
	$max = $count, $res = $_ if $count >= $max;
    }
    $res;
}

sub bestMatchSentence {

    my $best = -1;
    my $bestSentence;
    my @s = split /\W+/, shift;
    foreach (@_) {
	my $count = 0;
	foreach my $e (@s) {
	    $count++ if /$e/i;
	}
	$best = $count, $bestSentence = $_ if $count > $best;
    }
    $bestSentence;
}

# count the number of character that match
sub bestMatchSentence2 {

    my $best = -1;
    my $bestSentence;
    my @s = split /\W+/, shift;
    foreach (@_) {
	my $count = 0;
	foreach my $e (@s) {
	    $count+= length ($e) if /$e/i;
	}
	$best = $count, $bestSentence = $_ if $count > $best;
    }
    $bestSentence;
}

sub typeFromMagic($@) {
    my $f = shift;
    local *F; sysopen F, $f, 0 or return;

    my $tmp;
  M: foreach (@_) {
	my ($name, @l) = @$_;
	while (@l) {
	    my ($offset, $signature) = splice(@l, 0, 2);
	    sysseek(F, $offset, 0) or next M;
	    sysread(F, $tmp, length $signature);
	    $tmp eq $signature or next M;
	}
	return $name;
    }
    undef;
}

sub availableMemory() { sum map { /(\d+)/ } grep { /^(MemTotal|SwapTotal):/ } cat_("/proc/meminfo"); }
sub availableRamMB()  { 4 * int ((stat("/proc/kcore"))[7] / 1024 / 1024 / 4 + 0.5) }

sub setVirtual($) {
    my $vt = '';
    local *C;
    sysopen C, "/dev/console", 2 or die "failed to open /dev/console: $!";
    ioctl(C, c::VT_GETSTATE(), $vt) or die "ioctl VT_GETSTATE failed";
    ioctl(C, c::VT_ACTIVATE(), $_[0]) or die "ioctl VT_ACTIVATE failed";
    ioctl(C, c::VT_WAITACTIVE(), $_[0]) or die "ioctl VT_WAITACTIVE failed";
    unpack "S", $vt;
}


sub removeXiBSuffix($) {
    local $_ = shift;

    /(\d+)k$/i and return $1 * 1024;
    /(\d+)M$/i and return $1 * 1024 * 1024;
    /(\d+)G$/i and return $1 * 1024 * 1024 * 1024;
    $_;
}

sub formatTime {
    my ($s, $m, $h) = gmtime($_[0]);
    if ($h) {
	sprintf "%02d:%02d", $h, $m;
    } elsif ($m > 1) {
	_("%d minutes", $m);
    } elsif ($m == 1) {
	_("1 minute");
    } else {
	_("%d seconds", $s);
    }
}
sub formatTimeRaw {
    my ($s, $m, $h) = gmtime($_[0]);
    sprintf "%d:%02d:%02d", $h, $m, $s;
}

#- return the size of the partition and its free space in KiB
sub df {
    my ($mntpoint) = @_;
    my ($blocksize, $size, $free);
    my $buf = ' ' x 20000;
    syscall_('statfs', $mntpoint, $buf) or return;
    (undef, $blocksize, $size, $free, undef, undef) = unpack "L6", $buf;
    map { $_ * ($blocksize / 1024) } $size, $free;
}

sub next_val_in_array {
    my ($v, $l) = @_;
    my %l = mapn { @_ } $l, [ @$l[1..$#$l], $l->[0] ];
    $l{$v};
}


#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
