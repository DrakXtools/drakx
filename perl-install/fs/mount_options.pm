package fs::mount_options;

use diagnostics;
use strict;

use common;
use fs::type;
use fs::get;
use log;

sub list() {
    my %non_defaults = (
			sync => 'async', noatime => 'atime', noauto => 'auto', ro => 'rw', 
			user => 'nouser', nodev => 'dev', noexec => 'exec', nosuid => 'suid',
			user_xattr => 'nouser_xattr',
		       );
    my @user_implies = qw(noexec nodev nosuid);
    \%non_defaults, \@user_implies;
}

sub unpack {
    my ($part) = @_;
    my $packed_options = $part->{options};

    my ($non_defaults, $user_implies) = list();

    my @auto_fs = fs::type::guessed_by_mount();
    my %per_fs = (
		  iso9660 => [ qw(unhide) ],
		  vfat => [ qw(flush umask=0 umask=0022) ],
		  ntfs => [ qw(umask=0 umask=0022) ],
		  nfs => [ qw(rsize=8192 wsize=8192) ],
		  cifs => [ qw(username= password=) ],
		  davfs2 => [ qw(username= password= uid= gid=) ],
		  reiserfs => [ 'notail' ],
		 );
    push @{$per_fs{$_}}, 'usrquota', 'grpquota' foreach 'ext2', 'ext3', 'ext4', 'xfs';
    push @{$per_fs{$_}}, 'acl' foreach 'ext2', 'ext3', 'ext4', 'reiserfs';

    while (my ($fs, $l) = each %per_fs) {
	member($part->{fs_type}, $fs, 'auto') && member($fs, @auto_fs) or next;
	$non_defaults->{$_} = 1 foreach @$l;
    }

    $non_defaults->{relatime} = 1 if isTrueLocalFS($part) || $part->{fs_type} eq 'ntfs-3g';

    my $defaults = { reverse %$non_defaults };
    my %options = map { $_ => '' } keys %$non_defaults;
    my @unknown;
    foreach (split(",", $packed_options)) {
	if ($_ eq 'defaults') {
	    #- skip
	} elsif (member($_, 'user', 'users')) {
	    $options{$_} = 1 foreach $_, @$user_implies;
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

sub pack_ {
    my ($_part, $options, $unknown) = @_;

    my ($non_defaults, $user_implies) = list();
    my @l;

    my @umasks = map {
	if (/^umask=/) {
	    my $v = delete $options->{$_};
	    /^umask=(.+)/ ? if_($v, $1) : $v;
	} else { () }
    } keys %$options;
    if (@umasks and $_part->{media_type} ne 'cdrom') {
	push @l, 'umask=' . min(@umasks);
    }

    if (my $user = find { delete $options->{$_} } 'users', 'user') {
	push @l, $user;
	delete $options->{user};
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
sub pack {
    my ($part, $options, $unknown) = @_;
    $unknown =~ s/ /,/g;
    $part->{options} = pack_($part, $options, $unknown) || 'defaults';
    noreturn();
}

# update me on each util-linux new release:
sub help() {
    (
	'acl' => N("Enable POSIX Access Control Lists"),

	'flush' => N("Flush write cache on file close"),

	'grpquota' => N("Enable group disk quota accounting and optionally enforce limits"),

	'discard' => N("Enable automatic TRIM for SSD disks"),

	'noatime' => N("Do not update inode access times on this filesystem
(e.g, for faster access on the news spool to speed up news servers)."),

	'relatime' => N("Update inode access times on this filesystem in a more efficient way
(e.g, for faster access on the news spool to speed up news servers)."),

	'noauto' => N("Can only be mounted explicitly (i.e.,
the -a option will not cause the filesystem to be mounted)."),

	'nodev' => N("Do not interpret character or block special devices on the filesystem."),

	'noexec' => N("Do not allow execution of any binaries on the mounted
filesystem. This option might be useful for a server that has filesystems
containing binaries for architectures other than its own."),

	'nosuid' => N("Do not allow set-user-identifier or set-group-identifier
bits to take effect. (This seems safe, but is in fact rather unsafe if you
have suidperl(1) installed.)"),

	'ro' => N("Mount the filesystem read-only."),

	'sync' => N("All I/O to the filesystem should be done synchronously."),

	'users' => N("Allow every user to mount and umount the filesystem."),         

	'user' => N("Allow an ordinary user to mount the filesystem."),         

	'usrquota' => N("Enable user disk quota accounting, and optionally enforce limits"),

        'user_xattr' => N("Support \"user.\" extended attributes"),

        'umask=0' => N("Give write access to ordinary users"),

        'umask=0022' => N("Give read-only access to ordinary users"),
    );
}


sub rationalize {
    my ($part) = @_;

    my ($options, $unknown) = &unpack($part);

    if ($part->{fs_type} ne 'reiserfs') {
	$options->{notail} = 0;
    }
    if (!fs::type::can_be_one_of_those_fs_types($part, 'vfat', 'cifs', 'iso9660', 'udf')) {
	delete $options->{'codepage='};
    }
    if (member($part->{mntpoint}, fs::type::directories_needed_to_boot())) {
	foreach (qw(users user noauto)) {
	    if ($options->{$_}) {
		$options->{$_} = 0;
		$options->{$_} = 0 foreach qw(nodev noexec nosuid);
	    }
	}
    }

    &pack($part, $options, $unknown);
}

sub set_default {
    my ($part, %opts) = @_;
    #- opts are: security iocharset codepage ignore_is_removable

    my ($options, $unknown) = &unpack($part);

    if (!$opts{ignore_is_removable} && $part->{is_removable} 
	  && !member($part->{mntpoint}, fs::type::directories_needed_to_boot()) 
	  && (!$part->{fs_type} || $part->{fs_type} eq 'auto' || $part->{fs_type} =~ /:/)) {
	$part->{fs_type} = 'auto';
	$options->{flush} = 1 if $part->{media_type} ne 'cdrom';
    }

    if ($part->{media_type} eq 'cdrom') {
	$options->{ro} = 1;
    }

    if ($part->{media_type} eq 'fd') {
	# slow device so do not loose time, write now!
	$options->{flush} = 1;
    }

    if (isTrueLocalFS($part)) {
	#- noatime on laptops (do not wake up the hd)
	#- otherwise relatime (wake up the hd less often / better performances)
	#- Do  not  update  inode  access times on this
	#- filesystem (e.g, for faster access  on  the
	#- news spool to speed up news servers).
	$options->{relatime} = $options->{noatime} = 0;
	$options->{ detect_devices::isLaptop() ? 'noatime' : 'relatime' } = 1 if !$opts{force_atime};
    }
    if ($part->{fs_type} eq 'nfs') {
	put_in_hash($options, { 
			       nosuid => 1, 'rsize=8192,wsize=8192' => 1, soft => 1,
			      });
    }
    if ($part->{fs_type} eq 'cifs') {
	add2hash($options, { 'username=' => '%' }) if !$options->{'credentials='};
    }
    if (fs::type::can_be_this_fs_type($part, 'vfat')) {

	put_in_hash($options, {
			       users => 1, noexec => 0,
			      }) if $part->{is_removable};

	put_in_hash($options, {
			       'umask=0' => $opts{security} <= 1,
			       'iocharset=' => $opts{iocharset}, 'codepage=' => $opts{codepage},
			      });
    }
    if ($part->{fs_type} eq 'ntfs') {
	put_in_hash($options, { ro => 1, 'nls=' => $opts{iocharset},
				'umask=0' => $opts{security} < 1, 'umask=0022' => $opts{security} < 2,
			      });
    }
    if (fs::type::can_be_this_fs_type($part, 'iso9660')) {
	put_in_hash($options, { users => 1, noexec => 0, 'iocharset=' => $opts{iocharset} });
    }
    if ($part->{fs_type} eq 'reiserfs') {
	$options->{notail} = 1;
	$options->{user_xattr} = 1;
    }
    if (member($part->{fs_type}, qw(ext2 ext3 ext4))) {
	$options->{acl} = 1;
    }
    if (isLoopback($part) && !isSwap($part)) { #- no need for loop option for swap files
	$options->{loop} = 1;
    }

    # rationalize: no need for user
    if ($options->{autofs}) {
	$options->{users} = $options->{user} = 0;
    }

    if ($options->{user} || $options->{users}) {
        # have noauto when we have user
        $options->{noauto} = 1;
	# ensure security  (user_implies - noexec as noexec is not a security matter)
	$options->{$_} = 1 foreach 'nodev', 'nosuid';
    }

    &pack($part, $options, $unknown);

    rationalize($part);
}

sub set_all_default {
    my ($all_hds, %opts) = @_;
    #- opts are: security iocharset codepage

    foreach my $part (fs::get::really_all_fstab($all_hds)) {
	set_default($part, %opts);
    }
}

1;
