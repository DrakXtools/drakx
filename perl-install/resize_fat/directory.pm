package resize_fat::directory; # $Id$

use diagnostics;
use strict;

use common;
use resize_fat::dir_entry;
use resize_fat::io;


my $format = "a8 a3 C C C S7 I";
my @fields = (
    'name',
    'extension',
    'attributes',
    'is_upper_case_name',
    'creation_time_low',	#- milliseconds
    'creation_time_high',
    'creation_date',
    'access_date',
    'first_cluster_high',	#- for FAT32
    'time',
    'date',
    'first_cluster',
    'length',
);
my $psizeof_format = psizeof($format);

1;

sub entry_size { $psizeof_format }

#- call `f' for each entry of the directory
#- if f return true, then modification in the entry are taken back
sub traverse($$$) {
    my ($directory, $curr_dir_name, $f) = @_;

    for (my $i = 0;; $i++) {
	my $raw = \substr($directory, $i * $psizeof_format, $psizeof_format);

	#- empty entry means end of directory
	$$raw =~ /^\0*$/ and return $directory;

	my $entry; @{$entry}{@fields} = unpack $format, $$raw;

	&$f($curr_dir_name, $entry)
	    and	$$raw = pack $format, @{$entry}{@fields};
    }
    $directory;
}

sub traverse_all($$) {
    my ($fs, $f) = @_;

    my $traverse_all; $traverse_all = sub {
	my ($curr_dir_name, $entry) = @_;

	&$f($curr_dir_name, $entry);

        resize_fat::dir_entry::is_directory($entry)
	    and traverse(resize_fat::io::read_file($fs, resize_fat::dir_entry::get_cluster($entry)), "$curr_dir_name/$entry->{name}", $traverse_all);

	undef; #- no need to write back (cf traverse)
    };

    my $directory = $resize_fat::isFAT32 ?
	resize_fat::io::read_file($fs, $fs->{fat32_root_dir_cluster}) :
	resize_fat::io::read($fs, $fs->{root_dir_offset}, $fs->{root_dir_size});
    traverse($directory, "", $traverse_all);
    undef $traverse_all; #- circular reference is no good for perl's poor GC :(
}


#- function used by construct_dir_tree to translate the `cluster' fields in each
#- directory entry
sub remap($$) {
    my ($fs, $directory) = @_;
    traverse($directory, "", \&resize_fat::dir_entry::remap);
}
