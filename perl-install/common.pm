package common;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $printable_chars $sizeof_int $bitof_int $cancel $SECTORSIZE);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    common     => [ qw(__ min max sum sign product bool bool2text ikeys member divide is_empty_array_ref add2hash set_new set_add round_up round_down first second top uniq translate untranslate warp_text) ],
    functional => [ qw(fold_left map_index map_tab_hash mapn mapn_ difference2 before_leaving catch_cdie cdie) ],
    file       => [ qw(dirname basename touch all glob_ cat_ chop_ mode) ],
    system     => [ qw(sync makedev unmakedev psizeof strcpy gettimeofday syscall_ crypt_ getVarsFromSh setVarsInSh) ],
    constant   => [ qw($printable_chars $sizeof_int $bitof_int $SECTORSIZE) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

$printable_chars = "\x20-\x7E";     
$sizeof_int      = psizeof("i");    
$bitof_int       = $sizeof_int * 8; 
$SECTORSIZE      = 512;             

1;

sub fold_left(&@) {
    my $f = shift;
    local $a = shift;
    foreach $b (@_) { $a = &$f() }
    $a
}

sub _ { my $s = shift @_; sprintf translate($s), @_ }
#delete $main::{'_'};
sub __ { $_[0] }
sub min { fold_left { $a < $b ? $a : $b } @_ }
sub max { fold_left { $a > $b ? $a : $b } @_ }
sub sum { fold_left { $a + $b } @_ }
sub sign { $_[0] <=> 0 }
sub product { fold_left { $a * $b } @_ }
sub first { $_[0] }
sub second { $_[1] }
sub top { $_[$#_] }
sub uniq { my %l; @l{@_} = (); keys %l }
sub ikeys { my %l = @_; sort { $a <=> $b } keys %l }
sub add2hash { my ($a, $b) = @_; while (my ($k, $v) = each %{$b || {}}) { $a->{$k} ||= $v } }
sub member { my $e = shift; foreach (@_) { $e eq $_ and return 1 } 0 }
sub dirname { @_ == 1 or die "usage: dirname <name>\n"; local $_ = shift; s|[^/]*/*\s*$||; s|(.)/*$|$1|; $_ || '.' }
sub basename { @_ == 1 or die "usage: basename <name>\n"; local $_ = shift; s|/*\s*$||; s|.*/||; $_ }
sub bool { $_[0] ? 1 : 0 }
sub bool2text { $_[0] ? "true" : "false" }
sub strcpy { substr($_[0], $_[2] || 0, length $_[1]) = $_[1] }
sub cat_ { local *F; open F, $_[0] or $_[1] ? die "cat of file $_[0] failed: $!\n" : return; my @l = <F>; wantarray ? @l : join '', @l }
sub chop_ { map { my $l = $_; chomp $l; $l } @_ }
sub divide { my $d = int $_[0] / $_[1]; wantarray ? ($d, $_[0] % $_[1]) : $d }
sub round_up { my ($i, $r) = @_; $i += $r - ($i + $r - 1) % $r - 1; }
sub round_down { my ($i, $r) = @_; $i -= $i % $r; }
sub is_empty_array_ref { my $a = shift; !defined $a || @$a == 0 }
sub difference2 { my %l; @l{@{$_[1]}} = (); grep { !exists $l{$_} } @{$_[0]} }
sub intersection { my (%l, @m); @l{@{shift @_}} = (); foreach (@_) { @m = grep { exists $l{$_} } @$_; %l = (); @l{@m} = (); } keys %l }

sub set_new(@) { my %l; @l{@_} = undef; { list => [ @_ ], hash => \%l } }
sub set_add($@) { my $o = shift; foreach (@_) { exists $o->{hash}{$_} and next; push @{$o->{list}}, $_; $o->{hash}{$_} = undef } }

sub sync { syscall_('sync') }
sub gettimeofday { my $t = pack "LL"; syscall_('gettimeofday', $t, 0) or die "gettimeofday failed: $!\n"; unpack("LL", $t) }

sub remove_spaces { local $_ = shift; s/^ +//; s/ +$//; $_ }
sub mode { my @l = stat $_[0] or die "unable to get mode of file $_[0]: $!\n"; $l[2] }
sub psizeof { length pack $_[0] }

sub touch {
    my $f = shift;
    unless (-e $f) {
	local *F;
	open F, ">$f";
    }
    my $now = time;
    utime $now, $now, $f;
}

sub map_index(&@) {
    my $f = shift;
    my @l;
    local $::i = 0;
    foreach (@_) { push @l, &$f($::i); $::i++; }
    @l;
}

#pseudo-array-hash :)
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
	my $f = $list->{$_[0]}{$name} or die;
	$name eq 'DESTROY' and delete $list->{$_[0]};
	goto $f;
    } unless defined &{*N};

}

# ! the functions are not called in the order wanted, in case of multiple before_leaving :(
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

sub cdie {
    $@ = join '', @_;
    foreach (@common::cdie_catches) {
	&{$_}(@_) and return;
    }
    die join '', @_;
}

sub all {
    my $d = shift;

    local *F;
    opendir F, $d or die "all: can't open dir $d: $!\n";
    grep { $_ ne '.' && $_ ne '..' } readdir F;
}

sub glob_ {
    my ($d, $f) = ($_[0] =~ /\*/) ? (dirname($_[0]), basename($_[0])) : ($_[0], '*');

    $d =~ /\*/ and die "glob_: wildcard in directory not handled ($_[0])\n";
    ($f = quotemeta $f) =~ s/\\\*/.*/g;

    $d =~ m|/$| or $d .= '/';
    map { $d eq './' ? $_ : "$d$_" } grep { /$f/ } all($d);
}


sub syscall_ {
    my $f = shift;

    require 'syscall.ph';
    syscall(&{$common::{"SYS_$f"}}, @_) == 0;
}


sub crypt_ {
    local $_ = (gettimeofday())[1] % 0x40;
    tr [\0-\x3f] [0-9a-zA-Z./];
    crypt($_[0], $_)
}

sub makedev { ($_[0] << 8) | $_[1] }
sub unmakedev { $_[0] >> 8, $_[0] & 0xff }

sub translate {
    my ($s) = @_;
    my ($lang) = substr($ENV{LC_ALL} || $ENV{LANGUAGE} || $ENV{LC_MESSAGES} || $ENV{LANG} || '', 0, 2);
    unless (defined $po::I18N::{$lang}) {
	local $@;
	local $SIG{__DIE__} = 'none';
	eval { require "po/$lang.pm"; };
    }
    $po::I18N::{$lang} or return $s;
    my $l = *{$po::I18N::{$lang}};
    $l->{$s} || $s;
}

sub untranslate($@) {
    my $s = shift;
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
