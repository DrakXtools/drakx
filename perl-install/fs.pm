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
    my ($prefix, $file, @reading_options) = @_;

    if (member('keep_default', @reading_options)) {
	push @reading_options, 'freq_passno', 'keep_devfs_name', 'keep_device_LABEL';
    }

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
		 if_(member('keep_freq_passno', @reading_options), freq => $freq, passno => $passno),
		};

	put_in_hash($h, subpart_from_wild_device_name($dev));

	if ($h->{device_LABEL} && member('keep_device_LABEL', @reading_options)) {
	    $h->{prefer_device_LABEL} = 1;
        } elsif ($h->{devfs_device} && member('keep_devfs_name', @reading_options)) {
	    $h->{prefer_devfs_name} = 1;
	}

	if ($h->{options} =~ /credentials=/ && !member('verbatim_credentials', @reading_options)) {
	    require network::smb;
	    #- remove credentials=file with username=foo,password=bar,domain=zoo
	    #- the other way is done in fstab_to_string
	    my ($options, $unknown) = mount_options_unpack($h);
	    my $file = delete $options->{'credentials='};
	    my $credentials = network::smb::read_credentials_raw($file);
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
	my ($l1, $l2) = partition { fsedit::is_same_hd($_, $p) } @l;
	my ($p2) = @$l1 or next;
	@l = @$l2;

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

sub subpart_from_wild_device_name {
    my ($dev) = @_;

    if ($dev =~ /^LABEL=(.*)/) {
	{ device_LABEL => $1 };
    } elsif ($dev =~ m,^/(tmp|dev)/,) {
	my %part;
	($part{major}, $part{minor}) = unmakedev((stat "$::prefix$dev")[6]);

	if (my $symlink = readlink("$::prefix$dev")) {
	    if ($symlink =~ m|^[^/]+$|) {
		$part{device_alias} = $dev;
		$dev = $symlink;
	    }
	}
	$dev =~ s,^/(tmp|dev)/,,;

	my $is_devfs = $dev =~ m!/(disc|part\d+)$!;
	$part{$is_devfs ? 'devfs_device' : 'device'} = $dev;
	\%part;
    } else {
	if ($dev eq 'none') {
	} elsif ($dev =~ m!^(\w+):/\w!) {
	    #- nfs
	} elsif ($dev =~ m!^//\w!) {
	    #- smb
	} else {
	    log::l("part_from_wild_device_name: unknown device $dev");
	}
	{ device => $dev };
    }
}

sub add2all_hds {
    my ($all_hds, @l) = @_;

    @l = merge_fstabs('', [ fsedit::get_really_all_fstab($all_hds) ], @l);

    foreach (@l) {
	my $s = 
	    isThisFs('nfs', $_) ? 'nfss' :
	    isThisFs('smbfs', $_) ? 'smbs' :
	    isThisFs('davfs', $_) ? 'davs' :
	    isTrueLocalFS($_) || isSwap($_) || isOtherAvailableFS($_) ? '' :
	    'special';
	push @{$all_hds->{$s}}, $_ if $s;
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
	if ($::isInstall && $_->{mntpoint} =~ m!/tmp/(image|hdimage)!) {
	    $_->{real_mntpoint} = delete $_->{mntpoint};
	    if ($_->{real_mntpoint} eq '/tmp/hdimage') {
		log::l("found hdimage on $_->{device}");
		$_->{mntpoint} = common::usingRamdisk() && "/mnt/hd"; #- remap for hd install.
	    }
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
    } read_fstab($prefix, '/etc/fstab', 'keep_default');

    merge_fstabs($loose, $fstab, @l);
}

# - when using "$loose", it does not merge in type&options from the fstab
sub get_info_from_fstab {
    my ($all_hds, $prefix) = @_;
    my @l = read_fstab($prefix, '/etc/fstab', 'keep_default');
    add2all_hds($all_hds, @l)
}

sub prepare_write_fstab {
    my ($fstab, $o_prefix, $b_keep_smb_credentials) = @_;
    $o_prefix ||= '';

    my %new;
    my @smb_credentials;
    my @l = map { 
	my $device = 
	  isLoopback($_) ? 
	      ($_->{mntpoint} eq '/' ? "/initrd/loopfs" : $_->{loopback_device}{mntpoint}) . $_->{loopback_file} :
	  part2device($o_prefix, $_->{prefer_devfs_name} ? $_->{devfs_device} : $_->{device}, $_->{type});

	my $real_mntpoint = $_->{mntpoint} || ${{ '/tmp/hdimage' => '/mnt/hd' }}{$_->{real_mntpoint}};
	mkdir_p("$o_prefix$real_mntpoint") if $real_mntpoint =~ m|^/|;
	my $mntpoint = loopback::carryRootLoopback($_) ? '/initrd/loopfs' : $real_mntpoint;

	my ($freq, $passno) =
	  exists $_->{freq} ?
	    ($_->{freq}, $_->{passno}) :
	  isTrueLocalFS($_) && $_->{options} !~ /encryption=/ && !$_->{is_removable} ? 
	    (1, $_->{mntpoint} eq '/' ? 1 : loopback::carryRootLoopback($_) ? 0 : 2) : 
	    (0, 0);

	if (($device eq 'none' || !$new{$device}) && ($mntpoint eq 'swap' || !$new{$mntpoint})) {
	    #- keep in mind the new line for fstab.
	    $new{$device} = 1;
	    $new{$mntpoint} = 1;

	    my $options = $_->{options};

	    if (isThisFs('smbfs', $_) && $options =~ /password=/ && !$b_keep_smb_credentials) {
		require network::smb;
		if (my ($opts, $smb_credentials) = network::smb::fstab_entry_to_credentials($_)) {
		    $options = $opts;
		    push @smb_credentials, $smb_credentials;
		}
	    }

	    my $type = type2fs($_, 'auto');

	    my $dev = 
	      $_->{prefer_device_LABEL} ? 'LABEL=' . $_->{device_LABEL} :
	      $_->{device_alias} ? "/dev/$_->{device_alias}" : $device;

	    $mntpoint =~ s/ /\\040/g;
	    $dev =~ s/ /\\040/g;

	    # handle bloody supermount special case
	    if ($options =~ /supermount/) {
		my @l = grep { $_ ne 'supermount' } split(',', $options);
		my @l1 = grep { member($_, 'ro', 'exec') } @l;
		my @l2 = difference2(\@l, \@l1);
		$options = join(",", "dev=$dev", "fs=$type", @l1, if_(@l2, '--', @l2));
		($dev, $type) = ('none', 'supermount');
	    } else {
		#- if we were using supermount, the type could be something like ext2:vfat
		#- but this can't be done without supermount, so switching to "auto"
		$type = 'auto' if $type =~ /:/;
	    }

	    [ $mntpoint, $_->{comment} . join(' ', $dev, $mntpoint, $type, $options || 'defaults', $freq, $passno) . "\n" ];
	} else {
	    ()
	}
    } grep { $_->{device} && ($_->{mntpoint} || $_->{real_mntpoint}) && $_->{type} && ($_->{isFormatted} || !$_->{notFormatted}) } @$fstab;

    join('', map { $_->[1] } sort { $a->[0] cmp $b->[0] } @l), \@smb_credentials;
}

sub fstab_to_string {
    my ($all_hds, $o_prefix) = @_;
    my $fstab = [ fsedit::get_really_all_fstab($all_hds), @{$all_hds->{special}} ];
    my ($s, undef) = prepare_write_fstab($fstab, $o_prefix, 'keep_smb_credentials');
    $s;
}

sub write_fstab {
    my ($all_hds, $o_prefix) = @_;
    log::l("writing $o_prefix/etc/fstab");
    my $fstab = [ fsedit::get_really_all_fstab($all_hds), @{$all_hds->{special}} ];
    my ($s, $smb_credentials) = prepare_write_fstab($fstab, $o_prefix, '');
    output("$o_prefix/etc/fstab", $s);
    network::smb::save_credentials($_) foreach @$smb_credentials;
}

sub part2device {
    my ($prefix, $dev, $type) = @_;
    $dev eq 'none' || member($type, qw(nfs smbfs davfs)) ? 
      $dev : 
      do {
	  my $dir = $dev =~ m!^(/|LABEL=)! ? '' : '/dev/';
	  eval { devices::make("$prefix$dir$dev") };
	  "$dir$dev";
      };
}

sub auto_fs() {
    grep { chop; $_ && !/nodev/ } cat_("/etc/filesystems");
}

sub mount_options() {
    my %non_defaults = (
			sync => 'async', noatime => 'atime', noauto => 'auto', ro => 'rw', 
			user => 'nouser', nodev => 'dev', noexec => 'exec', nosuid => 'suid',
		       );
    my @user_implies = qw(noexec nodev nosuid);
    \%non_defaults, \@user_implies;
}

sub mount_options_unpack {
    my ($part) = @_;
    my $packed_options = $part->{options};

    my ($non_defaults, $user_implies) = mount_options();

    my @auto_fs = auto_fs();
    my %per_fs = (
		  iso9660 => [ qw(unhide) ],
		  vfat => [ qw(umask=0 umask=0022) ],
		  ntfs => [ qw(umask=0 umask=0022) ],
		  nfs => [ qw(rsize=8192 wsize=8192) ],
		  smbfs => [ qw(username= password=) ],
		  davfs => [ qw(username= password= uid= gid=) ],
		  reiserfs => [ 'notail' ],
		 );
    push @{$per_fs{$_}}, 'usrquota', 'grpquota' foreach 'ext2', 'ext3', 'xfs';

    while (my ($fs, $l) = each %per_fs) {
	isThisFs($fs, $part) || $part->{type} eq 'auto' && member($fs, @auto_fs) or next;
	$non_defaults->{$_} = 1 foreach @$l;
    }

    $non_defaults->{encrypted} = 1 if !$part->{isFormatted} || isSwap($part);

    $non_defaults->{supermount} = 1 if $part->{type} =~ /:/ || member(type2fs($part), 'auto', @auto_fs);

    my $defaults = { reverse %$non_defaults };
    my %options = map { $_ => '' } keys %$non_defaults;
    my @unknown;
    foreach (split(",", $packed_options)) {
	if ($_ eq 'user') {
	    $options{$_} = 1 foreach 'user', @$user_implies;
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
    my ($_part, $options, $unknown) = @_;

    my ($non_defaults, $user_implies) = mount_options();
    my @l;

    my @umasks = map {
	if (/^umask=/) {
	    my $v = delete $options->{$_};
	    /^umask=(.+)/ ? if_($v, $1) : $v;
	} else { () }
    } keys %$options;
    if (@umasks) {
	push @l, 'umask=' . min(@umasks);
    }

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
    noreturn();
}

# update me on each util-linux new release:
sub mount_options_help() {
    (

	'grpquota' => '',

	'noatime' => N("Do not update inode access times on this file system
(e.g, for faster access on the news spool to speed up news servers)."),

	'noauto' => N("Can only be mounted explicitly (i.e.,
the -a option will not cause the file system to be mounted)."),

	'nodev' => N("Do not interpret character or block special devices on the file system."),

	'noexec' => N("Do not allow execution of any binaries on the mounted
file system. This option might be useful for a server that has file systems
containing binaries for architectures other than its own."),

	'nosuid' => N("Do not allow set-user-identifier or set-group-identifier
bits to take effect. (This seems safe, but is in fact rather unsafe if you
have suidperl(1) installed.)"),

	'ro' => N("Mount the file system read-only."),

	'sync' => N("All I/O to the file system should be done synchronously."),

	'supermount' => '',

	'user' => N("Allow an ordinary user to mount the file system. The
name of the mounting user is written to mtab so that he can unmount the file
system again. This option implies the options noexec, nosuid, and nodev
(unless overridden by subsequent options, as in the option line
user,exec,dev,suid )."),

	'usrquota' => '',

        'umask=0' => N("Give write access to ordinary users"),

        'umask=0022' => N("Give read-only access to ordinary users"),
    );
}

sub set_default_options {
    my ($part, %opts) = @_;
    #- opts are: useSupermount security iocharset codepage

    my ($options, $unknown) = mount_options_unpack($part);

    if ($part->{is_removable}) {
	$options->{supermount} = $opts{useSupermount} && !($opts{useSupermount} eq 'magicdev' && $part->{media_type} eq 'cdrom');
	$part->{type} = !$options->{supermount} ? 'auto' :
	  $part->{media_type} eq 'cdrom' ? 'udf:iso9660' : 'ext2:vfat';
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
    if (isThisFs('nfs', $part)) {
	put_in_hash($options, { 
			       nosuid => 1, 'rsize=8192,wsize=8192' => 1, soft => 1,
			      });
    }
    if (isThisFs('smbfs', $part)) {
	add2hash($options, { 'username=' => '%' }) if !$options->{'credentials='};
    }
    if (isFat($part) || member('vfat', split(':', $part->{type})) || isThisFs('auto', $part)) {

	put_in_hash($options, {
			       user => 1, noexec => 0,
			      }) if $part->{is_removable};

	put_in_hash($options, {
			       'umask=0' => $opts{security} < 3, 'umask=0022' => $opts{security} < 4,
			       'iocharset=' => $opts{iocharset}, 'codepage=' => $opts{codepage},
			      });
    }
    if (isThisFs('ntfs', $part)) {
	put_in_hash($options, { ro => 1, 'nls=' => $opts{iocharset},
				'umask=0' => $opts{security} < 3, 'umask=0022' => $opts{security} < 4,
			      });
    }
    if (member('iso9660', split(':', $part->{type})) || isThisFs('auto', $part)) {
	put_in_hash($options, { user => 1, noexec => 0, 'iocharset=' => $opts{iocharset} });
    }
    if (isThisFs('reiserfs', $part)) {
	$options->{notail} = 1;
    } else {
	$options->{notail} = 0;
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
    my ($all_hds, %opts) = @_;
    #- opts are: useSupermount security iocharset codepage

    foreach my $part (fsedit::get_really_all_fstab($all_hds)) {
	set_default_options($part, %opts);
    }
}

sub set_removable_mntpoints {
    my ($all_hds) = @_;

    my %names;
    foreach (@{$all_hds->{raw_hds}}) {
	my $name = detect_devices::suggest_mount_point($_) or next;
	$name eq 'zip' and next;
	
	my $s = ++$names{$name};
	$_->{mntpoint} ||= "/mnt/$name" . ($s == 1 ? '' : $s);
    }
}

sub get_raw_hds {
    my ($prefix, $all_hds) = @_;

    push @{$all_hds->{raw_hds}}, detect_devices::removables();
    $_->{is_removable} = 1 foreach @{$all_hds->{raw_hds}};
    $_->{is_removable} = 1 foreach map { partition_table::get_normal_parts($_) } grep { $_->{usb_media_type} } @{$all_hds->{hds}};

    get_major_minor(@{$all_hds->{raw_hds}});

    my @fstab = read_fstab($prefix, '/etc/fstab', 'keep_default');
    $all_hds->{nfss} = [ grep { isThisFs('nfs', $_) } @fstab ];
    $all_hds->{smbs} = [ grep { isThisFs('smbfs', $_) } @fstab ];
    $all_hds->{davs} = [ grep { isThisFs('davfs', $_) } @fstab ];
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
    run_program::raw({ timeout => 60 * 60 }, 'mke2fs', '-F', @options, devices::make($dev)) or die N("%s formatting of %s failed", (any { $_ eq '-j' } @options) ? "ext3" : "ext2", $dev);
}
sub format_ext3 {
    my ($dev, @options) = @_;
    format_ext2($dev, "-j", @options);
    disable_forced_fsck($dev);
}
sub format_reiserfs {
    my ($dev, @options) = @_;
    #TODO add -h tea
    run_program::raw({ timeout => 60 * 60 }, "mkreiserfs", "-ff", @options, devices::make($dev)) or die N("%s formatting of %s failed", "reiserfs", $dev);
}
sub format_xfs {
    my ($dev, @options) = @_;
    run_program::raw({ timeout => 60 * 60 }, "mkfs.xfs", "-f", "-q", @options, devices::make($dev)) or die N("%s formatting of %s failed", "xfs", $dev);
}
sub format_jfs {
    my ($dev, @options) = @_;
    run_program::raw({ timeout => 60 * 60 }, "mkfs.jfs", "-f", @options, devices::make($dev)) or die N("%s formatting of %s failed", "jfs", $dev);
}
sub format_dos {
    my ($dev, @options) = @_;
    run_program::raw({ timeout => 60 * 60 }, "mkdosfs", @options, devices::make($dev)) or die N("%s formatting of %s failed", "dos", $dev);
}
sub format_hfs {
    my ($dev, @options) = @_;
    run_program::raw({ timeout => 60 * 60 }, "hformat", @options, devices::make($dev)) or die N("%s formatting of %s failed", "HFS", $dev);
}
sub real_format_part {
    my ($part) = @_;

    $part->{isFormatted} and return;

    if ($part->{encrypt_key}) {
	set_loop($part);
    }

    my $dev = $part->{real_device} || $part->{device};

    my @options = if_($part->{toFormatCheck}, "-c");
    log::l("formatting device $dev (type ", type2name($part->{type}), ")");

    if (isExt2($part)) {
	push @options, "-F" if isLoopback($part);
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
	format_ext2($dev, @options);
    } elsif (isThisFs("ext3", $part)) {
	push @options, "-m", "0" if $part->{mntpoint} =~ m|^/home|;
        format_ext3($dev, @options);
    } elsif (isThisFs("reiserfs", $part)) {
        format_reiserfs($dev, @options);
    } elsif (isThisFs("xfs", $part)) {
        format_xfs($dev, @options);
    } elsif (isThisFs("jfs", $part)) {
        format_jfs($dev, @options);
    } elsif (isDos($part)) {
        format_dos($dev, @options);
    } elsif (isWin($part) || isEfi($part)) {
        format_dos($dev, @options, '-F', 32);
    } elsif (isThisFs('hfs', $part)) {
        format_hfs($dev, @options, '-l', "Untitled");
    } elsif (isAppleBootstrap($part)) {
        format_hfs($dev, @options, '-l', "bootstrap");
    } elsif (isSwap($part)) {
	my $check_blocks = any { /^-c$/ } @options;
        swap::make($dev, $check_blocks);
    } else {
	die N("I don't know how to format %s in type %s", $part->{device}, type2name($part->{type}));
    }
    $part->{isFormatted} = 1;
}
sub format_part {
    my ($raids, $part, $prefix, $wait_message) = @_;
    if (isRAID($part)) {
	$wait_message->(N("Formatting partition %s", $part->{device})) if $wait_message;
	require raid;
	raid::format_part($raids, $part);
    } elsif (isLoopback($part)) {
	$wait_message->(N("Creating and formatting file %s", $part->{loopback_file})) if $wait_message;
	loopback::format_part($part, $prefix);
    } else {
	$wait_message->(N("Formatting partition %s", $part->{device})) if $wait_message;
	real_format_part($part);
    }
}

################################################################################
# mounting functions
################################################################################
sub set_loop {
    my ($part) = @_;
    $part->{real_device} ||= devices::set_loop(devices::make($part->{device}), $part->{encrypt_key}, $part->{options} =~ /encryption=(\w+)/);
}

sub formatMount_part {
    my ($part, $raids, $fstab, $prefix, $wait_message) = @_;

    if (isLoopback($part)) {
	formatMount_part($part->{loopback_device}, $raids, $fstab, $prefix, $wait_message);
    }
    if (my $p = up_mount_point($part->{mntpoint}, $fstab)) {
	formatMount_part($p, $raids, $fstab, $prefix, $wait_message) unless loopback::carryRootLoopback($part);
    }
    if ($part->{toFormat}) {
	format_part($raids, $part, $prefix, $wait_message);
    }
    mount_part($part, $prefix, 0, $wait_message);
}

sub formatMount_all {
    my ($raids, $fstab, $prefix, $o_wait_message) = @_;
    formatMount_part($_, $raids, $fstab, $prefix, $o_wait_message) 
      foreach sort { isLoopback($a) ? 1 : isSwap($a) ? -1 : 0 } grep { $_->{mntpoint} } @$fstab;

    #- ensure the link is there
    loopback::carryRootCreateSymlink($_, $prefix) foreach @$fstab;

    #- for fun :)
    #- that way, when install exits via ctrl-c, it gives hand to partition
    eval {
	my ($_type, $major, $minor) = devices::entry(fsedit::get_root($fstab)->{device});
	output "/proc/sys/kernel/real-root-dev", makedev($major, $minor);
    };
}

sub mount {
    my ($dev, $where, $fs, $b_rdonly, $o_options, $o_wait_message) = @_;
    log::l("mounting $dev on $where as type $fs, options $o_options");

    -d $where or mkdir_p($where);

    $dev = part2device('', $dev, $fs);

    $fs ne 'skip' or log::l("not mounting $dev partition"), return;

    my @fs_modules = qw(vfat hfs romfs ufs reiserfs xfs jfs ext3);

    if (member($fs, 'smb', 'smbfs', 'nfs', 'davfs', 'ntfs') && $::isStandalone || $::move) {
	$o_wait_message->(N("Mounting partition %s", $dev)) if $o_wait_message;
	system('mount', '-t', $fs, $dev, $where, if_($o_options, '-o', $o_options)) == 0 or die N("mounting partition %s in directory %s failed", $dev, $where);
    } else {
	my @types = ('ext2', 'proc', 'sysfs', 'usbdevfs', 'iso9660', 'devfs', 'devpts', @fs_modules);

	member($fs, @types) or log::l("skipping mounting $dev partition ($fs)"), return;

	$where =~ s|/$||;

	my $flag = c::MS_MGC_VAL();
	$flag |= c::MS_RDONLY() if $b_rdonly;
	my $mount_opt = "";

	if ($fs eq 'vfat') {
	    $mount_opt = 'check=relaxed';
	} elsif ($fs eq 'reiserfs') {
	    #- could be better if we knew if there is a /boot or not
	    #- without knowing it, / is forced to be mounted with notail
	    # if $where =~ m|/(boot)?$|;
	    $mount_opt = 'notail'; #- notail in any case
	} elsif ($fs eq 'jfs' && !$b_rdonly) {
	    $o_wait_message->(N("Checking %s", $dev)) if $o_wait_message;
	    #- needed if the system is dirty otherwise mounting read-write simply fails
	    run_program::raw({ timeout => 60 * 60 }, "fsck.jfs", $dev) or do {
		my $err = $?;
		die "fsck.jfs failed" if $err & 0xfc00;
	    };
	} elsif ($fs eq 'ext2' && !$b_rdonly) {
		$o_wait_message->(N("Checking %s", $dev)) if $o_wait_message;
		foreach ('-a', '-y') {
		    run_program::raw({ timeout => 60 * 60 }, "fsck.ext2", $_, $dev);
		    my $err = $?;
		    if ($err & 0x0100) {
			log::l("fsck corrected partition $dev");
		    }
		    if ($err & 0xfeff) {
			my $txt = sprintf("fsck failed on %s with exit code %d or signal %d", $dev, $err >> 8, $err & 255);
			$_ eq '-y' ? die($txt) : cdie($txt);
		    } else {
			last;
		    }
		}
	}
	if (member($fs, @fs_modules)) {
	    eval { modules::load($fs) };
	} elsif ($fs eq 'iso9660') {
	    eval { modules::load('isofs') };
	}
	log::l("calling mount($dev, $where, $fs, $flag, $mount_opt)");
	$o_wait_message->(N("Mounting partition %s", $dev)) if $o_wait_message;
	syscall_('mount', $dev, $where, $fs, $flag, $mount_opt) or die N("mounting partition %s in directory %s failed", $dev, $where) . " ($!)";
    
        eval { #- fail silently, /etc may be read-only
	    append_to_file("/etc/mtab", "$dev $where $fs defaults 0 0\n");
	};
    }
}

#- takes the mount point to umount (can also be the device)
sub umount {
    my ($mntpoint) = @_;
    $mntpoint =~ s|/$||;
    log::l("calling umount($mntpoint)");

    syscall_('umount2', $mntpoint, 0) or do {
	kill 15, fuzzy_pidofs('^fam\b');
	syscall_('umount2', $mntpoint, 0) or die N("error unmounting %s: %s", $mntpoint, $!);
    };

    substInFile { $_ = '' if /(^|\s)$mntpoint\s/ } '/etc/mtab'; #- don't care about error, if we can't read, we won't manage to write... (and mess mtab)
}

sub mount_part {
    my ($part, $o_prefix, $b_rdonly, $o_wait_message) = @_;

    #- root carrier's link can't be mounted
    loopback::carryRootCreateSymlink($part, $o_prefix);

    log::l("isMounted=$part->{isMounted}, real_mntpoint=$part->{real_mntpoint}, mntpoint=$part->{mntpoint}");
    if ($part->{isMounted} && $part->{real_mntpoint} && $part->{mntpoint}) {
	log::l("remounting partition on $o_prefix$part->{mntpoint} instead of $part->{real_mntpoint}");
	if ($::isInstall) { #- ensure partition will not be busy.
	    require install_any;
	    install_any::getFile('XXX');
	}
	eval {
	    umount($part->{real_mntpoint});
	    rmdir $part->{real_mntpoint};
	    symlinkf "$o_prefix$part->{mntpoint}", $part->{real_mntpoint};
	    delete $part->{real_mntpoint};
	    $part->{isMounted} = 0;
	};
    }

    return if $part->{isMounted};

    unless ($::testing) {
	if (isSwap($part)) {
	    $o_wait_message->(N("Enabling swap partition %s", $part->{device})) if $o_wait_message;
	    swap::swapon($part->{device});
	} else {
	    $part->{mntpoint} or die "missing mount point for partition $part->{device}";

	    my $mntpoint = ($o_prefix || '') . $part->{mntpoint};
	    if (isLoopback($part) || $part->{encrypt_key}) {
		set_loop($part);
	    } elsif (loopback::carryRootLoopback($part)) {
		$mntpoint = "/initrd/loopfs";
	    }
	    my $dev = $part->{real_device} || $part->{device};
	    mount($dev, $mntpoint, type2fs($part, 'skip'), $b_rdonly, $part->{options}, $o_wait_message);
	    rmdir "$mntpoint/lost+found";
	}
    }
    $part->{isMounted} = $part->{isFormatted} = 1; #- assume that if mount works, partition is formatted
}

sub umount_part {
    my ($part, $o_prefix) = @_;

    $part->{isMounted} || $part->{real_mntpoint} or return;

    unless ($::testing) {
	if (isSwap($part)) {
	    swap::swapoff($part->{device});
	} elsif (loopback::carryRootLoopback($part)) {
	    umount("/initrd/loopfs");
	} else {
	    umount(($o_prefix || '') . $part->{mntpoint} || devices::make($part->{device}));
	    devices::del_loop(delete $part->{real_device}) if $part->{real_device};
	}
    }
    $part->{isMounted} = 0;
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
    my ($part, $o_prefix) = @_;
    my $dir = "/tmp/tmp_fs_df";

    return $part->{free} if exists $part->{free};

    if ($part->{isMounted}) {
	$dir = ($o_prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	return; #- won't even try!
    } else {
	mkdir_p($dir);
	eval { mount($part->{device}, $dir, type2fs($part, 'skip'), 'readonly') };
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
