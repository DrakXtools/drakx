package fs;

use diagnostics;
use strict;

use common qw(:common :file :system :functional);
use log;
use devices;
use partition_table qw(:types);
use run_program;
use nfs;
use swap;
use detect_devices;
use commands;
use modules;

1;

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

sub check_mounted($) {
    my ($fstab) = @_;

    local (*F, *G, *H);
    open F, "/etc/mtab";
    open G, "/proc/mounts";
    open H, "/proc/swaps";
    foreach (<F>, <G>, <H>) {
	foreach my $p (@$fstab) {
	    /$p->{device}\s+([^\s]*)\s+/ and $p->{realMntpoint} = $1, $p->{isMounted} = $p->{isFormatted} = 1;
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
    my ($dev, @options) = @_;

    $dev =~ m,(rd|ida)/, and push @options, qw(-b 4096 -R stride=16); #- For RAID only.

    run_program::run("mke2fs", devices::make($dev), @options) or die _("%s formatting of %s failed", "ext2", $dev);
}

sub format_dos($;$@) {
    my ($dev, @options) = @_;

    run_program::run("mkdosfs", devices::make($dev), @options) or die _("%s formatting of %s failed", "dos", $dev);
}

sub format_part($;$@) {
    my ($part, @options) = @_;

    $part->{isFormatted} and return;

    log::l("formatting device $part->{device} (type ", type2name($part->{type}), ")");

    if (isExt2($part)) {
	format_ext2($part->{device}, @options);
    } elsif (isDos($part)) {
        format_dos($part->{device}, @options);
    } elsif (isWin($part)) {
        format_dos($part->{device}, @options, '-F', 32);
    } elsif (isSwap($part)) {
	my $check_blocks = grep { /^-c$/ } @options;
        swap::make($part->{device}, $check_blocks);
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
	my $mount_opt = "";

	if ($fs eq 'vfat') {
	    $mount_opt = "check=relaxed";
	    eval { modules::load('vfat') }; #- try using vfat
	    eval { modules::load('msdos') } if $@; #- otherwise msdos...
	}

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
    log::l("calling umount($mntpoint)");
    syscall_('umount', $mntpoint) or die _("error unmounting %s: %s", $mntpoint, "$!");

    my @mtab = cat_('/etc/mtab'); #- don't care about error, if we can't read, we won't manage to write... (and mess mtab)
    local *F;
    open F, ">/etc/mtab" or return;
    foreach (@mtab) { print F $_ unless /(^|\s)$mntpoint\s/; }
}

sub mount_part($;$$) {
    my ($part, $prefix, $rdonly) = @_;

    $part->{isMounted} and return;

    if (isSwap($part)) {
	swap::swapon($part->{device});
    } else {
	$part->{mntpoint} or die "missing mount point";
	mount(devices::make($part->{device}), ($prefix || '') . $part->{mntpoint}, type2fs($part->{type}), $rdonly);
    }
    $part->{isMounted} = $part->{isFormatted} = 1; #- assume that if mount works, partition is formatted
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

    #- order mount by alphabetical ordre, that way / < /home < /home/httpd...
    foreach (sort { ($a->{mntpoint} || '') cmp ($b->{mntpoint} || '') } @$fstab) {
	mount_part($_, $prefix) if $_->{mntpoint};
    }
}

sub umount_all($;$) {
    my ($fstab, $prefix) = @_;

    log::l("unmounting all filesystems");

    foreach (sort { $b->{mntpoint} cmp $a->{mntpoint} } @$fstab) {
	$_->{mntpoint} and umount_part($_, $prefix);
    }
}

#- do some stuff before calling write_fstab
sub write($$) {
    my ($prefix, $fstab) = @_;

    log::l("resetting /etc/mtab");
    local *F;
    open F, "> $prefix/etc/mtab" or die "error resetting $prefix/etc/mtab";

    my @to_add = (
       [ split ' ', '/dev/fd0 /mnt/floppy auto sync,user,noauto,nosuid,nodev,unhide 0 0' ],
       [ split ' ', 'none /proc proc defaults 0 0' ],
       [ split ' ', 'none /dev/pts devpts mode=0620 0 0' ],
       (map_index {
	   my $i = $::i ? $::i + 1 : '';
	   mkdir "$prefix/mnt/cdrom$i", 0755 or log::l("failed to mkdir $prefix/mnt/cdrom$i: $!");
	   symlinkf $_->{device}, "$prefix/dev/cdrom$i" or log::l("failed to symlink $prefix/dev/cdrom$i: $!");
	   [ "/dev/cdrom$i", "/mnt/cdrom$i", "auto", "user,noauto,nosuid,exec,nodev,ro", 0, 0 ];
       } detect_devices::cdroms()),
       (map_index { #- for zip drives, the right partition is the 4th.
	   my $i = $::i ? $::i + 1 : '';
	   mkdir "$prefix/mnt/zip$i", 0755 or log::l("failed to mkdir $prefix/mnt/zip$i: $!");
	   symlinkf "$_->{device}4", "$prefix/dev/zip$i" or log::l("failed to symlink $prefix/dev/zip$i: $!");
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
      map {
	  my ($dir, $options, $freq, $passno) = qw(/dev/ defaults 0 0);
	  $options ||= $_->{options};

	  isExt2($_) and ($freq, $passno) = (1, ($_->{mntpoint} eq '/') ? 1 : 2);
	  isNfs($_) and ($dir, $options) = ('', 'ro');

	  #- keep in mind the new line for fstab.
	  @new{($_->{mntpoint}, $_->{"$dir$_->{device}"})} = undef;

	  eval { devices::make("$prefix/$dir$_->{device}") } if $_->{device} && $dir;
	  mkdir "$prefix/$_->{mntpoint}", 0755 if $_->{mntpoint};

	  [ "$dir$_->{device}", $_->{mntpoint}, type2fs($_->{type}), $options, $freq, $passno ];

      } grep { $_->{mntpoint} && type2fs($_->{type}) &&
		 ! exists $new{$_->{mntpoint}} && ! exists $new{"/dev/$_->{device}"} } @$fstab;

    my @current = cat_("$prefix/etc/fstab");

    log::l("writing $prefix/etc/fstab");
    local *F;
    open F, "> $prefix/etc/fstab" or die "error writing $prefix/etc/fstab";
    foreach (@current) {
	my ($a, $b) = split;
	#- if we find one line of fstab containing either the same device or mntpoint, do not write it
	exists $new{$a} || exists $new{$b} and next;
	print F $_;
    }
    print F join(" ", @$_), "\n" foreach @to_add;
}

sub check_mount_all_fstab($;$) {
    my ($fstab, $prefix) = @_;
    $prefix ||= '';

    foreach (sort { ($a->{mntpoint} || '') cmp ($b->{mntpoint} || '') } @$fstab) {
	#- avoid unwanted mount in fstab.
	next if ($_->{device} =~ /none/ || $_->{type} =~ /nfs|smbfs|ncpfs|proc/ || $_->{options} =~ /noauto|ro/);

	#- TODO fsck

	eval { mount(devices::make($_->{device}), $prefix . $_->{mntpoint}, $_->{type}, 0); };
	if ($@) {
	    log::l("unable to mount partition $_->{device} on $prefix/$_->{mntpoint}");
	}
    }
}
