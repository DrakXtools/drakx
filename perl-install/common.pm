package common;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $printable_chars $sizeof_int $bitof_int $cancel $SECTORSIZE);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    common => [ qw(_ __ min max bool member divide is_empty_array_ref set_new set_add round_up round_down first second top uniq translate) ],
    file => [ qw(dirname basename all glob_ cat_ chop_ mode) ],
    system => [ qw(sync makedev unmakedev psizeof strcpy gettimeofday syscall_ crypt_) ],
    constant => [ qw($printable_chars $sizeof_int $bitof_int $SECTORSIZE) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

$printable_chars = "\x20-\x7E";
$sizeof_int = psizeof("i");
$bitof_int = $sizeof_int * 8;
$SECTORSIZE = 512;

1;

sub _ { my $s = shift @_; sprintf translate($s), @_ }
sub __ { $_[0] }
sub min { my $min = shift; grep { $_ < $min and $min = $_; } @_; $min }
sub max { my $max = shift; grep { $_ > $max and $max = $_; } @_; $max }
sub first { $_[0] }
sub second { $_[1] }
sub top { $_[$#_] }
sub uniq { my %l; @l{@_} = (); keys %l }
sub member { my $e = shift; foreach (@_) { $e eq $_ and return 1 } 0 }
sub dirname { @_ == 1 or die "usage: dirname <name>\n"; local $_ = shift; s|[^/]*/*\s*$||; s|(.)/*$|$1|; $_ || '.' }
sub basename { @_ == 1 or die "usage: basename <name>\n"; local $_ = shift; s|/*\s*$||; s|.*/||; $_ }
sub bool { $_[0] ? 1 : 0 }
sub strcpy { substr($_[0], $_[2] || 0, length $_[1]) = $_[1] }
sub cat_ { local *F; open F, $_[0] or $_[1] ? die "cat of file $_[0] failed: $!\n" : return; my @l = <F>; wantarray ? @l : join '', @l }
sub chop_ { map { my $l = $_; chomp $l; $l } @_ }
sub divide { my $d = int $_[0] / $_[1]; wantarray ? ($d, $_[0] % $_[1]) : $d }
sub round_up { my ($i, $r) = @_; $i += $r - ($i + $r - 1) % $r - 1; }
sub round_down { my ($i, $r) = @_; $i -= $i % $r; }
sub is_empty_array_ref { my $a = shift; !defined $a || @$a == 0 }

sub set_new(@) { my %l; @l{@_} = undef; { list => [ @_ ], hash => \%l } }
sub set_add($@) { my $o = shift; foreach (@_) { exists $o->{hash}->{$_} and next; push @{$o->{list}}, $_; $o->{hash}->{$_} = undef } }

sub sync { syscall_('sync') }
sub gettimeofday { my $t = pack "LL"; syscall_('gettimeofday', $t, 0) or die "gettimeofday failed: $!\n"; unpack("LL", $t) }

sub remove_spaces { local $_ = shift; s/^ +//; s/ +$//; $_ }
sub mode { my @l = stat $_[0] or die "unable to get mode of file $_[0]: $!\n"; $l[2] }
sub psizeof { length pack $_[0] }

sub all {
    my $d = shift;

    local *F;
    opendir F, $d or die "all: can't opendir $d: $!\n";
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
    unless (defined %po::I18N::I18N) {
	if (my ($lang) = ($ENV{LC_ALL} || $ENV{LANGUAGE} || $ENV{LC_MESSAGES} || $ENV{LANG}) =~ /(..)/) {
	    local $SIG{__DIE__} = 'none';
	    eval { require "po/$lang.pm" };
	}
    }
    $po::I18N::I18N{$s} || $s;
}
