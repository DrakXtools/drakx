package fs; # $Id$

use diagnostics;
use strict;

use common qw(:common :file :system :functional);
use log;
use devices;
use partition_table qw(:types);
use run_program;
use swap;
use detect_devices;
use commands;
use modules;
use fsedit;
use loopback;

1;

sub add_options(\$@) {
    my ($option, @options) = @_;
    my %l; @l{split(',', $$option), @options} = (); delete $l{defaults};
    $$option = join(',', keys %l) || "defaults";
}

sub read_fstab($) {
    my ($file) = @_;

    local *F;
    open F, $file or return;

    map {
	my ($dev, @l) = split;
	$dev =~ s,/(tmp|dev)/,,;
	{ device => $dev, mntpoint => $l[0], type => $l[1], options => $l[2] }
    } <F>;
}

sub up_mount_point {
    my ($mntpoint, $fstab) = @_;
    while (1) {
	$mntpoint = dirname($mntpoint);
	$mntpoint ne "." or return;
	$_->{mntpoint} eq $mntpoint and return $_ foreach @$fstab;
    }
}

sub check_mounted($) {
    my ($fstab) = @_;

    local (*F, *G, *H);
    open F, "/etc/mtab";
    open G, "/proc/mounts";
    open H, "/proc/swaps";
    foreach (<F>, <G>, <H>) {
	foreach my $p (@$fstab) {
	    /$p->{device}\s+([^\s]*)\s+/ and $p->{mntpoint} = $1, $p->{isMounted} = $p->{isFormatted} = 1;
	}
    }
}

sub get_mntpoints_from_fstab {
    my ($fstab, $prefix, $uniq) = @_;

    log::l("reading fstab");
    foreach (read_fstab("$prefix/etc/fstab")) {
	next if $uniq && fsedit::mntpoint2part($_->{mntpoint}, $fstab);

	foreach my $p (@$fstab) {
	    $p->{device} eq $_->{device} or next;
	    $_->{type} ne 'auto' && $_->{type} ne type2fs($p->{type}) and
		log::l("err, fstab and partition table do not agree for $_->{device} type: " . (type2fs($p->{type}) || type2name($p->{type})) . " vs $_->{type}"), next;
	    delete $p->{unsafeMntpoint} || !$p->{mntpoint} or next;
	    $p->{mntpoint} = $_->{mntpoint};
	    $p->{options} = $_->{options};
	}
    }
}

#- mke2fs -b (1024|2048|4096) -c -i(1024 > 262144) -N (1 > 100000000) -m (0-100%) -L volume-label
#- tune2fs
sub format_ext2($@) {
    my ($dev, @options) = @_;

    $dev =~ m,(rd|ida)/, and push @options, qw(-b 4096 -R stride=16); #- For RAID only.
    push @options, qw(-b 1024 -O none) if arch() =~ /alpha/;

    run_program::run("mke2fs", @options, devices::make($dev)) or die _("%s formatting of %s failed", "ext2", $dev);
}

sub format_reiserfs($@) {
    my ($dev, @options) = @_;

    run_program::run("mkreiserfs", "-f", @options, devices::make($dev)) or die _("%s formatting of %s failed", "reiserfs", $dev);
}

sub format_dos($@) {
    my ($dev, @options) = @_;

    run_program::run("mkdosfs", @options, devices::make($dev)) or die _("%s formatting of %s failed", "dos", $dev);
}

sub format_hfs($@) {
    my ($dev, @options) = @_;

    run_program::run("hformat", @options, devices::make($dev)) or die _("%s formatting of %s failed", "HFS", $dev);
}

sub real_format_part {
    my ($part) = @_;

    $part->{isFormatted} and return;

    my @options = $part->{toFormatCheck} ? "-c" : ();
    log::l("formatting device $part->{device} (type ", type2name($part->{type}), ")");

    if (isExt2($part)) {
	push @options, "-F" if isLoopback($part);
	format_ext2($part->{device}, @options);
    } elsif (isReiserfs($part)) {
        format_reiserfs($part->{device}, @options);
    } elsif (isDos($part)) {
        format_dos($part->{device}, @options);
    } elsif (isWin($part)) {
        format_dos($part->{device}, @options, '-F', 32);
    } elsif (isHFS($part)) {
        format_hfs($part->{device}, @options, '-l', "Untitled");
    } elsif (isSwap($part)) {
	my $check_blocks = grep { /^-c$/ } @options;
        swap::make($part->{device}, $check_blocks);
    } else {
	die _("I don't know how to format %s in type %s", $_->{device}, type2name($_->{type}));
    }
    $part->{isFormatted} = 1;
}
sub format_part {
    my ($raid, $part, $prefix) = @_;
    if (isRAID($part)) {
	require raid;
	raid::format_part($raid, $part);
    } elsif (isLoopback($part)) {
	loopback::format_part($part, $prefix);
    } else {
	real_format_part($part);
    }
}

sub formatMount_part {
    my ($part, $raid, $fstab, $prefix, $callback) = @_;

    if (isLoopback($part)) {
	formatMount_part($part->{device}, $raid, $fstab, $prefix, $callback);
    }
    if (my $p = up_mount_point($part->{mntpoint}, $fstab)) {
	formatMount_part($p, $raid, $fstab, $prefix, $callback) unless loopback::carryRootLoopback($part);
    }

    if ($part->{toFormat}) {
	$callback->($part) if $callback;
	format_part($raid, $part, $prefix);
    }
    mount_part($part, $prefix);
}

sub formatMount_all {
    my ($raid, $fstab, $prefix, $callback) = @_;
    formatMount_part($_, $raid, $fstab, $prefix, $callback) 
      foreach sort { isLoopback($a) ? 1 : isSwap($a) ? -1 : 0 } grep { $_->{mntpoint} } @$fstab;

    #- ensure the link is there
    loopback::carryRootCreateSymlink($_, $prefix) foreach @$fstab;

    #- for fun :)
    #- that way, when install exits via ctrl-c, it gives hand to partition
    eval {
	local $SIG{__DIE__} = 'ignore';
	my ($type, $major, $minor) = devices::entry(fsedit::get_root($fstab)->{device});
	output "/proc/sys/kernel/real-root-dev", makedev($major, $minor);
    };
}

sub mount($$$;$) {
    my ($dev, $where, $fs, $rdonly) = @_;
    log::l("mounting $dev on $where as type $fs");

    -d $where or commands::mkdir_('-p', $where);

    if ($fs eq 'nfs') {
	log::l("calling nfs::mount($dev, $where)");
#	nfs::mount($dev, $where) or die _("nfs mount failed");
    } elsif ($fs eq 'smb') {
	die "no smb yet...";
    } else {
	$dev = devices::make($dev) if $fs ne 'proc' && $fs ne 'usbdevfs';

	my $flag = c::MS_MGC_VAL();
	$flag |= c::MS_RDONLY() if $rdonly;
	my $mount_opt = "";

	if ($fs eq 'vfat') {
	    $mount_opt = 'check=relaxed';
	    eval { modules::load('vfat') }; #- try using vfat
	    eval { modules::load('msdos') } if $@; #- otherwise msdos...
	} elsif ($fs eq 'ufs') {
	    eval { modules::load('ufs') };
	} elsif ($fs eq 'reiserfs') {
	    #- could be better if we knew if there is a /boot or not
	    #- without knowing it, / is forced to be mounted with notail
	    $mount_opt = 'notail' if $where =~ m|/(boot)?$|;
	    eval { modules::load('reiserfs') };
	} elsif ($fs eq 'romfs') {
	    eval { modules::load('romfs') };
	}

	$where =~ s|/$||;
	log::l("calling mount($dev, $where, $fs, $flag, $mount_opt)");
	syscall_('mount', $dev, $where, $fs, $flag, $mount_opt) or die _("mount failed: ") . "$!";
    }
    local *F;
    open F, ">>/etc/mtab" or return; #- fail silently, must be read-only /etc
    print F "$dev $where $fs defaults 0 0\n";
}

#- takes the mount point to umount (can also be the device)
sub umount($) {
    my ($mntpoint) = @_;
    $mntpoint =~ s|/$||;
    log::l("calling umount($mntpoint)");
    syscall_('umount', $mntpoint) or die _("error unmounting %s: %s", $mntpoint, "$!");

    substInFile { $_ = '' if /(^|\s)$mntpoint\s/ } '/etc/mtab'; #- don't care about error, if we can't read, we won't manage to write... (and mess mtab)
}

sub mount_part($;$$) {
    my ($part, $prefix, $rdonly) = @_;

    #- root carrier's link can't be mounted
    loopback::carryRootCreateSymlink($part, $prefix);

    return if $part->{isMounted};

    unless ($::testing) {
	if (isSwap($part)) {
	    swap::swapon(isLoopback($part) ? $prefix . loopback::file($part) : $part->{device});
	} else {
	    $part->{mntpoint} or die "missing mount point";

	    my $dev = $part->{device};
	    my $mntpoint = ($prefix || '') . $part->{mntpoint};
	    if (isLoopback($part)) {
		eval { modules::load('loop') };
		$dev = $part->{real_device} = devices::set_loop($prefix . loopback::file($part)) || die;
	    } elsif (loopback::carryRootLoopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    mount(devices::make($dev), $mntpoint, type2fs($part->{type}), $rdonly);
	    rmdir "$mntpoint/lost+found";
	}
    }
    $part->{isMounted} = $part->{isFormatted} = 1; #- assume that if mount works, partition is formatted
}

sub umount_part($;$) {
    my ($part, $prefix) = @_;

    $part->{isMounted} or return;

    unless ($::testing) {
	if (isSwap($part)) {
	    swap::swapoff($part->{device});
	} elsif (loopback::carryRootLoopback($part)) {
	    umount("/initrd/loopfs");
	} else {
	    umount(($prefix || '') . $part->{mntpoint} || devices::make($part->{device}));
	    c::del_loop(delete $part->{real_device}) if isLoopback($part);
	}
    }
    $part->{isMounted} = 0;
}

sub mount_all($;$$) {
    my ($fstab, $prefix) = @_;

    #- TODO fsck, create check_mount_all ?
    log::l("mounting all filesystems");

    #- order mount by alphabetical ordre, that way / < /home < /home/httpd...
    foreach (sort { $a->{mntpoint} cmp $b->{mntpoint} } grep { isSwap($_) || $_->{mntpoint} && isTrueFS($_) } @$fstab) {
	mount_part($_, $prefix);
    }
}

sub umount_all($;$) {
    my ($fstab, $prefix) = @_;

    log::l("unmounting all filesystems");

    foreach (sort { $b->{mntpoint} cmp $a->{mntpoint} } @$fstab) {
	$_->{mntpoint} and umount_part($_, $prefix);
    }
}

sub df {
    my ($part, $prefix) = @_;
    my $dir = "/tmp/tmp_fs_df";

    return $part->{free} if exists $part->{free};

    if ($part->{isMounted}) {
	$dir = ($prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	return; #- won't even try!
    } else {
	mkdir $dir;
	eval { mount($part->{device}, $dir, type2fs($part->{type}), 'readonly') };
	if ($@) {
	    $part->{notFormatted} = 1;
	    $part->{isFormatted} = 0;
	    unlink $dir;
	    return;
	}
    }
    my (undef, $free) = common::df($dir);

    if (!$part->{isMounted}) {
	umount($dir);
	unlink($dir)
    }

    $part->{free} = 2 * $free if defined $free;
    $part->{free};
}

#- do some stuff before calling write_fstab
sub write($$$$) {
    my ($prefix, $fstab, $manualFstab, $useSupermount) = @_;
    $fstab = [ @{$fstab||[]}, @{$manualFstab||[]} ];

    unless ($::live) {
	log::l("resetting /etc/mtab");
	local *F;
	open F, "> $prefix/etc/mtab" or die "error resetting $prefix/etc/mtab";
    }

    my ($floppy) = detect_devices::floppies();

    my @to_add = (
       $useSupermount ?
       [ split ' ', "/mnt/floppy /mnt/floppy supermount fs=vfat,dev=/dev/$floppy 0 0" ] :
       [ split ' ', "/dev/$floppy /mnt/floppy auto sync,user,noauto,nosuid,nodev 0 0" ],
       [ split ' ', 'none /proc proc defaults 0 0' ],
       [ split ' ', 'none /dev/pts devpts mode=0620 0 0' ],
       (map_index {
	   my $i = $::i ? $::i + 1 : '';
	   mkdir "$prefix/mnt/cdrom$i", 0755;#- or log::l("failed to mkdir $prefix/mnt/cdrom$i: $!");
	   symlinkf $_->{device}, "$prefix/dev/cdrom$i" or log::l("failed to symlink $prefix/dev/cdrom$i: $!");
	   chown 0, 22, "$prefix/dev/$_->{device}";
	   $useSupermount ?
	     [ "/mnt/cdrom$i", "/mnt/cdrom$i", "supermount", "fs=iso9660,dev=/dev/cdrom$i", 0, 0 ] :
	     [ "/dev/cdrom$i", "/mnt/cdrom$i", "auto", "user,noauto,nosuid,exec,nodev,ro", 0, 0 ];
       } detect_devices::cdroms()),
       (map_index { #- for zip drives, the right partition is the 4th by default.
	   my $i = $::i ? $::i + 1 : '';
	   mkdir "$prefix/mnt/zip$i", 0755 or log::l("failed to mkdir $prefix/mnt/zip$i: $!");
	   symlinkf "$_->{device}4", "$prefix/dev/zip$i" or log::l("failed to symlink $prefix/dev/zip$i: $!");
	   $useSupermount ?
	     [ "/mnt/zip$i", "/mnt/zip$i", "supermount", "fs=vfat,dev=/dev/zip$i", 0, 0 ] :
	     [ "/dev/zip$i", "/mnt/zip$i", "auto", "user,noauto,nosuid,exec,nodev", 0, 0 ];
       } detect_devices::zips()));
    write_fstab($fstab, $prefix, @to_add);
}

sub write_fstab($;$$) {
    my ($fstab, $prefix, @to_add) = @_;
    $prefix ||= '';

    #- get the list of devices and mntpoint to remove existing entries
    #- and @to_add take precedence over $fstab to handle removable device
    #- if they are mounted OR NOT during install.
    my @new = grep { $_ ne 'none' } map { @$_[0,1] } @to_add;
    my %new; @new{@new} = undef;

    unshift @to_add,
      grep { 
	  my $b = !exists $new{$_->[0]} && !exists $new{$_->[1]};
	  #- keep in mind the new line for fstab.
	  @new{@$_[0,1]} = undef;
	  $b
      } map {
	  my ($dir, $options, $freq, $passno) = qw(/dev/ defaults 0 0);
	  $options = $_->{options} || $options;

	  isTrueFS($_) and ($freq, $passno) = (1, ($_->{mntpoint} eq '/') ? 1 : 2);
	  isNfs($_) and $dir = '', $options = $_->{options} || 'ro,nosuid,rsize=8192,wsize=8192';
	  isFat($_) and $options = $_->{options} || "user,exec,umask=0";

	  isReiserfs($_) && $_ == fsedit::get_root($fstab, 'boot') and add_options($options, "notail");

	  my $dev = isLoopback($_) ?
	    ($_->{mntpoint} eq '/' ? "/initrd/loopfs$_->{loopback_file}" : loopback::file($_)) :
	    ($_->{device} =~ /^\// ? $_->{device} : "$dir$_->{device}");
	      
	  local $_->{mntpoint} = do { 
	      $passno = 0;
	      "/initrd/loopfs";
	  } if loopback::carryRootLoopback($_);

	  add_options($options, "loop") if isLoopback($_) && !isSwap($_); #- no need for loop option for swap files

	  eval { devices::make("$prefix/$dev") } if $dir && !isLoopback($_);
	  mkdir "$prefix/$_->{mntpoint}", 0755 if $_->{mntpoint} && !isSwap($_);

	  [ $dev, $_->{mntpoint}, type2fs($_->{type}), $options, $freq, $passno ];

      } grep { $_->{mntpoint} && type2fs($_->{type}) } @$fstab;

    push @to_add,
      grep { !exists $new{$_->[0]} && !exists $new{$_->[1]} }
      map { [ split ] } cat_("$prefix/etc/fstab");

    log::l("writing $prefix/etc/fstab");
    local *F;
    open F, "> $prefix/etc/fstab" or die "error writing $prefix/etc/fstab";
    print F join(" ", @$_), "\n" foreach sort { $a->[1] cmp $b->[1] } @to_add;
}

sub merge_fstabs {
    my ($fstab, $manualFstab) = @_;
    my %l; $l{$_->{device}} = $_ foreach @$manualFstab;
    %$_ = (%$_, %{$l{$_->{device}} || next}) foreach @$fstab;
}

#sub check_mount_all_fstab($;$) {
#    my ($fstab, $prefix) = @_;
#    $prefix ||= '';
#
#    foreach (sort { ($a->{mntpoint} || '') cmp ($b->{mntpoint} || '') } @$fstab) {
#	 #- avoid unwanted mount in fstab.
#	 next if ($_->{device} =~ /none/ || $_->{type} =~ /nfs|smbfs|ncpfs|proc/ || $_->{options} =~ /noauto|ro/);
#
#	 #- TODO fsck
#
#	 eval { mount(devices::make($_->{device}), $prefix . $_->{mntpoint}, $_->{type}, 0); };
#	 if ($@) {
#	     log::l("unable to mount partition $_->{device} on $prefix/$_->{mntpoint}");
#	 }
#    }
#}
