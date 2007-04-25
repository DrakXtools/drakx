package fs::mount_point; # $Id$

use diagnostics;
use strict;

use common;
use any;
use fs::type;

sub guess_mount_point {
    my ($part, $prefix, $user) = @_;

    my %l = (
	     '/'     => 'etc/fstab',
	     '/boot' => 'vmlinuz',
	     '/tmp'  => '.X11-unix',
	     '/usr'  => 'src',
	     '/var'  => 'catman',
	    );

    my $handle = any::inspect($part, $prefix) or return;
    my $d = $handle->{dir};
    my $mnt = find { -e "$d/$l{$_}" } keys %l;
    $mnt ||= (stat("$d/.bashrc"))[4] ? '/root' : '/home/user' . ++$$user if -e "$d/.bashrc";
    $mnt ||= (any { -d $_ && (stat($_))[4] >= 500 && -e "$_/.bashrc" } glob_($d)) ? '/home' : '';
    ($mnt, $handle);
}

sub suggest_mount_points {
    my ($fstab, $prefix, $uniq) = @_;

    my $user;
    foreach my $part (grep { isTrueFS($_) } @$fstab) {
	$part->{mntpoint} && !$part->{unsafeMntpoint} and next; #- if already found via an fstab

	my ($mnt, $handle) = guess_mount_point($part, $prefix, \$user) or next;

	next if $uniq && fs::get::mntpoint2part($mnt, $fstab);
	$part->{mntpoint} = $mnt; delete $part->{unsafeMntpoint};

	#- try to find other mount points via fstab
	fs::merge_info_from_fstab($fstab, $handle->{dir}, $uniq, 'loose') if $mnt eq '/';
    }
    $_->{mntpoint} and log::l("suggest_mount_points: $_->{device} -> $_->{mntpoint}") foreach @$fstab;
}

sub suggest_mount_points_always {
    my ($fstab) = @_;

    my @win = grep { isFat_or_NTFS($_) && maybeFormatted($_) && !$_->{is_removable} } @$fstab;
    log::l("win parts: ", join ",", map { $_->{device} } @win) if @win;
    if (@win == 1) {
	#- Suggest /boot/efi on ia64.
	$win[0]{mntpoint} = arch() =~ /ia64/ ? "/boot/efi" : "/mnt/windows";
    } else {
	my %w; foreach (@win) {
	    my $v = $w{$_->{device_windobe}}++;
	    $_->{mntpoint} = $_->{unsafeMntpoint} = "/mnt/win_" . lc($_->{device_windobe}) . ($v ? $v+1 : ''); #- lc cuz of StartOffice(!) cf dadou
	}
    }

    my @sunos = grep { $_->{pt_type} == 2 } @$fstab; #- take only into account root partitions.
    if (@sunos) {
	my $v = '';
	map { $_->{mntpoint} = $_->{unsafeMntpoint} = "/mnt/sunos" . ($v && ++$v) } @sunos;
    }
    #- a good job is to mount SunOS root partition, and to use mount point described here in /etc/vfstab.
}

sub validate_mount_points {
    my ($fstab) = @_;

    #- TODO: set the mntpoints

    my %m; foreach (@$fstab) {
	my $m = $_->{mntpoint};

	$m && $m =~ m!^/! or next; #- there may be a lot of swaps or "none"

	$m{$m} and die N("Duplicate mount point %s", $m);
	$m{$m} = 1;

	#- in case the type does not correspond, force it to ext3
	fs::type::set_fs_type($_, 'ext3') if !isTrueFS($_) && !isOtherAvailableFS($_);
    }
    1;
}

sub ask_mount_points {
    my ($in, $fstab, $all_hds) = @_;

    my @fstab = grep { isTrueFS($_) } @$fstab;
    @fstab = grep { isSwap($_) } @$fstab if @fstab == 0;
    @fstab = @$fstab if @fstab == 0;
    die N("No partition available") if @fstab == 0;

    {
	my $_w = $in->wait_message('', N("Scanning partitions to find mount points"));
	suggest_mount_points($fstab, $::prefix, 'uniq');
	log::l("default mntpoint $_->{mntpoint} $_->{device}") foreach @fstab;
    }
    if (@fstab == 1) {
	$fstab[0]{mntpoint} = '/';
    } else {
	$in->ask_from_({ messages => N("Choose the mount points"),
			title => N("Partitioning"),
			icon => 'banner-part',
			interactive_help_id => 'ask_mntpoint_s',
			callbacks => {
			    complete => sub {
				require diskdrake::interactive;
				eval { 1, find_index {
				    !diskdrake::interactive::check_mntpoint($in, $_->{mntpoint}, $_, $all_hds);
				} @fstab };
			    },
			},
		      },
		      [ map { 
			  { 
			      label => partition_table::description($_), 
			      val => \$_->{mntpoint},
			      not_edit => 0,
			      list => [ '', fsedit::suggestions_mntpoint(fs::get::empty_all_hds()) ],
			  };
		        } @fstab ]) or return;
    }
    validate_mount_points($fstab);
}

1;
