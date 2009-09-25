package resize_fat::info_sector; # $Id$

use diagnostics;
use strict;

use common;
use resize_fat::io;

#- Oops, this will be unresizable on big-endian machine. trapped by signature.
my $format = "a484 I I I a16";
my @fields = (
    'unused',
    'signature',		#- should be 0x61417272
    'free_clusters',		#- -1 for unknown
    'next_cluster',		#- most recently allocated cluster
    'unused2',
);

1;


sub read($) {
    my ($fs) = @_;
    my $info = resize_fat::io::read($fs, $fs->{info_offset}, psizeof($format));
    @{$fs->{info_sector}}{@fields} = unpack $format, $info;
    $fs->{info_sector}{signature} == 0x61417272 or die "Invalid information sector signature\n";
}

sub write($) {
    my ($fs) = @_;
    $fs->{info_sector}{free_clusters} = $fs->{clusters}{count}{free};
    $fs->{info_sector}{next_cluster} = 2;

    my $info = pack $format, @{$fs->{info_sector}}{@fields};

    resize_fat::io::write($fs, $fs->{info_offset}, psizeof($format), $info);
}
