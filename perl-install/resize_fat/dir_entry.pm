package resize_fat::dir_entry; # $Id$

use diagnostics;
use strict;


my $DELETED_FLAG      = 0xe5;

my $READ_ONLY_ATTR    = 0x01;
my $HIDDEN_ATTR       = 0x02;
my $SYSTEM_ATTR       = 0x04;
my $VOLUME_LABEL_ATTR = 0x08;
my $VFAT_ATTR         = 0x0f;
my $DIRECTORY_ATTR    = 0x10;

1;

sub get_cluster($) {
    my ($entry) = @_;
    $entry->{first_cluster} + ($resize_fat::isFAT32 ? $entry->{first_cluster_high} * (1 << 16) : 0);
}
sub set_cluster($$) {
    my ($entry, $val) = @_;
    $entry->{first_cluster} = $val & ((1 << 16) - 1);
    $entry->{first_cluster_high} = $val >> 16 if $resize_fat::isFAT32;
}

sub is_unmoveable($) {
    my ($entry) = @_;
    $entry->{attributes} & $HIDDEN_ATTR || $entry->{attributes} & $SYSTEM_ATTR;
}

sub is_directory($) {
    my ($entry) = @_;
    $entry->{attributes} & $DIRECTORY_ATTR && $entry->{name} !~ /^\.\.? / && !is_special_entry($entry);
}

sub is_volume($) {
    my ($entry) = @_;
    !is_special_entry($entry) && $entry->{attributes} & $VOLUME_LABEL_ATTR;
}

sub is_file($) {
    my ($entry) = @_;
    !is_special_entry($entry) && !is_directory($entry) && !is_volume($entry) && $entry->{length};
}


sub is_special_entry($) {
    my ($entry) = @_;
    my ($c) = unpack "C", $entry->{name};

    #- skip empty slots, deleted files, and 0xF6?? (taken from kernel)
    $c == 0 || $c == $DELETED_FLAG || $c == 0xF6 and return 1;

    $entry->{attributes} == $VFAT_ATTR and return 1;
    0;
}


#- return true if entry has been modified
#- curr_dir_name is added to contains current directory name, "" for root.
sub remap {
    my ($curr_dir_name, $entry) = @_;

    is_special_entry($entry) and return;

    my $cluster = get_cluster($entry);
    my $new_cluster = resize_fat::c_rewritten::fat_remap($cluster);

    #-print "remapping cluster ", get_cluster($entry), " to $new_cluster";

    $new_cluster == $cluster and return; #- no need to modify

    set_cluster($entry, $new_cluster);
    1;
}
