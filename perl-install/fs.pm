package fs;

use diagnostics;
use strict;

use common qw(:common :file :system);
use log;
use devices;
use partition_table qw(:types);
use run_program;
use nfs;
use swap;
use detect_devices;
use commands;

1;


sub read_fstab($) {
    my ($file) = @_;

    local *F;
    open F, $file or return;
    
    map {
	my ($dev, $mntpoint, @l) = split ' ';
	$dev =~ s,/(tmp|dev)/,,;
	while (@l > 4) { $mntpoint .= " " . shift @l; }
	{ device => $dev, mntpoint => $mntpoint, type => $l[0], options => $l[1] }
    } <F>;
}

sub check_mounted($) {
    my ($fstab) = @_;

    local (*F, *G, *H);
    open F, "/etc/mtab";
    open G, "/proc/mounts";
    open H, "/proc/swaps";
    foreach (<F>, <G>, <H>) {
	foreach my $p (@$fstab) {
	    /$p->{device}\s/ and $p->{isMounted} = $p->{isFormatted} = 1;
	}
    }
}

sub get_mntpoints_from_fstab($) {
    my ($fstab) = @_;

    foreach (read_fstab('/etc/fstab')) {
	foreach my $p (@$fstab) {
	    $p->{device} eq $_->{device} or next;
	    $p->{mntpoint} ||= $_->{mntpoint};
	    $p->{options} ||= $_->{options};
	    $_->{type} ne 'auto' && $_->{type} ne type2fs($p->{type}) and 
		log::l("err, fstab and partition table do not agree for $_->{device} type: " . (type2fs($p->{type}) || type2name($p->{type})) . " vs $_->{type}");
	}
    }
}

sub format_ext2($;$) {
    my ($dev, $bad_blocks) = @_;
    my @options;

    $dev =~ m,(rd|ida)/, and push @options, qw(-b 4096 -R stride=16); # For RAID only.
    $bad_blocks and push @options, "-c";

    run_program::run("mke2fs", devices::make($dev), @options) or die _("%s formatting of %s failed", "ext2", $dev);
}

sub format_dos($;$@) {
    my ($dev, $bad_blocks, @options) = @_;

    run_program::run("mkdosfs", devices::make($dev), @options, $bad_blocks ? "-c" : ()) or die _("%s formatting of %s failed", "dos", $dev);
}

sub format_part($;$) {
    my ($part, $bad_blocks) = @_;

    $part->{isFormatted} and return;

    log::l("formatting device $part->{device} (type ", type2name($part->{type}), ")");

    if (isExt2($part)) {
	format_ext2($part->{device}, $bad_blocks);
    } elsif (isDos($part)) {
        format_dos($part->{device}, $bad_blocks);
    } elsif (isWin($part)) {
        format_dos($part->{device}, $bad_blocks, '-F', 32);
    } elsif (isSwap($part)) {
        swap::make($part->{device}, $bad_blocks);
    } else {
	die _("don't know how to format %s in type %s", $_->{device}, type2name($_->{type}));
    }
    $part->{isFormatted} = 1;
}

sub mount($$$;$) {
    my ($dev, $where, $fs, $rdonly) = @_; 
    log::l("mounting $dev on $where as type $fs");
  
    -d $where or commands::mkdir_('-p', $where);
    
    if ($fs eq 'nfs') {
	log::l("calling nfs::mount($dev, $where)");
	nfs::mount($dev, $where) or die _("nfs mount failed");
    } elsif ($fs eq 'smb') {
	die "no smb yet...";
    } else {
	$dev = devices::make($dev) if $fs ne 'proc';

	my $flag = 0;#c::MS_MGC_VAL();
	$flag |= c::MS_RDONLY() if $rdonly;
	my $mount_opt = $fs eq 'vfat' ? "check=relaxed" : "";
  
	log::l("calling mount($dev, $where, $fs, $flag, $mount_opt)");
	syscall_('mount', $dev, $where, $fs, $flag, $mount_opt) or die _("mount failed: ") . "$!";
    }
    local *F;
    open F, ">>/etc/mtab" or return; # fail silently, must be read-only /etc
    print F "$dev $where $fs defaults 0 0\n";
}

# takes the mount point to umount (can also be the device)
sub umount($) { 
    my ($mntpoint) = @_;
    syscall_('umount', $mntpoint) or die _("error unmounting %s: %s", $mntpoint, "$!");

    my @mtab = cat_('/etc/mtab'); # don't care about error, if we can't read, we won't manage to write... (and mess mtab)
    local *F;
    open F, ">/etc/mtab" or return;
    foreach (@mtab) { print F $_ unless /(^|\s)$mntpoint\s/; }
}

sub mount_part($;$) {
    my ($part, $prefix) = @_;
    
    $part->{isMounted} and return;
    $part->{mntpoint} or die "missing mount point";
    
    isSwap($part) ?
	swap::swapon($part->{device}) :
	mount(devices::make($part->{device}), ($prefix || '') . $part->{mntpoint}, type2fs($part->{type}), 0);
    $part->{isMounted} = $part->{isFormatted} = 1; # assume that if mount works, partition is formatted
}

sub umount_part($;$) {
    my ($part, $prefix) = @_;

    $part->{isMounted} or return;

    isSwap($part) ?
      swap::swapoff($part->{device}) :
      umount(($prefix || '') . ($part->{mntpoint} || devices::make($part->{device})));
    $part->{isMounted} = 0;
}

sub mount_all($;$) {
    my ($fstab, $prefix) = @_;

    log::l("mounting all filesystems");

    # order mount by alphabetical ordre, that way / < /home < /home/httpd...
    foreach (sort { $a->{mntpoint} cmp $b->{mntpoint} } @$fstab) {
	$_->{mntpoint} and mount_part($_, $prefix);
    }
}

sub umount_all($;$) {
    my ($fstab, $prefix) = @_;

    log::l("unmounting all filesystems");

    foreach (sort { $b->{mntpoint} cmp $a->{mntpoint} } @$fstab) {
	$_->{mntpoint} and umount_part($_, $prefix);
    }
}

# do some stuff before calling write_fstab
sub write($$) {
    my ($prefix, $fstab) = @_;
    my @cd_drives = detect_devices::cdroms();

    log::l("scanning /proc/mounts for iso9660 filesystems");
    unshift @cd_drives, grep { $_->{type} eq 'iso9660' } read_fstab("/proc/mounts");
    log::l("found cdrom drive(s) " . join(', ', map { $_->{device} } @cd_drives));

    # cd-rom rooted installs have the cdrom mounted on /dev/root which 
    # is not what we want to symlink to /dev/cdrom.                    
    my $cddev = first(grep { $_ ne 'root' } map { $_->{device} } @cd_drives);

    log::l("resetting /etc/mtab");
    local *F;
    open F, "> $prefix/etc/mtab" or die "error resetting $prefix/etc/mtab";

    if ($cddev) {
	mkdir "$prefix/mnt/cdrom", 0755 or log::l("failed to mkdir $prefix/mnt/cdrom: $!");
	symlink $cddev, "$prefix/dev/cdrom" or log::l("failed to symlink $prefix/dev/cdrom: $!");
    }
    write_fstab($fstab, $prefix, $cddev);

    devices::make "$prefix/dev/$_->{device}" foreach grep { $_->{device} && !isNfs($_) } @$fstab;
}

sub write_fstab($;$$) {
    my ($fstab, $prefix, $cddev) = @_;
    $prefix ||= '';

    my @to_add = 
      map {
	  my ($dir, $options, $freq, $passno) = qw(/dev/ defaults 0 0);
	  $options ||= $_->{options};

	  isExt2($_) and ($freq, $passno) = (1, ($_->{mntpoint} eq '/') ? 1 : 2);
	  isNfs($_) and ($dir, $options) = ('', 'ro');
	  
	  [ "$dir$_->{device}", $_->{mntpoint}, type2fs($_->{type}), $options, $freq, $passno ];

      } grep { $_->{mntpoint} && type2fs($_->{type}) } @$fstab;

    {
      push @to_add, [ split ' ', '/dev/fd0 /mnt/floppy auto sync,user,noauto,nosuid,nodev,unhide 0 0' ];
      push @to_add, [ split ' ', '/dev/cdrom /mnt/cdrom auto user,noauto,nosuid,exec,nodev,ro 0 0' ] if $cddev;
      push @to_add, [ split ' ', 'none /proc proc defaults 0 0' ];
      push @to_add, [ split ' ', 'none /dev/pts devpts mode=0620 0 0' ];
    }

    # get the list of devices and mntpoint
    my @new = grep { $_ ne 'none' } map { @$_[0,1] } @to_add;
    my %new; @new{@new} = undef;

    my @current = cat_("$prefix/etc/fstab");

    log::l("writing $prefix/etc/fstab");
    local *F;
    open F, "> $prefix/etc/fstab" or die "error writing $prefix/etc/fstab";
    foreach (@current) {
	my ($a, $b) = split;
	# if we find one line of fstab containing either the same device or mntpoint, do not write it
	exists $new{$a} || exists $new{$b} and next;
	print F $_;
    }
    print F join(" ", @$_), "\n" foreach @to_add;
}


