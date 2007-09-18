package fs::proc_partitions; # $Id$

use common;


sub read_raw() {
    my (undef, undef, @all) = cat_("/proc/partitions");
    grep {
	$_->{size} != 1 &&	  # skip main extended partition
	$_->{size} != 0x3fffffff; # skip cdroms (otherwise stops cd-audios)
    } map { 
	my %l; 
	@l{qw(major minor size dev)} = split; 
	\%l;
    } @all;
}

sub read {
    my ($hds) = @_;

    my @all = read_raw();
    my ($parts, $_disks) = partition { $_->{dev} =~ /\d$/ && $_->{dev} !~ /^(sr|scd)/ } @all;

    fs::get_major_minor($hds);

    my $prev_part;
    foreach my $part (@$parts) {
	my $dev = $part->{dev};
	if (my $hd = find { $part->{dev} =~ /^\Q$_->{device}\E./ } @$hds) {
	    put_in_hash($part, partition_table::hd2minimal_part($hd));
	}
	
	undef $prev_part if $prev_part && ($prev_part->{rootDevice} || '') ne ($part->{rootDevice} || '');

	$part->{device} = $dev;
	$part->{size} *= 2;	# from KB to sectors
	$part->{start} = $prev_part ? $prev_part->{start} + $prev_part->{size} : 0;
	require fs::type;
	put_in_hash($part, fs::type::type_subpart_from_magic($part));
	$prev_part = $part;
	delete $part->{dev}; # cleanup
    }
    @$parts;
}

sub compare {
    my ($hd) = @_;

    my @l1 = partition_table::get_normal_parts($hd);
    my @l2 = grep { $_->{rootDevice} eq $hd->{device} } &read([$hd]);

    #- /proc/partitions includes partition with type "empty" and a non-null size
    #- so add them for comparison
    my ($len1, $len2) = (int(@l1) + $hd->{primary}{nb_special_empty}, int(@l2));

    if ($len1 != $len2 && arch() ne 'ppc') {
	die sprintf(
		    "/proc/partitions does not agree with drakx %d != %d:\n%s\n", $len1, $len2,
		    "/proc/partitions: " . join(", ", map { "$_->{device} ($_->{rootDevice})" } @l2));
    }
    $len2;
}

sub use_ {
    my ($hd) = @_;

    require partition_table::readonly;
    partition_table::readonly->initialize($hd, [ grep { $_->{rootDevice} eq $hd->{device} } &read([$hd]) ]);
}

1;
