package loopback;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file);
use partition_table qw(:types);
use commands;
use fs;
use log;


sub file {
    my ($part) = @_;
    ($part->{device}{mntpoint} || die "loopback::file but loopback file has no associated mntpoint") . 
      $part->{loopback_file};
}

sub loopbacks {
    map { map { @{$_->{loopback} || []} } partition_table::get_normal_parts($_) } @_;
}

sub carryRootLoopback {
    my ($part) = @_;
    $_->{mntpoint} eq '/' and return 1 foreach @{$part->{loopback} || []};
    0;
}

sub carryRootCreateSymlink {
    my ($part, $prefix) = @_;

    carryRootLoopback($part) or return;

    my $mntpoint = "$prefix$part->{mntpoint}";
    unless (-e $mntpoint) {
	eval { commands::mkdir_("-p", dirname($mntpoint)) };
	#- do non-relative link for install, should be changed to relative link before rebooting
	symlink "/initrd/loopfs", $mntpoint;
    }
    #- indicate kernel to keep initrd
    mkdir "$prefix/initrd", 0755;
}


sub format_part {
    my ($part, $prefix) = @_;
    fs::mount_part($part->{device}, $prefix);
    my $f = create($part, $prefix);
    local $part->{device} = $f;
    fs::real_format_part($part);
}

sub create {
    my ($part, $prefix) = @_;
    my $f = "$prefix$part->{device}{mntpoint}$part->{loopback_file}";
    return $f if -e $f;

    eval { commands::mkdir_("-p", dirname($f)) };

    log::l("creating loopback file $f");
    
    local *F;
    open F, ">$f" or die "failed to create loopback file";
    for (my $nb = $part->{size}; $nb >= 0; $nb -= 8) { #- 8 * 512 = 4096 :)
	print F "\0" x 4096;
    }
    $f;
}

sub getFree {
    my ($part, $prefix) = @_;

    if ($part->{isFormatted} || !$part->{notFormatted}) {
	$part->{freespace} = $part->{size};
    } elsif (!$part->{freespace}) {
	isMountableRW($part) or return;

	my $dir = "/tmp/loopback_tmp";
	if ($part->{isMounted}) {
	    $dir = ($prefix || '') . $part->{mntpoint};
	} else {
	    mkdir $dir, 0700;
	    fs::mount($part->{device}, $dir, type2fs($part->{type}), 'rdonly');
	}
	my $buf = ' ' x 20000;
	syscall_('statfs', $dir, $buf) or return;
	my (undef, $blocksize, $size, undef, $free, undef) = unpack "L2L4", $buf;
	$_ *= $blocksize / 512 foreach $size, $free;

	
	unless ($part->{isMounted}) {
	    fs::umount($dir);
	    unlink $dir;
	}

	$part->{freespace} = $free;
    }
    $part->{freespace} - sum map { $_->{size} } @{$part->{loopback} || []};
}

1;

