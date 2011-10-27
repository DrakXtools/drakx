#!/usr/bin/perl

@ARGV == 1 && chdir $ARGV[0] or die "usage: devices.pl <dir>\n";

foreach (<DATA>) {
    chomp;
    my ($typ, $maj, $min, @l) = split;
    foreach (@l) {
	my @l2 = do {
	    if (my ($prefix, $ini, $end) = /(.*)(\d+)-(\d+)$/) {
		map { "$prefix$_" } $ini .. $end;
	    } else {
		$_;
	    }
	};
	foreach (@l2) {
	    my $cmd = "mknod-m600 $_ $typ $maj " . $min++;
	    system($cmd) == 0 or die "$cmd failed\n";
	}
    }
}

__DATA__
c   5   1 console
b   2   0 fd0-1
c   1   2 kmem
b   7   0 loop0-15
c   1   1 mem
c   1   3 null
c   1   4 port
b   1   1 ram
b   1   0 ram0-19
b   1   0 ramdisk
c   1   8 random
b  11   0 scd0-7
c   0   0 stderr
c   0   0 stdin
c   0   0 stdout
c   5   0 tty
c   4   0 tty0-9
c   4  64 ttyS0-3
c   1   9 urandom
c   1   5 zero
b   3   0 hda hda1-16
b   3  64 hdb hdb1-16
b  22   0 hdc hdc1-16
b  22  64 hdd hdd1-16
b  33   0 hde hde1-16
b  33  64 hdf hdf1-16
b  34   0 hdg hdg1-16
b  34  64 hdh hdh1-16
b   8   0 sda sda1-15 sdb sdb1-15 sdc sdc1-15 sdd sdd1-15 sde sde1-15 sdf sdf1-15 sdg sdg1-15 sdh sdh1-15
b   9   0 md0-15
c  10 144 nvram
c   9   0 st0-15
