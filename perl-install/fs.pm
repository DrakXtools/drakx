package fs; # $Id$

use diagnostics;
use strict;

use MDK::Common::System;
use MDK::Common::Various;
use common;
use log;
use devices;
use partition_table qw(:types);
use run_program;
use swap;
use detect_devices;
use modules;
use fsedit;
use loopback;


sub read_fstab {
    my ($prefix, $file, $all_options) = @_;

    my %comments;
    my $comment;
    my @l = grep {
	if (/^\s*#/) {
	    $comment .= chomp_($_) . "\n";
	    0;
	} else {
	    $comments{$_} = $comment if $comment;
	    $comment = '';
	    1;
	}
    } cat_("$prefix$file");

    #- attach comments at the end of fstab to the previous line
    $comments{$l[-1]} = $comment if $comment;

    map {
	my ($dev, $mntpoint, $type, $options, $freq, $passno) = split;
	my $comment = $comments{$_};

	$options = 'defaults' if $options eq 'rw'; # clean-up for mtab read

	$type = fs2type($type);
	if ($type eq 'supermount') {
	    # normalize this bloody supermount
	    $options = join(",", 'supermount', grep {
		if (/fs=(.*)/) {
		    $type = $1;
		    0;
		} elsif (/dev=(.*)/) {
		    $dev = $1;
		    0;
		} elsif ($_ eq '--') {
		    0;
		} else {
		    1;
		}
	    } split(',', $options));
	} elsif ($type eq 'smb') {
	    # prefering type "smbfs" over "smb"
	    $type = 'smbfs';
	}
	$mntpoint =~ s/\\040/ /g;
	$dev =~ s/\\040/ /g;

	my $h = { 
		 device => $dev, mntpoint => $mntpoint, type => $type, 
		 options => $options, comment => $comment,
		 if_($all_options, freq => $freq, passno => $passno),
		};

	($h->{major}, $h->{minor}) = unmakedev((stat "$prefix$dev")[6]);

	if ($dev =~ m,/(tmp|dev)/,) {
	    my $symlink = readlink("$prefix$dev");
	    $dev =~ s,/(tmp|dev)/,,;

	    if ($symlink =~ m|^[^/]+$|) {
		$h->{device_alias} = $dev;
		$h->{device} = $symlink;
	    } else {
		$h->{device} = $dev;
	    }
	}

	if ($h->{options} =~ /credentials=/) {
	    require network::smb;
	    #- remove credentials=file with username=foo,password=bar,domain=zoo
	    #- the other way is done in fstab_to_string
	    my ($options, $unknown) = mount_options_unpack($h);
	    my $file = delete $options->{'credentials='};
	    my $credentials = network::smb::read_credentials_raw("$prefix$file");
	    if ($credentials->{username}) {
		$options->{"$_="} = $credentials->{$_} foreach qw(username password domain);
		mount_options_pack($h, $options, $unknown);
	    }
	}

	$h;
    } @l;
}

sub merge_fstabs {
    my ($loose, $fstab, @l) = @_;

    foreach my $p (@$fstab) {
	my ($p2) = grep { fsedit::is_same_hd($_, $p) } @l or next;
	@l       = grep { !fsedit::is_same_hd($_, $p) } @l;

	$p->{mntpoint} = $p2->{mntpoint} if delete $p->{unsafeMntpoint};

	$p->{type} = $p2->{type} if $p2->{type} && !$loose;
	$p->{options} = $p2->{options} if $p2->{options} && !$loose;
	#- important to get isMounted property else DrakX may try to mount already mounted partitions :-(
	add2hash($p, $p2);
	$p->{device_alias} ||= $p2->{device_alias} || $p2->{device} if $p->{device} ne $p2->{device} && $p2->{device} !~ m|/|;

	$p->{type} && $p2->{type} && $p->{type} ne $p2->{type} && type2fs($p) ne type2fs($p2) &&
	  $p->{type} ne 'auto' && $p2->{type} ne 'auto' and
	    log::l("err, fstab and partition table do not agree for $p->{device} type: " .
		   (type2fs($p) || type2name($p->{type})) . " vs ", (type2fs($p2) || type2name($p2->{type})));
    }
    @l;
}

sub add2all_hds {
    my ($all_hds, @l) = @_;

    @l = merge_fstabs('', [ fsedit::get_really_all_fstab($all_hds) ], @l);

    foreach (@l) {
	my $s = 
	    isNfs($_) ? 'nfss' :
	    isThisFs('smbfs', $_) ? 'smbs' :
	    'special';
	push @{$all_hds->{$s}}, $_;
    }
}

sub get_major_minor {
    eval {
	my (undef, $major, $minor) = devices::entry($_->{device});
	($_->{major}, $_->{minor}) = ($major, $minor);
    } foreach @_;
}

sub merge_info_from_mtab {
    my ($fstab) = @_;

    my @l1 = map { my $l = $_; 
		   my %l = (type => fs2type('swap')); 
		   $l{$_} = $l->{$_} foreach qw(device major minor); 
		   \%l;
	       } read_fstab('', '/proc/swaps');
    
    my @l2 = map { read_fstab('', $_) } '/etc/mtab', '/proc/mounts';

    foreach (@l1, @l2) {
	log::l("found mounted partition on $_->{device} with $_->{mntpoint}");
	if ($::isInstall && $_->{mntpoint} eq '/tmp/hdimage') {
	    log::l("found hdimage on $_->{device}");
	    $_->{real_mntpoint} = delete $_->{mntpoint};
	    $_->{mntpoint} = common::usingRamdisk() && "/mnt/hd"; #- remap for hd install.
	}
	$_->{isMounted} = $_->{isFormatted} = 1;
	delete $_->{options};
    } 
    merge_fstabs('loose', $fstab, @l1, @l2);
}

# - when using "$loose", it does not merge in type&options from the fstab
sub merge_info_from_fstab {
    my ($fstab, $prefix, $uniq, $loose) = @_;

    my @l = grep { 
	if ($uniq) {
	    my $part = fsedit::mntpoint2part($_->{mntpoint}, $fstab);
	    !$part || fsedit::is_same_hd($part, $_); #- keep it only if it is the mountpoint AND the same device
	} else {
	    1;
	}
    } read_fstab($prefix, "/etc/fstab", 'all_options');

    merge_fstabs($loose, $fstab, @l);
}

sub prepare_write_fstab {
    my ($all_hds, $prefix, $keep_smb_credentials) = @_;
    $prefix ||= '';

    my @l1 = (fsedit::get_really_all_fstab($all_hds), @{$all_hds->{special}});
    my @l2 = read_fstab($prefix, "/etc/fstab", 'all_options');

    {
	#- remove entries from @l2 that are given by @l1
	#- this is needed to allow to unset a mount point
	my %new; 
	$new{$_->{device}} = 1 foreach @l1;
	delete $new{none}; #- special case for device "none" which can be _mounted_ more than once
	@l2 = grep { !$new{$_->{device}} } @l2;
    }

    my %new;
    my @smb_credentials;
    my @l = map { 
	my $device = 
	  $_->{device} eq 'none' || member($_->{type}, qw(nfs smbfs)) ? 
	      $_->{device} : 
	  isLoopback($_) ? 
	      ($_->{mntpoint} eq '/' ? "/initrd/loopfs" : "$_->{loopback_device}{mntpoint}") . $_->{loopback_file} :
	  do {
	      my $dir = $_->{device} =~ m|^/| ? '' : '/dev/';
	      eval { devices::make("$prefix$dir$_->{device}") };
	      "$dir$_->{device}";
	  };

	my $real_mntpoint = $_->{mntpoint} || ${{ '/tmp/hdimage' => '/mnt/hd' }}{$_->{real_mntpoint}};
	mkdir("$prefix$real_mntpoint", 0755) if $real_mntpoint =~ m|^/|;
	my $mntpoint = loopback::carryRootLoopback($_) ? '/initrd/loopfs' : $real_mntpoint;

	my ($freq, $passno) =
	  exists $_->{freq} ?
	    ($_->{freq}, $_->{passno}) :
	  isTrueFS($_) && $_->{options} !~ /encryption=/ ? 
	    (1, $_->{mntpoint} eq '/' ? 1 : loopback::carryRootLoopback($_) ? 0 : 2) : 
	    (0, 0);

	if (($device eq 'none' || !$new{$device}) && ($mntpoint eq 'swap' || !$new{$mntpoint})) {
	    #- keep in mind the new line for fstab.
	    $new{$device} = 1;
	    $new{$mntpoint} = 1;

	    my $options = $_->{options};

	    if (isThisFs('smbfs', $_) && $options =~ /password=/ && !$keep_smb_credentials) {
		require network::smb;
		if (my ($opts, $smb_credentials) = network::smb::fstab_entry_to_credentials($_)) {
		    $options = $opts;
		    push @smb_credentials, $smb_credentials;
		}
	    }

	    my $type = type2fs($_);

	    my $dev = $_->{device_alias} ? "/dev/$_->{device_alias}" : $device;

	    $mntpoint =~ s/ /\\040/g;
	    $dev =~ s/ /\\040/g;

	    # handle bloody supermount special case
	    if ($options =~ /supermount/) {
		my @l = grep { $_ ne 'supermount' } split(',', $options);
		my @l1 = grep { member($_, 'ro', 'exec') } @l;
		my @l2 = difference2(\@l, \@l1);
		$options = join(",", "dev=$dev", "fs=$type", @l1, if_(@l2, '--', @l2));
		($dev, $type) = ('none', 'supermount');
	    }

	    [ $mntpoint, $_->{comment} . join(' ', $dev, $mntpoint, $type, $options || 'defaults', $freq, $passno) . "\n" ];
	} else {
	    ()
	}
    } grep { $_->{device} && ($_->{mntpoint} || $_->{real_mntpoint}) && $_->{type} } (@l1, @l2);

    join('', map { $_->[1] } sort { $a->[0] cmp $b->[0] } @l), \@smb_credentials;
}

sub fstab_to_string {
    my ($all_hds, $prefix) = @_;
    my ($s, undef) = prepare_write_fstab($all_hds, $prefix, 'keep_smb_credentials');
    $s;
}

sub write_fstab {
    my ($all_hds, $prefix) = @_;
    log::l("writing $prefix/etc/fstab");
    my ($s, $smb_credentials) = prepare_write_fstab($all_hds, $prefix, '');
    output("$prefix/etc/fstab", $s);
    network::smb::save_credentials($_) foreach @$smb_credentials;
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
		  reiserfs => [ 'notail' ],
		 );
    push @{$per_fs{$_}}, 'usrquota', 'grpquota' foreach 'ext2', 'ext3', 'xfs';

    while (my ($fs, $l) = each %per_fs) {
	isThisFs($fs, $part) || $part->{type} eq 'auto' && member($fs, @auto_fs) or next;
	$non_defaults->{$_} = 1 foreach @$l;
    }

    $non_defaults->{encrypted} = 1 if !$part->{isFormatted} || isSwap($part);

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

sub mount_options_pack_ {
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

    join(",", uniq(grep { $_ } @l));
}
sub mount_options_pack {
    my ($part, $options, $unknown) = @_;
    $part->{options} = mount_options_pack_($part, $options, $unknown);
    MDK::Common::Various::noreturn();
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
    my ($part, $is_removable, $useSupermount, $security, $iocharset, $codepage) = @_;

    my ($options, $unknown) = mount_options_unpack($part);

    if ($is_removable) {
	$options->{supermount} = $useSupermount;
	$part->{type} = 'auto';	# if supermount, code below will handle choosing the right type
    }

    my $is_auto = isThisFs('auto', $part);

    if ($options->{supermount} && $is_auto) {
	# this can't work, guessing :-(
	$part->{type} = fs2type($part->{media_type} eq 'cdrom' ? 'iso9660' : 'vfat');
	$is_auto = 0;
    }

    if ($part->{media_type} eq 'cdrom') {
	$options->{ro} = 1;
    }

    if ($part->{media_type} eq 'fd') {
	# slow device so don't loose time, write now!
	$options->{sync} = 1;
    }

    if (isTrueFS($part)) {
	#- noatime on laptops (do not wake up the hd)
	#- Do  not  update  inode  access times on this
	#- file system (e.g, for faster access  on  the
	#- news spool to speed up news servers).
	$options->{noatime} = detect_devices::isLaptop();
    }
    if (isNfs($part)) {
	put_in_hash($options, { 
			       nosuid => 1, 'rsize=8192,wsize=8192' => 1, soft => 1,
			      });
    }
    if (isFat($part) || $is_auto) {

	put_in_hash($options, {
			       user => 1, noexec => 0,
			      }) if !exists $part->{rootDevice}; # partition means no removable media

	put_in_hash($options, {
			       'umask=0' => $security < 3, 'iocharset=' => $iocharset, 'codepage=' => $codepage,
			      });
    }
    if (isThisFs('ntfs', $part) || $is_auto) {
	put_in_hash($options, { 'iocharset=' => $iocharset });
    }
    if (isThisFs('iso9660', $part) || $is_auto) {
	put_in_hash($options, { user => 1, noexec => 0, 'iocharset=' => $iocharset });
    }
    if (isThisFs('reiserfs', $part)) {
	$options->{notail} = 1;
    }
    if (isLoopback($part) && !isSwap($part)) { #- no need for loop option for swap files
	$options->{loop} = 1;
    }

    # rationalize: no need for user
    if ($options->{autofs} || $options->{supermount}) {
	$options->{user} = 0;
    }

    # have noauto when we have user
    $options->{noauto} = 1 if $options->{user}; 

    if ($options->{user}) {
	# ensure security  (user_implies - noexec as noexec is not a security matter)
	$options->{$_} = 1 foreach 'nodev', 'nosuid';
    }

    mount_options_pack($part, $options, $unknown);
}

sub set_all_default_options {
    my ($all_hds, $useSupermount, $security, $iocharset, $codepage) = @_;

    my @removables = @{$all_hds->{raw_hds}};

    foreach my $part (fsedit::get_really_all_fstab($all_hds)) {
	set_default_options($part, member($part, @removables), $useSupermount, $security, $iocharset, $codepage);
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
	if ($name) {
	    my $s = ++$names{$name};
	    $_->{mntpoint} ||= "/mnt/$name" . ($s == 1 ? '' : $s);
	}
    }
}

sub get_raw_hds {
    my ($prefix, $all_hds) = @_;

    $all_hds->{raw_hds} = 
      [ 
       detect_devices::floppies(), 
       detect_devices::cdroms__faking_ide_scsi(), 
       detect_devices::zips__faking_ide_scsi(),
      ];
    get_major_minor(@{$all_hds->{raw_hds}});

    my @fstab = read_fstab($prefix, "/etc/fstab", 'all_options');
    $all_hds->{nfss} = [ grep { isNfs($_) } @fstab ];
    $all_hds->{smbs} = [ grep { isThisFs('smbfs', $_) } @fstab ];
    $all_hds->{special} = [
       (grep { isThisFs('tmpfs', $_) } @fstab),
       { device => 'none', mntpoint => '/proc', type => 'proc' },
       { device => 'none', mntpoint => '/dev/pts', type => 'devpts', options => 'mode=0620' },
    ];
}

################################################################################
# formatting functions
################################################################################
sub disable_forced_fsck {
    my ($dev) = @_;
    run_program::run("tune2fs", "-c0", "-i0", devices::make($dev));
}

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
    disable_forced_fsck($dev);
}
sub format_reiserfs {
    my ($dev, @options) = @_;
    #TODO add -h tea
    run_program::run("mkreiserfs", "-ff", @options, devices::make($dev)) or die _("%s formatting of %s failed", "reiserfs", $dev);
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

    my $dev = $part->{real_device} || $part->{device};

    my @options = $part->{toFormatCheck} ? "-c" : ();
    log::l("formatting device $dev (type ", type2name($part->{type}), ")");

    if (isExt2($part)) {
	push @options, "-F" if isLoopback($part);
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
	format_ext2($dev, @options);
    } elsif (isThisFs("ext3", $part)) {
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
        format_ext3($dev, @options);
    } elsif (isThisFs("reiserfs", $part)) {
        format_reiserfs($dev, @options, if_(c::kernel_version() =~ /^\Q2.2/, "-v", "1"));
    } elsif (isThisFs("xfs", $part)) {
        format_xfs($dev, @options);
    } elsif (isThisFs("jfs", $part)) {
        format_jfs($dev, @options);
    } elsif (isDos($part)) {
        format_dos($dev, @options);
    } elsif (isWin($part)) {
        format_dos($dev, @options, '-F', 32);
    } elsif (isThisFs('hfs', $part)) {
        format_hfs($dev, @options, '-l', "Untitled");
    } elsif (isAppleBootstrap($part)) {
        format_hfs($dev, @options, '-l', "bootstrap");
    } elsif (isSwap($part)) {
	my $check_blocks = grep { /^-c$/ } @options;
        swap::make($dev, $check_blocks);
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
sub set_loop {
    my ($part) = @_;
    if (!$part->{real_device}) {
	eval { modules::load('loop') };
	$part->{real_device} = devices::set_loop(devices::make($part->{device}), $part->{encrypt_key}, $part->{options} =~ /encryption=(\w+)/);
    }
}

sub formatMount_part {
    my ($part, $raids, $fstab, $prefix, $callback) = @_;

    if (isLoopback($part)) {
	formatMount_part($part->{loopback_device}, $raids, $fstab, $prefix, $callback);
    }
    if (my $p = up_mount_point($part->{mntpoint}, $fstab)) {
	formatMount_part($p, $raids, $fstab, $prefix, $callback) unless loopback::carryRootLoopback($part);
    }
    if ($part->{encrypt_key}) {
	set_loop($part);
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
    my ($dev, $where, $fs, $rdonly, $options) = @_;
    log::l("mounting $dev on $where as type $fs, options $options");

    -d $where or mkdir_p($where);

    my @fs_modules = qw(vfat hfs romfs ufs reiserfs xfs jfs ext3);

    if (member($fs, 'smb', 'smbfs', 'nfs', 'ntfs') && $::isStandalone) {
	system('mount', '-t', $fs, $dev, $where, '-o', $options) == 0 or die _("mounting partition %s in directory %s failed", $dev, $where);
	return; #- do not update mtab, already done by mount(8)
    } elsif (member($fs, 'ext2', 'proc', 'usbdevfs', 'iso9660', @fs_modules)) {
	$dev = devices::make($dev) if $fs ne 'proc' && $fs ne 'usbdevfs';
	$where =~ s|/$||;

	my $flag = c::MS_MGC_VAL();
	$flag |= c::MS_RDONLY() if $rdonly;
	my $mount_opt = "";

	if ($fs eq 'vfat') {
	    $mount_opt = 'check=relaxed';
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
	if (member($fs, @fs_modules)) {
	    eval { modules::load($fs) };
	} elsif ($fs eq 'iso9660') {
	    eval { modules::load('isofs') };
	}
	if ($fs eq 'ext3' && $::isInstall) {
	    # ext3 mount to use the journal
	    syscall_('mount', $dev, $where, $fs, $flag, $mount_opt) or die _("mounting partition %s in directory %s failed", $dev, $where) . " ($!)";
	    syscall_('umount', $where);
	    # really mount as ext2 during install for speed up
	    $fs = 'ext2';
	}
	log::l("calling mount($dev, $where, $fs, $flag, $mount_opt)");
	syscall_('mount', $dev, $where, $fs, $flag, $mount_opt) or die _("mounting partition %s in directory %s failed", $dev, $where) . " ($!)";
    } else {
	log::l("skipping mounting $fs partition");
	return;
    }
    local *F;
    open F, ">>/etc/mtab" or return; #- fail silently, /etc must be read-only
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

    log::l("isMounted=$part->{isMounted}, real_mntpoint=$part->{real_mntpoint}, mntpoint=$part->{mntpoint}");
    if ($part->{isMounted} && $part->{real_mntpoint} && $part->{mntpoint}) {
	log::l("remounting partition on $prefix$part->{mntpoint} instead of $part->{real_mntpoint}");
	if ($::isInstall) { #- ensure partition will not be busy.
	    require install_any;
	    install_any::getFile('XXX');
	}
	eval {
	    umount($part->{real_mntpoint});
	    rmdir $part->{real_mntpoint};
	    symlinkf "$prefix$part->{mntpoint}", $part->{real_mntpoint};
	    delete $part->{real_mntpoint};
	    $part->{isMounted} = 0;
	};
    }

    return if $part->{isMounted};

    unless ($::testing) {
	if (isSwap($part)) {
	    swap::swapon($part->{device});
	} else {
	    $part->{mntpoint} or die "missing mount point for partition $part->{device}";

	    my $mntpoint = ($prefix || '') . $part->{mntpoint};
	    if (isLoopback($part) || $part->{encrypt_key}) {
		set_loop($part);
	    } elsif (loopback::carryRootLoopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    my $dev = $part->{real_device} || $part->{device};
	    mount($dev, $mntpoint, type2fs($part), $rdonly, $part->{options});
	    rmdir "$mntpoint/lost+found";
	}
    }
    $part->{isMounted} = $part->{isFormatted} = 1; #- assume that if mount works, partition is formatted
}

sub umount_part {
    my ($part, $prefix) = @_;

    $part->{isMounted} || $part->{real_mntpoint} or return;

    unless ($::testing) {
	if (isSwap($part)) {
	    swap::swapoff($part->{device});
	} elsif (loopback::carryRootLoopback($part)) {
	    umount("/initrd/loopfs");
	} else {
	    umount(($prefix || '') . $part->{mntpoint} || devices::make($part->{device}));
	    devices::del_loop(delete $part->{real_device}) if $part->{real_device};
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
