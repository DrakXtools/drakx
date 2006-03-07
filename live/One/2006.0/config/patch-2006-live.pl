$o->{autoExitInstall} = 1;
$o->{build_live_system} = 1;
$o->{desktop} = 'KDE';
$o->{autologin} = ${$o->{users}}[0]->{name};


my %cmdline;
my $opt; foreach (@ARGV) {
    if (/^--?(.*)/) {
        $cmdline{$opt} = 1 if $opt;
        $opt = $1;
    } else {
        $cmdline{$opt} = $_ if $opt;
        $opt = '';
    }
} $cmdline{$opt} = 1 if $opt;
exists $cmdline{langs} and $o->{locale}{langs} = +{ map { $_ => 1 } split(':', $cmdline{langs}) };

use install_any;
package install_any;

undef *ejectCdrom;
*ejectCdrom = sub {};

use pkgs;
package pkgs;

undef *read_rpmsrate;
*read_rpmsrate = sub {
    my ($packages, $rpmsrate_flags_chosen, $f) = @_;

    my ($rates, $flags, $need_to_copy) = read_rpmsrate_raw($f);
    
    foreach (keys %$flags) {
	my $p = packageByName($packages, $_) or next;
	my @flags = (@{$flags->{$_}}, map { if_(/locales-(.*)/, qq(LOCALES"$1")) } $p->requires_nosense);

	@flags = map {
	    my ($user_flags, $known_flags) = partition { /^!?CAT_/ } split('\|\|', $_);
	    my $ok = find {
		my $inv = s/^!//;
		$inv xor do {
		    if (my ($p) = /^HW"(.*)"/) {
			return $::o->{build_live_system} ? !$inv : detect_devices::matching_desc__regexp($p);
		    } elsif (($p) = /^HW_CAT"(.*)"/) {
			return $::o->{build_live_system} ? !$inv : modules::probe_category($p);
		    } elsif (($p) = /^DRIVER"(.*)"/) {
			return $::o->{build_live_system} ? !$inv : detect_devices::matching_driver__regexp($p);
		    } elsif (($p) = /^TYPE"(.*)"/) {
			return $::o->{build_live_system} ? !$inv : detect_devices::matching_type($p);
		    } else {
			$rpmsrate_flags_chosen->{$_};
		    }
		};
	    } @$known_flags;
	    $ok ? 'TRUE' : @$user_flags ? join('||', @$user_flags) : 'FALSE';
	} @flags;

	$p->set_rate($rates->{$_});
	$p->set_rflags(member('FALSE', @flags) ? 'FALSE' : @flags);
    }
    push @{$packages->{needToCopy} ||= []}, @$need_to_copy;
};

undef *bestKernelPackage;
*bestKernelPackage = sub {
    my ($packages) = @_;

    my @kernels = packages2kernels($packages) or internal_error('no kernel available');
    my ($version_BOOT) = c::kernel_version() =~ /^(\d+\.\d+)/;
    if (my @l = grep { $_->{version} =~ /\Q$version_BOOT/ } @kernels) {
	#- favour versions corresponding to current BOOT version
	@kernels = @l;
    }
    my @preferred_exts =
      $::o->{build_live_system} ? '-i586-up-1GB' :
      detect_devices::is_xbox() ? '-xbox' :
      detect_devices::is_i586() ? '-i586-up-1GB' :
      !detect_devices::has_cpu_flag('pae') ? ('-i686-up-4GB', '-i586-up-1GB') :
      detect_devices::hasSMP() ? '-smp' :
      '';
    foreach my $prefered_ext (@preferred_exts, '') {
	if (my @l = grep { $_->{ext} eq $prefered_ext } @kernels) {
	    @kernels = @l;
	}
    }

    log::l("bestKernelPackage (" . join(':', @preferred_exts) . "): " . join(' ', map { $_->{pkg}->name } @kernels) . (@kernels > 1 ? ' (choosing the first)' : ''));
    $preferred{'kernel-source-' . $kernels[0]{version}} = undef;
    $kernels[0]{pkg};
};

undef *selected_leaves;
*selected_leaves = sub {
    my ($packages) = @_;
    my $provides = $packages->{provides};

    my @l = grep { $_->flag_requested || $_->flag_installed } @{$packages->{depslist}};

    my %required_ids;
    foreach my $pkg (@l) {
	foreach my $req ($pkg->requires_nosense) {
	    my $h = $provides->{$req} or next;
	    my @provides = my ($provide) = keys %$h;
	    @provides == 1 or next;
	    if ($provide != (exists $required_ids{$pkg->id} ? $required_ids{$pkg->id} : $pkg->id)) {
#		log::l($packages->{depslist}[$provide]->name . " is not a leaf because required by " . $pkg->name . " (through require $req)"); 
		#- $pkg requires $req, provided by $provide, so we can skip $provide
		$required_ids{$provide} = $pkg->id;
	    }
	}
    }
    [ map { $_->name } grep { ! exists $required_ids{$_->id} } @l ];    
};

use install_steps;
package install_steps;

my $old = \&configureNetwork;
undef *configureNetwork;
*configureNetwork = sub {
    my ($o) = @_;
    if ($o->{build_live_system}) {
        require network::ethernet;
        network::ethernet::install_dhcp_client($o, undef);
    }
    &$old;
};

undef *doPartitionDisksAfter;
*doPartitionDisksAfter = sub {
    my ($o) = @_;

    if (!$::testing) {
	my $hds = $o->{all_hds}{hds};
	partition_table::write($_) foreach @$hds;
	$_->{rebootNeeded} and $o->rebootNeeded foreach @$hds;
    }

    fs::set_removable_mntpoints($o->{all_hds});
    fs::mount_options::set_all_default($o->{all_hds}, %$o, lang::fs_options($o->{locale}))
	if !$o->{isUpgrade};

    $o->{fstab} = [ fs::get::fstab($o->{all_hds}) ];

    if ($::local_install) {
	my $p = fs::get::mntpoint2part($::prefix, [ fs::read_fstab('', '/proc/mounts') ]);
	my $part = fs::get::device2part($p->{device}, $o->{fstab}) || $o->{fstab}[0];
	$part->{mntpoint} = '/';
	$part->{isMounted} = 1;
    }

    fs::get::root_($o->{fstab}) or die "Oops, no root partition";

    if (arch() =~ /ppc/ && detect_devices::get_mac_generation() =~ /NewWorld/) {
	die "Need bootstrap partition to boot system!" if !(defined $partition_table::mac::bootstrap_part);
    }
    
    if (arch() =~ /ia64/ && !fs::get::has_mntpoint("/boot/efi", $o->{all_hds})) {
	die N("You must have a FAT partition mounted in /boot/efi");
    }

    if ($o->{partitioning}{use_existing_root}) {
	#- ensure those partitions are mounted so that they are not proposed in choosePartitionsToFormat
	fs::mount::part($_) foreach sort { $a->{mntpoint} cmp $b->{mntpoint} }
				    grep { $_->{mntpoint} && maybeFormatted($_) } @{$o->{fstab}};
    }

    cat_("/proc/mounts") =~ m|(\S+)\s+/tmp/nfsimage| &&
      !any { $_->{mntpoint} eq "/mnt/nfs" } @{$o->{all_hds}{nfss}} and
	push @{$o->{all_hds}{nfss}}, { fs_type => 'nfs', mntpoint => "/mnt/nfs", device => $1, options => "noauto,ro,nosuid,soft,rsize=8192,wsize=8192" };
};

use network::network;
package network::network;

undef *write_zeroconf;
*write_zeroconf = sub {
    my ($net, $in) = @_;
    my $zhostname = $net->{zeroconf}{hostname};
    my $file = $::prefix . $tmdns_file;

    if ($zhostname) {
	$in->do_pkgs->ensure_binary_is_installed('tmdns', 'tmdns', 'auto') if !$in->do_pkgs->is_installed('bind');
	$in->do_pkgs->ensure_binary_is_installed('zcip', 'zcip', 'auto');
    }

    #- write blank hostname even if disabled so that drakconnect does not assume zeroconf is enabled
    eval { substInFile { s/^\s*(hostname)\s*=.*/$1 = $zhostname/ } $file } if $zhostname || -f $file;

    require services;
    services::set_status('tmdns', $net->{zeroconf}{hostname}, $::isInstall);
};

use Xconfig::card;
package Xconfig::card;

#- don't create (potentially broken) ld.so.conf.d files for X drivers
#- anyway we don't want to configure it for the live system
undef *libgl_config;
*libgl_config = sub {};
