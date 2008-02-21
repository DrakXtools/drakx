package fs; # $Id$

use diagnostics;
use strict;

use common;
use log;
use devices;
use fs::type;
use fs::get;
use fs::format;
use fs::mount_options;
use fs::loopback;
use fs::mount;
use run_program;
use detect_devices;
use modules;
use fsedit;


sub read_fstab {
    my ($prefix, $file, @reading_options) = @_;

    if (member('keep_default', @reading_options)) {
	push @reading_options, 'freq_passno', 'keep_device_LABEL', 'keep_device_UUID';
    }

    my %comments;
    my $comment;
    my @l = grep {
	if (/^Filename\s*Type\s*Size/) {
	    0; #- when reading /proc/swaps
	} elsif (/^\s*#/) {
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
	my ($dev, $mntpoint, $fs_type, $options, $freq, $passno) = split;
	my $comment = $comments{$_};

	$options = 'defaults' if $options eq 'rw'; # clean-up for mtab read

	if ($fs_type eq 'supermount') {
	    log::l("dropping supermount");
	    $options = join(",", grep {
		if (/fs=(.*)/) {
		    $fs_type = $1;

		    #- with supermount, the type could be something like ext2:vfat
		    #- but this can not be done without supermount, so switching to "auto"
		    $fs_type = 'auto' if $fs_type =~ /:/;

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
	} elsif ($fs_type eq 'smb') {
	    # prefering type "smbfs" over "smb"
	    $fs_type = 'smbfs';
	}
	s/\\040/ /g foreach $mntpoint, $dev, $options;

	my $h = { 
		 mntpoint => $mntpoint, fs_type => $fs_type,
		 options => $options, comment => $comment,
		 if_(member('keep_freq_passno', @reading_options), freq => $freq, passno => $passno),
		};

	put_in_hash($h, fs::wild_device::to_subpart($dev));

	if ($h->{device_LABEL} && !$h->{device_alias} && member('keep_device_LABEL', @reading_options)) {
	    $h->{prefer_device_LABEL} = 1;
	} elsif ($h->{device_UUID} && !$h->{device_alias} && member('keep_device_UUID', @reading_options)) {
	    $h->{prefer_device_UUID} = 1;
	} else {
	    $h->{prefer_device} = 1;
	}

	if ($h->{options} =~ /credentials=/ && !member('verbatim_credentials', @reading_options)) {
	    require fs::remote::smb;
	    #- remove credentials=file with username=foo,password=bar,domain=zoo
	    #- the other way is done in fstab_to_string
	    my ($options, $unknown) = fs::mount_options::unpack($h);
	    my $file = delete $options->{'credentials='};
	    my $credentials = fs::remote::smb::read_credentials_raw($file);
	    if ($credentials->{username}) {
		$options->{"$_="} = $credentials->{$_} foreach qw(username password domain);
		fs::mount_options::pack($h, $options, $unknown);
	    }
	}

	$h;
    } @l;
}

sub merge_fstabs {
    my ($loose, $fstab, @l) = @_;

    foreach my $p (@$fstab) {
	my ($l1, $l2) = partition { fs::get::is_same_hd($_, $p) } @l;
	my ($p2) = @$l1 or next;
	@l = @$l2;

	$p->{mntpoint} = $p2->{mntpoint} if delete $p->{unsafeMntpoint};

	if (!$loose) {
	    $p->{fs_type} = $p2->{fs_type} if $p2->{fs_type};
	    $p->{options} = $p2->{options} if $p2->{options};
	    add2hash_($p, $p2);
	} else {
	    $p->{isMounted} ||= $p2->{isMounted};
	    $p->{real_mntpoint} ||= $p2->{real_mntpoint};
	}
	$p->{device_alias} ||= $p2->{device_alias} if $p->{device} ne $p2->{device} && $p2->{device} !~ m|/|;

	$p->{fs_type} && $p2->{fs_type} && $p->{fs_type} ne $p2->{fs_type}
	  && $p->{fs_type} ne 'auto' && $p2->{fs_type} ne 'auto' and
	    log::l("err, fstab and partition table do not agree for $p->{device} type: $p->{fs_type} vs $p2->{fs_type}");
    }
    @l;
}

sub add2all_hds {
    my ($all_hds, @l) = @_;

    @l = merge_fstabs('', [ fs::get::really_all_fstab($all_hds) ], @l);

    foreach (@l) {
	my $s = 
	    $_->{fs_type} eq 'nfs' ? 'nfss' :
	    $_->{fs_type} eq 'smbfs' ? 'smbs' :
	    $_->{fs_type} eq 'davfs2' ? 'davs' :
	    isTrueLocalFS($_) || isSwap($_) || isOtherAvailableFS($_) ? '' :
	    'special';
	push @{$all_hds->{$s}}, $_ if $s;
    }
}

sub get_major_minor {
    my ($fstab) = @_;
    foreach (@$fstab) {
	eval {
	    my (undef, $major, $minor) = devices::entry($_->{device});
	    ($_->{major}, $_->{minor}) = ($major, $minor);
	} if !$_->{major};
    }
}

sub merge_info_from_mtab {
    my ($fstab) = @_;

    my @l1 = map { my $l = $_; 
		   my $h = fs::type::fs_type2subpart('swap');
		   $h->{$_} = $l->{$_} foreach qw(device major minor); 
		   $h;
	       } read_fstab('', '/proc/swaps');
    
    my @l2 = map { read_fstab('', $_) } '/etc/mtab', '/proc/mounts';

    foreach (@l1, @l2) {
	log::l("found mounted partition on $_->{device} with $_->{mntpoint}");
	if ($::isInstall && $_->{mntpoint} =~ m!^/tmp/\w*image$!) {
	    $_->{real_mntpoint} = delete $_->{mntpoint};
	}
	$_->{isMounted} = 1;
	set_isFormatted($_, 1);
    } 
    merge_fstabs('loose', $fstab, @l1, @l2);
}

# - when using "$loose", it does not merge in type&options from the fstab
sub merge_info_from_fstab {
    my ($fstab, $prefix, $uniq, $loose) = @_;

    my @l = grep { 
	if ($uniq) {
	    my $part = fs::get::mntpoint2part($_->{mntpoint}, $fstab);
	    !$part || fs::get::is_same_hd($part, $_); #- keep it only if it is the mountpoint AND the same device
	} else {
	    1;
	}
    } read_fstab($prefix, '/etc/fstab', 'keep_default');

    merge_fstabs($loose, $fstab, @l);
}

sub get_info_from_fstab {
    my ($all_hds) = @_;
    my @l = read_fstab($::prefix, '/etc/fstab', 'keep_default');
    add2all_hds($all_hds, @l);
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
	  fs::wild_device::from_part($o_prefix, $_);

	my $comment = $_->{comment};
	$comment = '' if $comment =~ m!^Entry for /dev/.* :!;
	$comment ||= "# Entry for /dev/$_->{device} :\n" if $device =~ /^(UUID|LABEL)=/;

	my $real_mntpoint = $_->{mntpoint} || ${{ '/tmp/hdimage' => '/mnt/hd' }}{$_->{real_mntpoint}};
	mkdir_p("$o_prefix$real_mntpoint") if $real_mntpoint =~ m|^/|;
	my $mntpoint = fs::type::carry_root_loopback($_) ? '/initrd/loopfs' : $real_mntpoint;

	my ($freq, $passno) =
	  exists $_->{freq} ?
	    ($_->{freq}, $_->{passno}) :
	  isTrueLocalFS($_) && $_->{options} !~ /encryption=/ && (!$_->{is_removable} || member($_->{mntpoint}, fs::type::directories_needed_to_boot())) ? 
	    (1, $_->{mntpoint} eq '/' ? 1 : fs::type::carry_root_loopback($_) ? 0 : 2) : 
	    (0, 0);

	if (($device eq 'none' || !$new{$device}) && ($mntpoint eq 'swap' || !$new{$mntpoint})) {
	    #- keep in mind the new line for fstab.
	    $new{$device} = 1;
	    $new{$mntpoint} = 1;

	    my $options = $_->{options} || 'defaults';

	    if ($_->{fs_type} eq 'smbfs' && $options =~ /password=/ && !$b_keep_smb_credentials) {
		require fs::remote::smb;
		if (my ($opts, $smb_credentials) = fs::remote::smb::fstab_entry_to_credentials($_)) {
		    $options = $opts;
		    push @smb_credentials, $smb_credentials;
		}
	    }

	    my $fs_type = $_->{fs_type} || 'auto';

	    s/ /\\040/g foreach $mntpoint, $device, $options;

	    my $file_dep = $options =~ /\b(loop|bind)\b/ ? $device : '';

	    [ $file_dep, $mntpoint, $comment . join(' ', $device, $mntpoint, $fs_type, $options, $freq, $passno) . "\n" ];
	} else {
	    ();
	}
    } grep { $_->{device} && ($_->{mntpoint} || $_->{real_mntpoint}) && $_->{fs_type} && ($_->{isFormatted} || !$_->{notFormatted}) } @$fstab;

    sub sort_it {
	my (@l) = @_;

	if (my $file_based = find { $_->[0] } @l) {
	    my ($before, $other) = partition { $file_based->[0] =~ /^\Q$_->[1]/ } @l;
	    $file_based->[0] = ''; #- all dependencies are now in before
	    if (@$other && @$before) {
		sort_it(@$before), sort_it(@$other);
	    } else {
		sort_it(@l);
	    }
	} else {
	    sort { $a->[1] cmp $b->[1] } @l;
	}	
    }
    @l = sort_it(@l);

    join('', map { $_->[2] } @l), \@smb_credentials;
}

sub fstab_to_string {
    my ($all_hds, $o_prefix) = @_;
    my $fstab = [ fs::get::really_all_fstab($all_hds), @{$all_hds->{special}} ];
    my ($s, undef) = prepare_write_fstab($fstab, $o_prefix, 'keep_smb_credentials');
    $s;
}

sub write_fstab {
    my ($all_hds, $o_prefix) = @_;
    log::l("writing $o_prefix/etc/fstab");
    my $fstab = [ fs::get::really_all_fstab($all_hds), @{$all_hds->{special}} ];
    my ($s, $smb_credentials) = prepare_write_fstab($fstab, $o_prefix, '');
    output("$o_prefix/etc/fstab", $s);
    fs::remote::smb::save_credentials($_) foreach @$smb_credentials;
}

sub set_removable_mntpoints {
    my ($all_hds) = @_;

    my %names;
    foreach (@{$all_hds->{raw_hds}}) {
	my $name = detect_devices::suggest_mount_point($_) or next;
	$name eq 'zip' and next;
	
	my $s = ++$names{$name};
	$_->{mntpoint} ||= "/media/$name" . ($s == 1 ? '' : $s);
    }
}

sub get_raw_hds {
    my ($prefix, $all_hds) = @_;

    push @{$all_hds->{raw_hds}}, detect_devices::removables();
    $_->{is_removable} = 1 foreach @{$all_hds->{raw_hds}};

    get_major_minor($all_hds->{raw_hds});

    my @fstab = read_fstab($prefix, '/etc/fstab', 'keep_default');
    $all_hds->{nfss} = [ grep { $_->{fs_type} eq 'nfs' } @fstab ];
    $all_hds->{smbs} = [ grep { $_->{fs_type} eq 'smbfs' } @fstab ];
    $all_hds->{davs} = [ grep { $_->{fs_type} eq 'davfs2' } @fstab ];
    $all_hds->{special} = [
       (grep { $_->{fs_type} eq 'tmpfs' } @fstab),
       { device => 'none', mntpoint => '/proc', fs_type => 'proc' },
    ];
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
	return; #- will not even try!
    } else {
	mkdir_p($dir);
	eval { fs::mount::mount(devices::make($part->{device}), $dir, $part->{fs_type}, 'readonly') };
	if ($@) {
	    set_isFormatted($part, 0);
	    unlink $dir;
	    return;
	}
    }
    my (undef, $free) = MDK::Common::System::df($dir);

    if (!$part->{isMounted}) {
	fs::mount::umount($dir);
	unlink($dir);
    }

    $part->{free} = 2 * $free if defined $free;
    $part->{free};
}

1;
