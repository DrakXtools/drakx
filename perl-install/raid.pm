package raid; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table qw(:types);
use run_program;
use devices;
use commands;
use modules;
use fs;

sub nb { 
    my ($nb) = @_;
    first((ref $nb ? $nb->{device} : $nb) =~ /(\d+)/);
}

sub new {
    my ($raids, @parts) = @_;
    my $nb = @$raids; 
    $raids->[$nb] = { 'chunk-size' => "64k", type => 0x83, disks => [ @parts ], device => "md$nb", notFormatted => 1, level => 1 };
    foreach my $part (@parts) {
	$part->{raid} = $nb;
	delete $part->{mntpoint};
    }
    update($raids->[$nb]);
    $nb;
}

sub add {
    my ($raids, $part, $nb) = @_; $nb = nb($nb);
    $raids->[$nb]{isMounted} and die _("Can't add a partition to _formatted_ RAID md%d", $nb);
    $part->{raid} = $nb;
    delete $part->{mntpoint};
    push @{$raids->[$nb]{disks}}, $part;
    update($raids->[$nb]);
}

sub delete {
    my ($raids, $nb) = @_;
    $nb = nb($nb);

    delete $_->{raid} foreach @{$raids->[$nb]{disks}};
    undef $raids->[$nb];
}

sub changeNb {
    my ($raids, $oldnb, $newnb) = @_;
    if ($oldnb != $newnb) {
	($raids->[$newnb], $raids->[$oldnb]) = ($raids->[$oldnb], undef);
	$raids->[$newnb]{device} = "md$newnb";
	$_->{raid} = $newnb foreach @{$raids->[$newnb]{disks}};
    }
    $newnb;
}

sub removeDisk {
    my ($raids, $part) = @_;
    my $nb = nb($part->{raid});
    run_program::run("raidstop", devices::make($part->{device}));
    delete $part->{raid};
    my $disks = $raids->[$nb]{disks};
    @$disks = grep { $_ != $part } @$disks;
    if (@$disks) {
	update($raids->[$nb]);
    } else {
	undef $raids->[$nb];
    }
}

sub updateSize {
    my ($part) = @_;
    local $_ = $part->{level};
    my @l = map { $_->{size} } @{$part->{disks}};

    $part->{size} = do {
	if (/0|linear/) { sum @l        }
	elsif (/1/  )   { min @l        }
	elsif (/4|5/)   { min(@l) * $#l }
    };
}

sub module {
    my ($part) = @_;
    my $mod = $part->{level};

    $mod = 5 if $mod eq "4";
    $mod = "raid$mod" if $mod =~ /^\d+$/;
    $mod;
}

sub updateIsFormatted {
    my ($part) = @_;
    $part->{isFormatted}  = and_ map { $_->{isFormatted}  } @{$part->{disks}};
    $part->{notFormatted} = and_ map { $_->{notFormatted} } @{$part->{disks}};
}
sub update {
    foreach (@_) {
	updateSize($_);
	updateIsFormatted($_);
    }
}

sub write {
    my ($raids, $file) = @_;
    local *F;
    local $\ = "\n";
    open F, ">$file" or die _("Can't write file %s", $file);

    foreach (grep {$_} @$raids) {
	print F <<"EOF";
raiddev       /dev/$_->{device}
raid-level    $_->{level}
chunk-size    $_->{'chunk-size'}
persistent-superblock 1
EOF
	print F "nr-raid-disks ", int @{$_->{disks}};
	map_index {	    
	    print F "    device    ", devices::make($_->{device});
	    print F "    raid-disk $::i";
	} @{$_->{disks}};
    }
}

sub make {
    my ($raids, $part) = @_;
    isRAID($_) and make($raids, $_) foreach @{$part->{disks}};
    my $dev = devices::make($part->{device});
    eval { modules::load(module($part)) };
    &write($raids, "/etc/raidtab");
    run_program::run("raidstop", $dev);
    run_program::run("mkraid", "--really-force", $dev) or die
	$::isStandalone ? _("mkraid failed (maybe raidtools are missing?)") : _("mkraid failed");
}

sub format_part {
    my ($raids, $part) = @_;
    $part->{isFormatted} and return;

    make($raids, $part);
    fs::real_format_part($part);
    $_->{isFormatted} = 1 foreach @{$part->{disks}};
}

sub verify {
    my ($raids) = @_;
    $raids or return;
    foreach (grep {$_} @$raids) {
	@{$_->{disks}} >= ($_->{level} =~ /4|5/ ? 3 : 2) or die _("Not enough partitions for RAID level %d\n", $_->{level});
    }
}

sub prepare_prefixed {
    my ($raids, $prefix) = @_;
    $raids or return;

    eval { commands::cp("-f", "/etc/raidtab", "$prefix/etc/raidtab") };
    foreach (grep {$_} @$raids) {
	devices::make("$prefix/dev/$_->{device}") foreach @{$_->{disks}};
    }
}

sub stopAll() { run_program::run("raidstop", devices::make("md$_")) foreach 0..7 }

1;
