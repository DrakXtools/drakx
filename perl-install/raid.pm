package raid;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :functional);
use run_program;
use devices;
use commands;
use fs;

sub nb($) { 
    my ($nb) = @_;
    first((ref $nb ? $nb->{device} : $nb) =~ /(\d+)/);
}

sub is($) {
    my ($part) = @_;
    $part->{device} =~ /^md/;
}

sub new($$) {
    my ($raid, $part) = @_;
    my $nb = @$raid; 
    $raid->[$nb] = { 'chunk-size' => "64k", type => 0x83, disks => [ $part ], device => "md$nb", notFormatted => 1 };
    $part->{raid} = $nb;
}

sub add($$$) {
    my ($raid, $part, $nb) = @_;
    $raid->[$nb]{isMounted} and die _("Can't add a partition to _formatted_ RAID md%d", $nb);
    $part->{raid} = $nb;
    push @{$raid->[$nb]{disks}}, $part;
}

sub delete($$) {
    my ($raid, $nb) = @_;
    $nb = nb($nb);

    delete $_->{raid} foreach @{$raid->[$nb]{disks}};
    $raid->[$nb] = undef;
}

sub removeDisk($$) {
    my ($raid, $part) = @_;
    my $nb = nb($part->{raid});
    delete $part->{raid};
    @{$raid->[$nb]{disks}} = grep { $_ != $part } @{$raid->[$nb]{disks}};
    update($raid->[$nb]);
}

sub updateSize($) {
    my ($part) = @_;
    local $_ = $part->{level};
    my @l = map { $_->{size} } @{$part->{disks}};

    $part->{size} = do {
	if (/0|linear/) { sum @l        }
	elsif (/1/  )   { min @l        }
	elsif (/4|5/)   { min(@l) * $#l }
    };
}

sub module($) {
    my ($part) = @_;
    my $mod = $part->{level};

    $mod = 5 if $mod eq "4";
    $mod = "raid$mod" if $mod =~ /^\d+$/;
    $mod;
}

sub updateIsFormatted($) {
    my ($part) = @_;
    $part->{isFormatted}  = and_ map { $_->{isFormatted}  } @{$part->{disks}};
    $part->{notFormatted} = and_ map { $_->{notFormatted} } @{$part->{disks}};
}
sub update($) {
    &updateSize;
    &updateIsFormatted;
}

sub write($) {
    my ($raid, $file) = @_;
    local *F;
    local $\ = "\n";

    foreach (grep {$_} @$raid) {
	open F, ">$file" or die _("Can't write file $file");
	print F <<"EOF";
raiddev       /dev/$_->{device}
raid-level    $_->{level}
chunk-size    $_->{'chunk-size'}
persistent-superblock 1
EOF
	print F "nr-raid-disks ", int @{$_->{disks}};
	map_index {
	    print F "    device    /dev/$_->{device}";
	    print F "    raid-disk $::i";
	} @{$_->{disks}};
    }
}

sub make($$) {
    my ($raid, $part) = @_;
    my $dev = devices::make($part->{device});
    eval { commands::modprobe(module($part)) };
    run_program::run("raidstop", $dev);
    &write($raid, "/etc/raidtab");
    run_program::run("mkraid", "--really-force", $dev);
    run_program::run("raidstart", $dev);
}

sub format_part($$) {
    my ($raid, $part) = @_;
    make($raid->{raid}, $part) if is($part);
    fs::format_part($part);
}

sub verify($) {
    my ($raid) = @_;
    $raid && $raid->{raid} or return;
    foreach (@{$raid->{raid}}) {
	@{$_->{disks}} >= ($_->{level} =~ /4|5/ ? 3 : 2) or die _("Not enough partitions for RAID level %d\n", $_->{level});
    }
}

1;
