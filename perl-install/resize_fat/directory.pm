package resize_fat::directory;

use diagnostics;
use strict;

use common qw(:system);
use resize_fat::dir_entry;
use resize_fat::io;


my $format = "a8 a3 C C C S7 I";
my @fields = (
    'name',
    'extension',
    'attributes',
    'is_upper_case_name',
    'creation_time_low',	# milliseconds
    'creation_time_high',
    'creation_date',
    'access_date',
    'first_cluster_high',	# for FAT32
    'time',
    'date',
    'first_cluster',
    'length',
);

1;

sub entry_size { psizeof($format) }

# call `f' for each entry of the directory
# if f return true, then modification in the entry are taken back
sub traverse($$$) {
    my ($fs, $directory, $f) = @_;

    for (my $i = 0;; $i++) {
	my $raw = \substr($directory, $i * psizeof($format), psizeof($format));

	# empty entry means end of directory
	$$raw =~ /^\0*$/ and return $directory;

	my $entry; @{$entry}{@fields} = unpack $format, $$raw;

	&$f($entry) 
	    and	$$raw = pack $format, @{$entry}{@fields};
    }
    $directory;
}

sub traverse_all($$) {
    my ($fs, $f) = @_;

    my $traverse_all; $traverse_all = sub {
	my ($entry) = @_;

	&$f($entry);

        resize_fat::dir_entry::is_directory($entry) 
	    and traverse($fs, resize_fat::io::read_file($fs, resize_fat::dir_entry::get_cluster($entry)), $traverse_all);

	undef; # no need to write back (cf traverse)
    };

    my $directory = $resize_fat::isFAT32 ?
	resize_fat::io::read_file($fs, $fs->{fat32_root_dir_cluster}) :
	resize_fat::io::read($fs, $fs->{root_dir_offset}, $fs->{root_dir_size});
    traverse($fs, $directory, $traverse_all);
}


# function used by construct_dir_tree to translate the `cluster' fields in each
# directory entry
sub remap {
    my ($fs, $directory) = @_;

    traverse($fs->{fat_remap}, $directory, sub { resize_fat::dir_entry::remap($fs->{fat_remap}, $_[0]) });
}
