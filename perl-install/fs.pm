package fs; # $Id$

use diagnostics;
use strict;

use MDK::Common::System;
use common;
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


sub read_fstab {
    my ($file) = @_;

    map {
	my ($dev, $mntpoint, $type, $options) = split;

	$options = 'defaults' if $options eq 'rw'; # clean-up for mtab read

	$type = fs2type($type);
	if ($type eq 'supermount') {
	    # normalize this bloody supermount
	    $options = join(",", grep {
		if (/fs=(.*)/) {
		    $type = $1;
		    0;
		} elsif (/dev=(.*)/) {
		    $dev = $1;
		    0;
		} else {
		    1;
		}
	    } split(',', $options));
	}

	if ($dev =~ m,/(tmp|dev)/,) {
	    $dev = expand_symlinks($dev);
	    $dev =~ s,/(tmp|dev)/,,;
	}

	{ device => $dev, mntpoint => $mntpoint, type => $type, options => $options };
    } cat_($file);
}

sub merge_fstabs {
    my ($fstab, @l) = @_;

    foreach my $p (@$fstab) {
	my ($p2) = grep { $_->{device} eq $p->{device} } @l or next;
	@l       = grep { $_->{device} ne $p->{device} } @l;

	$p->{type} ne $p2->{type} && $p->{type} ne 'auto' && $p2->{type} ne 'auto' and
	  log::l("err, fstab and partition table do not agree for $p->{device} type: " . (type2fs($p) || type2name($p->{type})) . " vs ", (type2fs($p2) || type2name($p2->{type}))), next;
	
	$p->{mntpoint} = $p2->{mntpoint} if delete $p->{unsafeMntpoint};

	$p->{type} = $p2->{type} if $p->{type} eq 'defaults';
	$p->{options} = $p2->{options};
	add2hash($p, $p2);
    }
    @l;
}

sub add2all_hds {
    my ($all_hds, @l) = @_;

    @l = merge_fstabs([ fsedit::get_really_all_fstab($all_hds) ], @l);

    foreach (@l) {
	my $s = 
	    isNfs($_) ? 'nfs' :
	    isThisFs('smbfs', $_) ? 'smb' :
	    'special';
	push @{$all_hds->{$s}}, $_;
    }
}

sub merge_info_from_mtab {
    my ($fstab) = @_;

    my @l1 = map {; { device => $_->{device}, type => fs2type('swap') } } read_fstab('/proc/swaps');
    my @l2 = map { read_fstab($_) } '/etc/mtab', '/proc/mounts';

    foreach (@l1, @l2) {
	$_->{isMounted} = $_->{isFormatted} = 1;
	delete $_->{options};
    } 
    merge_fstabs($fstab, @l1, @l2);
}

sub merge_info_from_fstab {
    my ($fstab, $prefix, $uniq) = @_;
    my @l = grep { !($uniq && fsedit::mntpoint2part($_->{mntpoint}, $fstab)) } read_fstab("$prefix/etc/fstab");
    merge_fstabs($fstab, @l);
}

sub write_fstab {
    my ($all_hds, $prefix) = @_;
    $prefix ||= '';

    my @l1 = (fsedit::get_really_all_fstab($all_hds), @{$all_hds->{special}});
    my @l2 = read_fstab("$prefix/etc/fstab");

    my %new;
    my @l = map { 
	my $device = 
	  $_->{device} eq 'none' || member($_->{type}, qw(nfs smb)) ? 
	      $_->{device} : 
	  isLoopback($_) ? 
	      ($_->{mntpoint} eq '/' ? "/initrd/loopfs$_->{loopback_file}" : $_->{device}) :
	  do {
	      my $dir = $_->{device} =~ m|^/| ? '' : '/dev/';
	      devices::make("$prefix$dir$_->{device}"); "$dir$_->{device}";
	  };

	mkdir("$prefix/$_->{mntpoint}", 0755);
	my $mntpoint = loopback::carryRootLoopback($_) ? '/initrd/loopfs' : $_->{mntpoint};
	
	my ($freq, $passno) =
	  isTrueFS($_) ? 
	    (1, $_->{mntpoint} eq '/' ? 1 : loopback::carryRootLoopback($_) ? 0 : 2) : 
	    (0, 0);

	if (($device eq 'none' || !$new{$device}) && !$new{$mntpoint}) {
	    #- keep in mind the new line for fstab.
	    $new{$device} = 1;
	    $new{$mntpoint} = 1;

	    my $options = $_->{options};
	    my $type = type2fs($_);

	    # handle bloody supermount special case
	    if ($options =~ /supermount/) {
		$options = join(",", "dev=$device", "fs=$type", grep { $_ ne 'supermount' } split(':', $options));
		($device, $type) = ($mntpoint, 'supermount');
	    }

	    [ $device, $mntpoint, $type, $options || 'defaults', $freq, $passno ];
	} else {
	    ()
	}
    } grep { $_->{device} && $_->{mntpoint} && $_->{type} } (@l1, @l2);

    log::l("writing $prefix/etc/fstab");
    output("$prefix/etc/fstab", map { join(' ', @$_) . "\n" } sort { $a->[1] cmp $b->[1] } @l);
}

sub auto_fs() {
    grep { chop; $_ && !/nodev/ } cat_("/etc/filesystems");
}

sub mount_options {
    my %non_defaults = (
			sync => 'async', noatime => 'atime', noauto => 'auto', ro => 'rw', 
			user => 'nouser', nodev => 'dev', noexec => 'exec', nosuid => 'suid',
		       );
    my @user_implies = qw(noexec nodev nosuid);
    \%non_defaults, \@user_implies;
}

# simple function
# use mount_options_unpack + mount_options_pack for advanced stuff
sub add_options(\$@) {
    my ($option, @options) = @_;
    my %l; @l{split(',', $$option), @options} = (); delete $l{defaults};
    $$option = join(',', keys %l) || "defaults";
}

sub mount_options_unpack {
    my ($part) = @_;
    my $packed_options = $part->{options};

    my ($non_defaults, $user_implies) = mount_options();

    my @auto_fs = auto_fs();
    my %per_fs = (
		  iso9660 => [ qw(unhide) ],
		  vfat => [ qw(umask=0) ],
		  nfs => [ qw(rsize=8192 wsize=8192) ],
		  smbfs => [ qw(username= password=) ],
		 );
    while (my ($fs, $l) = each %per_fs) {
	isThisFs($fs, $part) || $part->{type} eq 'auto' && member($fs, @auto_fs) or next;
	$non_defaults->{$_} = 1 foreach @$l;
    }

    $non_defaults->{supermount} = 1 if member(type2fs($part), 'auto', @auto_fs);

    my $defaults = { reverse %$non_defaults };
    my %options = map { $_ => '' } keys %$non_defaults;
    my @unknown;
    foreach (split(",", $packed_options)) {
	if ($_ eq 'user') {
	    $options{$_} = 1 foreach ('user', @$user_implies);
	} elsif (exists $non_defaults->{$_}) {
	    $options{$_} = 1;
	} elsif ($defaults->{$_}) {
	    $options{$defaults->{$_}} = 0;
	} elsif (/(.*?=)(.*)/) {
	    $options{$1} = $2;
	} else {
	    push @unknown, $_;
	}
    }
    # merge those, for cleaner help
    $options{'rsize=8192,wsize=8192'} = delete $options{'rsize=8192'} && delete $options{'wsize=8192'}
      if exists $options{'rsize=8192'};

    my $unknown = join(",", @unknown);
    \%options, $unknown;
}

sub mount_options_pack {
    my ($part, $options, $unknown) = @_;

    my ($non_defaults, $user_implies) = mount_options();
    my @l;

    if (delete $options->{user}) {
	push @l, 'user';
	foreach (@$user_implies) {
	    if (!delete $options->{$_}) {
		# overriding
		$options->{$non_defaults->{$_}} = 1;
	    }
	}
    }
    push @l, map_each { if_($::b, $::a =~ /=$/ ? "$::a$::b" : $::a) } %$options;
    push @l, $unknown;

    $part->{options} = join(",", grep { $_ } @l);
}

sub mount_options_help {
    my %help = map { $_ => '' } @_;
    my %short = map { if_(/(.*?)=/, "$1=" => $_) } keys %help;

    foreach (split(':', $ENV{LANGUAGE}), '') {
	my $manpage = "/usr/share/man/$_/man8/mount.8.bz2";
	-e $manpage or next;

	my ($tp, $option);
	foreach (`bzip2 -dc $manpage`) {
	    my $prev_tp = $tp;
	    $tp = /^\.(TP|RE)/;
	    my ($s) = /^\.B (.*)/;
	    if ($prev_tp && $s eq '\-o' .. /X^/) {
		if (my $v = $prev_tp && $s =~ /^[a-z]/i .. $tp) {
		    if ($v == 1) {
			$s = $short{$s} || $s;
			$option = exists $help{$s} && !$help{$s} ? $s : '';
		    } elsif ($v !~ 'E0') {
			s/\\//g;
			s/\s*"(.*?)"\s*/$1/g if s/^\.BR\s+//;
			s/^\.B\s+//;
			$help{$option} .= $_ if $option;
		    }
		}        
	    }
	}
    }
    %help;
}

sub set_default_options {
    my ($all_hds, $useSupermount, $iocharset, $codepage) = @_;

    my @removables = @{$all_hds->{raw_hds}};

    foreach my $part (fsedit::get_really_all_fstab($all_hds)) {
	my ($options, $unknown) = mount_options_unpack($part);

	if (member($part, @removables)) {
	    $options->{supermount} = $useSupermount;
	    $part->{type} = 'auto'; # if supermount, code below will handle choosing the right type
	}

	my $is_auto = isThisFs('auto', $part);

	if ($options->{supermount} && $is_auto) {
	    # this can't work, guessing :-(
	    $part->{type} = fs2type($part->{media_type} eq 'cdrom' ? 'iso9660' : 'vfat');
	    $is_auto = 0;
	}

	if ($part->{media_type} eq 'fd') {
	    # slow device so don't loose time, write now!
	    $options->{sync} = 1;
	}

	if (isNfs($part)) {
	    put_in_hash($options, { 
	        ro => 1, nosuid => 1, 'rsize=8192,wsize=8192' => 1, 
		'iocharset=' => $iocharset,
            });
	}
	if (isFat($part) || $is_auto) {
	    put_in_hash($options, {
	        user => 1, 'umask=0' => 1, exec => 1,
	        'iocharset=' => $iocharset, 'codepage=' => $codepage,
            });
	}
	if (isThisFs('ntfs', $part) || $is_auto) {
	    put_in_hash($options, { 'iocharset=' => $iocharset });
	}
	if (isThisFs('iso9660', $part) || $is_auto) {
	    put_in_hash($options, { user => 1, exec => 1, });
	}
	if (isThisFs('reiserfs', $part)) {
	    $options->{notail} = 1;
	}
	if (isLoopback($_) && !isSwap($_)) { #- no need for loop option for swap files
	    $options->{loop} = 1;
	}

	# rationalize: no need for user
	if ($options->{autofs} || $options->{supermount}) {
	    $options->{user} = 0;
	}

	# have noauto when we have user
	$options->{noauto} = $options->{user}; 

	if ($options->{user}) {
	    # ensure security  (user_implies - noexec as noexec is not a security matter)
	    $options->{$_} = 1 foreach 'nodev', 'nosuid';
	}

	mount_options_pack($part, $options, $unknown);
    }
}

sub set_removable_mntpoints {
    my ($all_hds) = @_;

    my %names;
    foreach (@{$all_hds->{raw_hds}}) {
	my $name = $_->{media_type};
	if (member($name, 'hd', 'fd')) {
	    if (detect_devices::isZipDrive($_)) {
		$name = 'zip';
	    } elsif ($name eq 'fd') {
		$name = 'floppy';
	    } else {
		log::l("set_removable_mntpoints: don't know what to with hd $_->{device}");
		next;
	    }
	}
	my $s = ++$names{$name};
	$_->{mntpoint} ||= "/mnt/$name" . ($s == 1 ? '' : $s);
    }
}

sub get_raw_hds {
    my ($prefix, $all_hds) = @_;

    $all_hds->{raw_hds} = 
      [ 
       detect_devices::floppies(), detect_devices::cdroms(), 
       (map { $_->{device} .= '4'; $_ } detect_devices::zips())
      ];
    my @fstab = read_fstab("$prefix/etc/fstab");
    $all_hds->{nfss} = [ grep { isNfs($_) } @fstab ];
    $all_hds->{smbs} = [ grep { isThisFs('smbfs', $_) } @fstab ];
    $all_hds->{special} = [
       { device => 'none', mntpoint => '/proc', type => 'proc' },
       { device => 'none', mntpoint => '/dev/pts', type => 'devpts', options => 'mode=0620' },
    ];
}

################################################################################
# formatting functions
################################################################################
sub format_ext2($@) {
    #- mke2fs -b (1024|2048|4096) -c -i(1024 > 262144) -N (1 > 100000000) -m (0-100%) -L volume-label
    #- tune2fs
    my ($dev, @options) = @_;
    $dev =~ m,(rd|ida|cciss)/, and push @options, qw(-b 4096 -R stride=16); #- For RAID only.
    push @options, qw(-b 1024 -O none) if arch() =~ /alpha/;
    run_program::run("mke2fs", @options, devices::make($dev)) or die _("%s formatting of %s failed", "ext2", $dev);
}
sub format_ext3 {
    my ($dev, @options) = @_;
    format_ext2($dev, "-j", @options);
}
sub format_reiserfs {
    my ($dev, @options) = @_;
    #TODO add -h tea
    run_program::run("mkreiserfs", "-f", "-q", @options, devices::make($dev)) or die _("%s formatting of %s failed", "reiserfs", $dev);
}
sub format_xfs {
    my ($dev, @options) = @_;
    run_program::run("mkfs.xfs", "-f", "-q", @options, devices::make($dev)) or die _("%s formatting of %s failed", "xfs", $dev);
}
sub format_jfs {
    my ($dev, @options) = @_;
    run_program::run("mkfs.jfs", "-f", @options, devices::make($dev)) or die _("%s formatting of %s failed", "jfs", $dev);
}
sub format_dos {
    my ($dev, @options) = @_;
    run_program::run("mkdosfs", @options, devices::make($dev)) or die _("%s formatting of %s failed", "dos", $dev);
}
sub format_hfs {
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
    } elsif (isThisFs("ext3", $part)) {
        format_ext3($part->{device}, @options);
    } elsif (isThisFs("reiserfs", $part)) {
        format_reiserfs($part->{device}, @options, if_(c::kernel_version() =~ /^\Q2.2/, "-v", "1"));
    } elsif (isThisFs("xfs", $part)) {
        format_xfs($part->{device}, @options);
    } elsif (isThisFs("jfs", $part)) {
        format_jfs($part->{device}, @options);
    } elsif (isDos($part)) {
        format_dos($part->{device}, @options);
    } elsif (isWin($part)) {
        format_dos($part->{device}, @options, '-F', 32);
    } elsif (isThisFs('hfs', $part)) {
        format_hfs($part->{device}, @options, '-l', "Untitled");
    } elsif (isAppleBootstrap($part)) {
        format_hfs($part->{device}, @options, '-l', "bootstrap");
    } elsif (isSwap($part)) {
	my $check_blocks = grep { /^-c$/ } @options;
        swap::make($part->{device}, $check_blocks);
    } else {
	die _("I don't know how to format %s in type %s", $_->{device}, type2name($_->{type}));
    }
    $part->{isFormatted} = 1;
}
sub format_part {
    my ($raids, $part, $prefix) = @_;
    if (isRAID($part)) {
	require raid;
	raid::format_part($raids, $part);
    } elsif (isLoopback($part)) {
	loopback::format_part($part, $prefix);
    } else {
	real_format_part($part);
    }
}

################################################################################
# mounting functions
################################################################################
sub formatMount_part {
    my ($part, $raids, $fstab, $prefix, $callback) = @_;

    if (isLoopback($part)) {
	formatMount_part($part->{loopback_device}, $raids, $fstab, $prefix, $callback);
    }
    if (my $p = up_mount_point($part->{mntpoint}, $fstab)) {
	formatMount_part($p, $raids, $fstab, $prefix, $callback) unless loopback::carryRootLoopback($part);
    }

    if ($part->{toFormat}) {
	$callback->($part) if $callback;
	format_part($raids, $part, $prefix);
    }
    mount_part($part, $prefix);
}

sub formatMount_all {
    my ($raids, $fstab, $prefix, $callback) = @_;
    formatMount_part($_, $raids, $fstab, $prefix, $callback) 
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

sub mount {
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
	} elsif ($fs eq 'reiserfs') {
	    #- could be better if we knew if there is a /boot or not
	    #- without knowing it, / is forced to be mounted with notail
	    # if $where =~ m|/(boot)?$|;
	    $mount_opt = 'notail'; #- notail in any case
	} elsif ($fs eq 'ext2') {
	    run_program::run("fsck.ext2", "-a", $dev);
	    $? & 0x0100 and log::l("fsck corrected partition $dev");
	    $? & 0xfeff and die _("fsck failed with exit code %d or signal %d", $? >> 8, $? & 255);
	}
	if (member($fs, qw(hfs romfs ufs reiserfs xfs jfs ext3))) {
	    eval { modules::load($fs) };
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
sub umount {
    my ($mntpoint) = @_;
    $mntpoint =~ s|/$||;
    log::l("calling umount($mntpoint)");
    syscall_('umount', $mntpoint) or die _("error unmounting %s: %s", $mntpoint, "$!");

    substInFile { $_ = '' if /(^|\s)$mntpoint\s/ } '/etc/mtab'; #- don't care about error, if we can't read, we won't manage to write... (and mess mtab)
}

sub mount_part {
    my ($part, $prefix, $rdonly) = @_;

    #- root carrier's link can't be mounted
    loopback::carryRootCreateSymlink($part, $prefix);

    return if $part->{isMounted};

    unless ($::testing) {
	if (isSwap($part)) {
	    swap::swapon($part->{device});
	} else {
	    $part->{mntpoint} or die "missing mount point";

	    my $dev = $part->{device};
	    my $mntpoint = ($prefix || '') . $part->{mntpoint};
	    if (isLoopback($part)) {
		eval { modules::load('loop') };
		$dev = $part->{real_device} = devices::set_loop($part->{device}) || die;
	    } elsif (loopback::carryRootLoopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    mount(devices::make($dev), $mntpoint, type2fs($part), $rdonly);
	    rmdir "$mntpoint/lost+found";
	}
    }
    $part->{isMounted} = $part->{isFormatted} = 1; #- assume that if mount works, partition is formatted
}

sub umount_part {
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

################################################################################
# various functions
################################################################################
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
	eval { mount($part->{device}, $dir, type2fs($part), 'readonly') };
	if ($@) {
	    $part->{notFormatted} = 1;
	    $part->{isFormatted} = 0;
	    unlink $dir;
	    return;
	}
    }
    my (undef, $free) = MDK::Common::System::df($dir);

    if (!$part->{isMounted}) {
	umount($dir);
	unlink($dir)
    }

    $part->{free} = 2 * $free if defined $free;
    $part->{free};
}

sub up_mount_point {
    my ($mntpoint, $fstab) = @_;
    while (1) {
	$mntpoint = dirname($mntpoint);
	$mntpoint ne "." or return;
	$_->{mntpoint} eq $mntpoint and return $_ foreach @$fstab;
    }
}

1;
