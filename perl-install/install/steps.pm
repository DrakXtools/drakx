package install::steps; # $Id$

use diagnostics;
use strict;
use vars qw(@filesToSaveForUpgrade @filesNewerToUseAfterUpgrade);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use install::any 'addToBeDone';
use partition_table;
use detect_devices;
use fs::any;
use fs::type;
use fs::partitioning;
use modules;
use run_program;
use lang;
use keyboard;
use fsedit;
use do_pkgs;
use install::pkgs;
use any;
use log;

our @ISA = qw(do_pkgs);

@filesToSaveForUpgrade = qw(
/etc/ld.so.conf /etc/fstab /etc/hosts /etc/conf.modules /etc/modules.conf
);

@filesNewerToUseAfterUpgrade = qw(
/etc/profile
);

#-######################################################################################
#- OO Stuff
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    bless $o, ref($type) || $type;
    return $o;
}

sub charsetChanged {
    my ($_o) = @_;
}

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub enteringStep {
    my ($_o, $step) = @_;
    log::l("starting step `$step'");
}
sub leavingStep {
    my ($o, $step) = @_;
    log::l("step `$step' finished");

    if (-d "$::prefix/root/drakx") {
	eval { cp_af("/tmp/ddebug.log", "$::prefix/root/drakx") };
	output(install::any::auto_inst_file(), install::any::g_auto_install(1));
    }

    foreach my $s (@{$o->{orderedSteps}}) {
	#- the reachability property must be recomputed each time to take
	#- into account failed step.
	next if $o->{steps}{$s}{done} && !$o->{steps}{$s}{redoable};

	my $reachable = 1;
	if (my $needs = $o->{steps}{$s}{needs}) {
	    my @l = ref($needs) ? @$needs : $needs;
	    $reachable = min(map { $o->{steps}{$_}{done} || 0 } @l);
	}
	$o->{steps}{$s}{reachable} = 1 if $reachable;
    }
    $o->{steps}{$step}{reachable} = $o->{steps}{$step}{redoable};

    while (my $f = shift @{$o->{steps}{$step}{toBeDone} || []}) {
	eval { &$f() };
	if (my $err = $@) {
	    $o->ask_warn(N("Error"), [
N("An error occurred, but I do not know how to handle it nicely.
Continue at your own risk."), formatError($err) || $err ]);
	}
    }
}

sub errorInStep { 
    my ($_o, $err) = @_;
    print "error :(\n"; 
    print "$err\n\n";
    c::_exit(1);
}
sub kill_action {}

#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;

    #- for auto_install compatibility with old $o->{lang}
    $o->{locale} = lang::system_locales_to_ourlocale($o->{lang}, $o->{lang}) if $o->{lang};
    $o->{locale}{langs} ||= { $o->{locale}{lang} => 1 };

    if (!exists $o->{locale}{country}) {
	lang::lang_changed($o->{locale});
    }

    add2hash_($o->{locale}, { utf8 => lang::utf8_should_be_needed($o->{locale}) });
    lang::set($o->{locale}, !$o->isa('interactive::gtk'));

    log::l("selectLanguage: pack_langs: ", lang::pack_langs($o->{locale}{langs}), " utf8-flag: ", to_bool($o->{locale}{utf8}));

    #- for auto_install compatibility with old $o->{keyboard} containing directly $o->{keyboard}{KEYBOARD}
    $o->{keyboard} = { KEYBOARD => $o->{keyboard} } if $o->{keyboard} && !ref($o->{keyboard});

    if (!$o->{keyboard} || $o->{keyboard}{unsafe}) {
	$o->{keyboard} = keyboard::default($o->{locale});
	$o->{keyboard}{unsafe} = 1;
	keyboard::setup_install($o->{keyboard});
    }

    $o->charsetChanged;

    addToBeDone {
	lang::write_langs($o->{locale}{langs});
    } 'formatPartitions';
    addToBeDone {
	lang::write_and_install($o->{locale}, $o->do_pkgs);
    } 'installPackages';
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o) = @_;
    keyboard::setup_install($o->{keyboard});

    addToBeDone {
	#- the bkmap keymaps in installer are deficient, we need to load the real one before keyboard::write which will generate /etc/sysconfig/console/default.kmap
	run_program::rooted($::prefix, 'loadkeys', keyboard::keyboard2kmap($o->{keyboard}))
	    or log::l("loadkeys failed");
	keyboard::write($o->{keyboard});
    } 'installPackages' if !$o->{isUpgrade} || !$o->{keyboard}{unsafe};

    if ($o->{raw_X}) {
	require Xconfig::default;
	Xconfig::default::config_keyboard($o->{raw_X}, $o->{keyboard});
	$o->{raw_X}->write;
    }
}
#------------------------------------------------------------------------------
sub acceptLicense {}

#------------------------------------------------------------------------------
sub setupSCSI {
    my ($o) = @_;
    install::any::configure_pcmcia($o);
    modules::load(modules::category2modules('disk/cdrom'));
    modules::load_category($o->{modules_conf}, 'bus/firewire');
    modules::load_category($o->{modules_conf}, 'disk/ide');
    #- load disk/ide before disk/scsi (to prevent sata deps from overriding non-libata pata modules)
    modules::load_category($o->{modules_conf}, 'disk/scsi|hardware_raid|sata|firewire');

    install::any::getHds($o);
}

#------------------------------------------------------------------------------
sub selectInstallClass {
    my ($o) = @_;

    if ($o->{partitioning}{use_existing_root} || $o->{isUpgrade}) {
	# either one root is defined (and all is ok), or we take the first one we find
	my $p = fs::get::root_($o->{fstab}) || (first(install::any::find_root_parts($o->{fstab}, $::prefix)) || die)->{part};
	$o->{migrate_device_names} = install::any::use_root_part($o->{all_hds}, $p);
    } 
}

#------------------------------------------------------------------------------
sub doPartitionDisksBefore {
    my ($o) = @_;
    eval { 
	eval { fs::mount::umount("$::prefix/sys") };
	eval { fs::mount::umount("$::prefix/proc/bus/usb") };
	eval { fs::mount::umount("$::prefix/proc") };
	eval {          fs::mount::umount_all($o->{fstab}) };
	eval { sleep 1; fs::mount::umount_all($o->{fstab}) } if $@; #- HACK
    } if $o->{fstab} && !$::testing;
}

#------------------------------------------------------------------------------
sub doPartitionDisksAfter {
    my ($o) = @_;

    fs::any::write_hds($o->{all_hds}, $o->{fstab}, !$o->{isUpgrade}, sub { $o->rebootNeeded }, $o);

    if ($::local_install) {
	my $p = fs::get::mntpoint2part($::prefix, [ fs::read_fstab('', '/proc/mounts') ]);
	my $part = find { fs::get::is_same_hd($p, $_) } @{$o->{fstab}};
	$part ||= $o->{fstab}[0];
	$part->{mntpoint} = '/';
	$part->{isMounted} = 1;
    }

    fs::any::check_hds_boot_and_root($o->{all_hds}, $o->{fstab});

    if ($o->{partitioning}{use_existing_root}) {
	#- ensure those partitions are mounted so that they are not proposed in choosePartitionsToFormat
	fs::mount::part($_) foreach sort { $a->{mntpoint} cmp $b->{mntpoint} }
				    grep { $_->{mntpoint} && maybeFormatted($_) } @{$o->{fstab}};
    }
}

#------------------------------------------------------------------------------
sub doPartitionDisks {
    my ($o) = @_;

    if ($o->{partitioning}{auto_allocate}) {
	catch_cdie { fsedit::auto_allocate($o->{all_hds}, $o->{partitions}) } sub { 1 };
    }
}

#------------------------------------------------------------------------------

sub rebootNeeded($) {
    my ($_o) = @_;
    log::l("Rebooting...");
    c::_exit(0);
}

sub choosePartitionsToFormat {
    my ($o) = @_;
    fs::partitioning::guess_partitions_to_format($o->{fstab});
}

sub formatMountPartitions {
    my ($o) = @_;
    fs::format::formatMount_all($o->{all_hds}, $o->{fstab}, undef);
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o) = @_;

    install::any::setPackages($o);
}

sub ask_deselect_media__copy_on_disk {
    my (undef, $_hdlists, $_copy_rpms_on_disk) = @_;
    0;
}

sub ask_change_cd {
    my (undef, $phys_m, $_o_rel_file) = @_;
    log::l("change to medium " . install::media::phys_medium_to_string($phys_m) . " refused (it can't be done automatically)");
    0;
}

sub selectSupplMedia { '' }

sub choosePackages {
    my ($o) = @_;

    #- now for upgrade, package that must be upgraded are
    #- selected first, after is used the same scheme as install.

    #- make sure we kept some space left for available else the system may
    #- not be able to start
    my $available = install::any::getAvailableSpace($o);
    my $availableCorrected = install::pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);
    log::l(sprintf "available size %s (corrected %s)", formatXiB($available), formatXiB($availableCorrected));

    add2hash_($o, { compssListLevel => 5 }) if !$::auto_install;

    #- !! destroying user selection of packages (they may have done individual selection before)
    exists $o->{compssListLevel}
	  and install::pkgs::setSelectedFromCompssList($o->{packages}, $o->{rpmsrate_flags_chosen}, $o->{compssListLevel}, $availableCorrected);

    $availableCorrected;
}

sub upgrading_redhat() {
    #- remove weird config files that bother Xconfig::* too much
    unlink "$::prefix/etc/X11/XF86Config";
    unlink "$::prefix/etc/X11/XF86Config-4";

    sub prefering_mdv {
	my ($lpkg, $rpkg_ver, $c) = @_;
	my $lpkg_ver = $lpkg->version . '-' . $lpkg->release;
	log::l($lpkg->name . ' ' . ': prefering ' . ($c == 1 ? "$lpkg_ver over $rpkg_ver" : "$rpkg_ver over $lpkg_ver"));
    }

    my $old_compare_pkg = \&URPM::Package::compare_pkg;
    undef *URPM::Package::compare_pkg;
    *URPM::Package::compare_pkg = sub {
	my ($lpkg, $rpkg) = @_;
	my $c = ($lpkg->release =~ /mdv|mnb/ ? 1 : 0) - ($rpkg->release =~ /mdv|mnb/ ? 1 : 0);
	if ($c) {
	    prefering_mdv($lpkg, $rpkg->version . '-' . $rpkg->release, $c);
	    $c;
	} else {
	    &$old_compare_pkg;
	}
    };

    my $old_compare = \&URPM::Package::compare;
    undef *URPM::Package::compare;
    *URPM::Package::compare = sub {
	my ($lpkg, $rpkg_ver) = @_;
	my $c = ($lpkg->release =~ /mdv|mnb/ ? 1 : 0) - ($rpkg_ver =~ /mdv|mnb/ ? 1 : 0);
	if ($c) {
	    prefering_mdv($lpkg, $rpkg_ver, $c);
	    return $c;
	}
	&$old_compare;
    };
}

sub beforeInstallPackages {
    my ($o) = @_;

    read_bootloader_config($o);

    if ($o->{isUpgrade}) {
	$o->{modules_conf}->merge_into(modules::any_conf->read);
    }

    #- save these files in case of upgrade failure.
    if ($o->{isUpgrade}) {
	foreach (@filesToSaveForUpgrade) {
	    unlink "$::prefix/$_.mdkgisave";
	    if (-e "$::prefix/$_") {
		eval { cp_af("$::prefix/$_", "$::prefix/$_.mdkgisave") };
	    }
	}
	foreach (@filesNewerToUseAfterUpgrade) {
	    unlink "$::prefix/$_.rpmnew";
	}
    }

    #- mainly for upgrading redhat packages, but it can help other
    my @should_not_be_dirs = qw(/usr/share/locale/zh_TW/LC_TIME /usr/include/GL);
    my @should_be_dirs = qw(/etc/X11/xkb);
    my @to_remove = (
		     (grep { !-l $_ && -d $_          } map { "$::prefix$_" } @should_not_be_dirs),
		     (grep { -l $_ || !-d $_ && -e $_ } map { "$::prefix$_" } @should_be_dirs),
		    );
    rm_rf(@to_remove);

    if ($o->{isUpgrade} eq 'redhat') {
	upgrading_redhat();
    }

    if ($o->{isUpgrade} =~ /redhat|conectiva/) {
	#- to ensure supermount is removed (???)
	fs::mount_options::set_all_default($o->{all_hds}, %$o, lang::fs_options($o->{locale}));
    }
	

    #- some packages need such files for proper installation.
    install::any::write_fstab($o);

    require network::network;
    network::network::add2hosts("localhost", "127.0.0.1");

    #- resolv.conf will be modified at boot time
    #- the following will ensure we have a working DNS during install
    if (-e "/etc/resolv.conf" && ! -e "$::prefix/etc/resolv.conf") {
	cp_af("/etc/resolv.conf", "$::prefix/etc");
    }

    log::l("setting excludedocs to $o->{excludedocs}");
    substInFile { s/%_excludedocs.*//; $_ .= "%_excludedocs yes\n" if eof && $o->{excludedocs} } "$::prefix/etc/rpm/macros";

    #- add oem theme if the files exists.
    mkdir_p("$::prefix/usr/share");
    install::media::getAndSaveFile_($o->{stage2_phys_medium}, "install/oem-theme.rpm", "$::prefix/usr/share/oem-theme.rpm");

    system("sh", "-c", $o->{preInstallNonRooted}) if $o->{preInstallNonRooted};
}

#- returns number of packages installed, 0 if none were selected.
sub pkg_install {
    my ($o, @l) = @_;
    log::l("selecting packages " . join(" ", @l));

    install::pkgs::select_by_package_names($o->{packages}, \@l);

    my @toInstall = install::pkgs::packagesToInstall($o->{packages});
    if (@toInstall) {
	log::l("installing packages");
	$o->installPackages;
    } else {
	log::l("all packages selected are already installed, nothing to do");
	delete $o->{packages}{rpmdb}; #- make sure rpmdb is closed
	0;
    }
}

sub installCallback {
#    my (undef, $msg, @para) = @_;
#    log::l("$msg: " . join(',', @para));
}

sub installPackages { #- complete REWORK, TODO and TOCHECK!
    my ($o) = @_;
    my $packages = $o->{packages};

    install::pkgs::remove_marked_ask_remove($packages, \&installCallback);

    #- small transaction will be built based on this selection and depslist.
    my @toInstall = install::pkgs::packagesToInstall($packages);

    my $time = time();
    { 
	local $ENV{DURING_INSTALL} = 1;
	local $ENV{TMPDIR} = '/tmp';
	local $ENV{TMP} = '/tmp';
	install::pkgs::install($o->{isUpgrade}, \@toInstall, $packages, \&installCallback);
    }
    any::writeandclean_ldsoconf($::prefix);

    run_program::rooted_or_die($::prefix, 'ldconfig');

    log::l("Install took: ", formatTimeRaw(time() - $time));
    install::media::log_sizes();
    scalar(@toInstall); #- return number of packages installed.
}

sub afterInstallPackages($) {
    my ($o) = @_;

    read_bootloader_config($o) if $o->{isUpgrade} && is_empty_hash_ref($o->{bootloader});

    die N("Some important packages did not get installed properly.
Either your cdrom drive or your cdrom is defective.
Check the cdrom on an installed computer using \"rpm -qpl media/main/*.rpm\"
") if any { m|read failed: Input/output error| } cat_("$::prefix/root/drakx/install.log");

    if (arch() !~ /^sparc/) { #- TODO restore it as may be needed for sparc
	-x "$::prefix/usr/bin/dumpkeys" or $::testing or die 
"Some important packages did not get installed properly.

Please switch to console 2 (using ctrl-alt-f2)
and look at the log file /tmp/ddebug.log

Consoles 1,3,4,7 may also contain interesting information";
    }

    #-  why not? cuz weather is nice today :-) [pixel]
    common::sync(); common::sync();

    #- generate /etc/lvmtab needed for rc.sysinit
    run_program::rooted($::prefix, 'lvm2', 'vgscan') if -e '/etc/lvmtab';

    require harddrake::autoconf;
    #- configure PCMCIA services if needed.
    harddrake::autoconf::pcmcia($o->{pcmcia});
    #- configure CPU frequency modules
    harddrake::autoconf::cpufreq();

    #- for mandrake_firstime
    touch "$::prefix/var/lock/TMP_1ST";

    fs::any::set_cdrom_symlink($o->{all_hds}{raw_hds});
    any::config_mtools($::prefix);

    #- make sure wins is disabled in /etc/nsswitch.conf
    #- else if eth0 is not existing, glibc segfaults.
    substInFile { s/\s*wins// if /^\s*hosts\s*:/ } "$::prefix/etc/nsswitch.conf";

    #- make sure some services have been enabled (or a catastrophic restart will occur).
    #- these are normally base package post install scripts or important services to start.
    run_program::rooted($::prefix, "chkconfig", "--add", $_) foreach
			qw(netfs network rawdevices sound kheader keytable syslog crond portmap);

    if ($o->{mouse}{device} =~ /ttyS/) {
	log::l("disabling gpm for serial mice (does not get along nicely with X)");
	run_program::rooted($::prefix, "chkconfig", "--del", "gpm"); 
    }

    #- install urpmi before as rpmdb will be opened, this will cause problem with update-menus.
    $o->install_urpmi;

    if ($o->{pcmcia}) {
	substInFile { s/.*(TaskBarShowAPMStatus).*/$1=1/ } "$::prefix/usr/lib/X11/icewm/preferences";
	eval { cp_af("$::prefix/usr/share/applnk/System/kapm.kdelnk",
		     "$::prefix/etc/skel/Desktop/Autostart/kapm.kdelnk") };
    }

    if ($o->{brltty}) {
	output("$::prefix/etc/brltty.conf", <<EOF);
braille-driver $o->{brltty}{driver}
braille-device $o->{brltty}{device}
text-table $o->{brltty}{table}
EOF
    }


    install::any::disable_user_view() if $o->{security} >= 3 || $o->{authentication}{NIS};
    run_program::rooted($::prefix, "kdeDesktopCleanup");

    #- move some file after an upgrade that may be seriously annoying.
    #- and rename saved files to .mdkgiorig.
    if ($o->{isUpgrade}) {
	my $pkg = install::pkgs::packageByName($o->{packages}, 'rpm');
	$pkg && ($pkg->flag_selected || $pkg->flag_installed) && $pkg->compare(">= 4.0") and install::pkgs::cleanOldRpmDb();

	log::l("moving previous desktop files that have been updated to Trash of each user");
	install::any::kdemove_desktop_file($::prefix);

	foreach (@filesToSaveForUpgrade) {
	    renamef("$::prefix/$_.mdkgisave", "$::prefix/$_.mdkgiorig")
	      if -e "$::prefix$_.mdkgisave";
	}

	foreach (@filesNewerToUseAfterUpgrade) {
	    if (-e "$::prefix/$_.rpmnew" && -e "$::prefix/$_") {
		renamef("$::prefix/$_", "$::prefix/$_.mdkgiorig");
		renamef("$::prefix/$_.rpmnew", "$::prefix/$_");
	    }
	}
    }

    renamef(install::pkgs::removed_pkgs_to_upgrade_file(), install::pkgs::removed_pkgs_to_upgrade_file() . '.done');
    unlink(glob("$::prefix/root/drakx/*.upgrading"));

    if ($o->{upgrade_by_removing_pkgs_matching}) {
	if (cat_("$::prefix/etc/inittab.rpmsave") =~ /^id:5:initdefault:\s*$/m) {
	    $o->{X}{xdm} = 1;
	    require Xconfig::various;
	    Xconfig::various::runlevel(5);
	}
    }

    any::fix_broken_alternatives($o->{isUpgrade} eq 'redhat');

    #- update theme directly from a package (simplest).
    if (-s "$::prefix/usr/share/oem-theme.rpm") {
	run_program::rooted($::prefix, "rpm", "-U", "/usr/share/oem-theme.rpm");
	unlink "/usr/share/oem-theme.rpm";
    }

    #- call update-menus at the end of package installation
    push @{$o->{waitpids}}, run_program::raw({ root => $::prefix, detach => 1 }, "update-menus", "-n");

    $o->install_hardware_packages;

    if ($o->{updatemodules}) {
	$o->updatemodules($ENV{THIRDPARTY_DEVICE}, $ENV{THIRDPARTY_DIR});
    }
}

sub install_urpmi {
    my ($o) = @_;

    my $pkg = install::pkgs::packageByName($o->{packages}, 'urpmi');
    if ($pkg && ($pkg->flag_selected || $pkg->flag_installed)
	#- this is a workaround. if many urpmi packages are found in the
	#- provides of all media, packages_providing() might return the wrong
	#- one. This probably needs to be fixed in URPM
	|| run_program::rooted_get_stdout($::prefix, '/bin/rpm', '-q', 'urpmi') =~ /urpmi/
    ) {
	install::media::install_urpmi($o->{method}, $o->{packages});
	install::pkgs::saveCompssUsers($o->{packages}, $o->{compssUsers});
    } else {
	log::l("skipping install_urpmi, urpmi not installed");
    }
}

sub install_hardware_packages {
    my ($o) = @_;
    if ($o->{match_all_hardware}) {
        my @l;

        require Xconfig::card;
        require Xconfig::proprietary;
        my $cards = Xconfig::card::readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");
        my @drivers = grep { $_ } uniq(map { $_->{Driver2} } values %$cards);
        push @l, map { Xconfig::proprietary::pkgs_for_Driver2($_, $o->do_pkgs) } @drivers;

        require network::connection;
        require network::thirdparty;
        foreach my $type (network::connection->get_types) {
            $type->can('get_thirdparty_settings') or next;
            foreach my $settings (@{$type->get_thirdparty_settings || []}) {
                foreach (@network::thirdparty::thirdparty_types) {
                    my @packages = network::thirdparty::get_required_packages($_, $settings);
                    push @l, network::thirdparty::get_available_packages($_, $o, @packages);
                }
            }
        }

        $o->do_pkgs->install(@l) if @l;
    }
}

sub updatemodules {
    my ($_o, $dev, $rel_dir) = @_;
    return if $::testing;

    $dev = devices::make($dev) or log::l("updatemodules: bad device $dev"), return;

    my $mount_dir = '/updatemodules';
    find {
	eval { fs::mount::mount($dev, $mount_dir, $_, 0); 1 };
    } 'ext2', 'vfat' or log::l("updatemodules: can't mount $dev"), return;

    my $dir = "$mount_dir$rel_dir";
    foreach my $kernel_version (all("$::prefix/lib/modules")) {
	log::l("examining updated modules for kernel $kernel_version");
	-d "$dir/$kernel_version" or next;
	log::l("found updatable modules");
	run_program::run("cd $dir/$kernel_version ; find -type f | cpio -pdu $::prefix/lib/modules/$kernel_version");
	run_program::rooted($::prefix, 'depmod', '-a', '-F', "/boot/System.map-$kernel_version", $kernel_version);
    }

    my $category;
    foreach (cat_("$dir/to_load")) {
	chomp;
	if (/^#/) {
	    ($category) = $1 if /\[list_modules: (.*?)\]/;
	} elsif ($category) {
	    log::l("adding $_ to $category\n");
	    my $r = \%list_modules::l;
	    $r = $r->{$_} foreach split('/', $category);
	    push @$r, $_;

	    $category = '';
	}
    }

    fs::mount::umount($mount_dir);
}

#------------------------------------------------------------------------------
sub selectMouse($) {
    my ($_o) = @_;
}

#------------------------------------------------------------------------------
sub configureNetwork {
    my ($o) = @_;
    require network::network;
    network::network::configure_network($o->{net}, $o, $o->{modules_conf});
    configure_firewall($o) if !$o->{isUpgrade};

    #- only a http proxy can be used by stage1
    #- the method is http even for ftp connections through a http proxy
    #- use this http proxy for both http and ftp connections
    if ($o->{method} eq "http" && $ENV{PROXY}) {
	my $proxy = "http://$ENV{PROXY}" . ($ENV{PROXYPORT} && ":$ENV{PROXYPORT}");
	add2hash($o->{miscellaneous} ||= {}, {
	    http_proxy => $proxy,
	    ftp_proxy => $proxy,
	});
	network::network::proxy_configure($o->{miscellaneous});
    }
}

sub configure_firewall {
    my ($o) = @_;

    #- set up a firewall if ports have been specified or if the security level is high enough
    $o->{firewall_ports} ||= '' if $o->{security} >= 3 && !exists $o->{firewall_ports};

    if (defined $o->{firewall_ports}) {
	require network::drakfirewall;
	$o->{firewall_ports} ||= ''; #- don't open any port by default
	network::drakfirewall::set_ports($o->do_pkgs, 0, $o->{firewall_ports}, 'log_net_drop');
	network::drakfirewall::set_ifw($o->do_pkgs, 1, [ 'psd' ], '');
    }
}

#------------------------------------------------------------------------------
sub installUpdates {
    my ($o) = @_;
    my $u = $o->{updates} or return; 
    $u->{url} or return;

    upNetwork($o);
    require mirror;

    # FIXME: install all update media
    my $phys_medium = install::media::url2mounted_phys_medium($o, $u->{url} . '/media/main/updates');

    my $update_medium = { name => "Updates for Mandriva Linux " . $o->{product_id}{version}, update => 1 };
    install::media::get_standalone_medium($o, $phys_medium, $o->{packages}, $update_medium);

    $o->pkg_install(@{$u->{packages} || []});

    #- re-install urpmi with update security medium.
    install_urpmi($o);
}

sub summaryBefore {}

sub summary {
    my ($o) = @_;
    configureTimezone($o);
}

sub summaryAfter {
    my ($_o) = @_;
}

#------------------------------------------------------------------------------
sub configureTimezone {
    my ($o) = @_;
    install::any::preConfigureTimezone($o);

    $o->pkg_install('ntp') if $o->{timezone}{ntp};

    require timezone;
    timezone::write($o->{timezone});
}

#------------------------------------------------------------------------------
sub configureServices {
    my ($o) = @_;
    if ($o->{services}) {
	require services;
	services::doit($o, $o->{services});
    }
}

#------------------------------------------------------------------------------
sub setRootPassword_addUser {
    my ($o) = @_;

    setRootPassword($o);
    addUser($o);
}

sub setRootPassword {
    my ($o) = @_;
    $o->{superuser} ||= {};
    require authentication;
    authentication::set_root_passwd($o->{superuser}, $o->{authentication});
    install::any::set_authentication($o);
}

sub addUser {
    my ($o) = @_;
    my $users = $o->{users} ||= [];

    if ($::prefix) {
	#- getpwnam, getgrnam, getgrid works
	symlinkf("$::prefix/etc/passwd", '/etc/passwd');
	symlinkf("$::prefix/etc/group", '/etc/group');
    }

    any::add_users($users, $o->{authentication});

    if ($o->{autologin}) {
	$o->{desktop} ||= first(any::sessions());
	$o->pkg_install("autologin") if !member($o->{desktop}, 'KDE', 'GNOME');
    }
    any::set_autologin($o->do_pkgs, $o->{autologin}, $o->{desktop});

    install::any::disable_user_view() if @$users == ();
}

#------------------------------------------------------------------------------
sub read_bootloader_config {
    my ($o) = @_;

    require bootloader;
    eval { add2hash($o->{bootloader} ||= {}, bootloader::read($o->{all_hds})) };
    $@ && $o->{isUpgrade} and log::l("read_bootloader_config failed: $@");

    $o->{bootloader}{bootUnsafe} = 0 if $o->{bootloader}{boot}; #- when upgrading, do not ask where to install the bootloader (mbr vs boot partition)
}

sub setupBootloaderBefore {
    my ($o) = @_;
    any::setupBootloaderBefore($o->do_pkgs, $o->{bootloader}, $o->{all_hds}, $o->{fstab}, $o->{keyboard},
                               $o->{allowFB}, $o->{vga}, $o->{meta_class} ne 'server');
}

sub setupBootloader {
    my ($o) = @_;

    any::install_acpi_pkgs($o->do_pkgs, $o->{bootloader});

    require bootloader;
    bootloader::install($o->{bootloader}, $o->{all_hds});
}

#------------------------------------------------------------------------------
sub configureXBefore {
    my ($o) = @_;

    #- keep this here if the package has to be updated.
    $o->pkg_install("task-x11");
}
sub configureX {
    my ($o) = @_;
    configureXBefore($o);

    require Xconfig::default;
    $o->{raw_X} = Xconfig::default::configure($o->do_pkgs, $o->{keyboard}, $o->{mouse});

    require Xconfig::main;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, $o->do_pkgs, $o->{X}, install::any::X_options_from_o($o));
    configureXAfter($o);
}
sub configureXAfter {
    my ($_o) = @_;
}

#------------------------------------------------------------------------------
sub miscellaneousBefore {
    my ($o) = @_;

    require security::level;
    require security::various;
    $o->{security} ||= security::level::get();
    $o->{security_user} ||= security::various::config_security_user($::prefix);
    $o->{libsafe} ||= security::various::config_libsafe($::prefix);

    log::l("security level is $o->{security}");
}
sub miscellaneous {
    my ($_o) = @_;
    #- keep some given parameters
    #-TODO
}
sub miscellaneousAfter {
    my ($o) = @_;

    $ENV{SECURE_LEVEL} = $o->{security}; #- deprecated with chkconfig 1.3.4-2mdk, uses /etc/sysconfig/msec

    addToBeDone {
	addVarsInSh("$::prefix/etc/sysconfig/system", { META_CLASS => $o->{meta_class} });

	eval { install::any::set_security($o) };

    } 'installPackages';
}

#------------------------------------------------------------------------------
sub exitInstall { 
    my ($o) = @_;

    install::any::deploy_server_notify($o) if exists $o->{deploy_server};

    #- mainly for auto_install's
    #- do not use run_program::xxx because it does not leave stdin/stdout unchanged
    system("bash", "-c", $o->{postInstallNonRooted}) if $o->{postInstallNonRooted};
    system("chroot", $::prefix, "bash", "-c", $o->{postInstall}) if $o->{postInstall};

    eval { 
	my $report = '/root/drakx/report.bug';
	unlink "$::prefix$report", "$::prefix$report.gz";
	output "$::prefix$report", install::any::report_bug();
	run_program::rooted($::prefix, 'gzip', $report);
    };
    eval { install::any::getAndSaveAutoInstallFloppies($o, 1) } if arch() !~ /^ppc/;
    eval { output "$::prefix/root/drakx/README", "This directory contains several installation-related files,
mostly log files (very useful if you ever report a bug!).

Beware that some Mandriva Linux tools rely on the contents of some
of these files... so remove any file from here at your own
risk!
" };
    #- wait for remaining processes.
    foreach (@{$o->{waitpids}}) {
	waitpid $_, 0;
	log::l("pid $_ returned $?");
    }
    install::media::umount_media($o->{packages});
    install::media::openCdromTray(install::media::first_medium($o->{packages})->{phys_medium}{device}) if !detect_devices::is_xbox() && $o->{method} eq 'cdrom';
    install::media::log_sizes();
}

#------------------------------------------------------------------------------
sub hasNetwork {
    my ($o) = @_;
    $o->{net}{type} && $o->{net}{network}{NETWORKING} ne 'no' and return 1;
    log::l("no network seems to be configured for internet ($o->{net}{type},$o->{net}{network}{NETWORKING})");
    0;
}

sub network_is_cheap {
    my ($o) = @_;
    member($o->{net}{type}, qw(adsl lan cable));
}

sub start_network_interface {
    my ($o) = @_;
    require network::tools;
    network::tools::start_net_interface($o->{net}, 0);
}

sub stop_network_interface {
    my ($o) = @_;
    require network::tools;
    network::tools::stop_net_interface($o->{net}, 0);
}

#------------------------------------------------------------------------------
sub upNetwork {
    my ($o, $b_pppAvoided) = @_;

    install::any::is_network_install($o) || $::local_install and return 1;
    $o->{modules_conf}->write;
    if (! -e "/etc/resolv.conf") {
        #- symlink resolv.conf in install root too so that updates and suppl media can be added
        symlink "$::prefix/etc/resolv.conf", "/etc/resolv.conf";
    }
    if (hasNetwork($o)) {
	if (network_is_cheap($o)) {
	    log::l("starting network ($o->{net}{type})");
	    start_network_interface($o);
	    return 1;
	} elsif (!$b_pppAvoided) {
	    log::l("starting network (ppp: $o->{net}{type})");
	    eval { modules::load(qw(serial ppp bsd_comp ppp_deflate)) };
	    run_program::rooted($::prefix, "/etc/rc.d/init.d/syslog", "start");
	    start_network_interface($o);
	    return 1;
	} else {
	    log::l(qq(not starting network (b/c ppp avoided and type is "$o->{net}{type})"));
	}
    }
    $::testing;
}

#------------------------------------------------------------------------------
sub downNetwork {
    my ($o, $costlyOnly) = @_;

    install::any::is_network_install($o) || $::local_install and return 1;
    $o->{modules_conf}->write;
    if (hasNetwork($o)) {
	if (!$costlyOnly) {
	    stop_network_interface($o);
	    return 1;
	} elsif (!network_is_cheap($o)) {
	    stop_network_interface($o);
	    run_program::rooted($::prefix, "/etc/rc.d/init.d/syslog", "stop");
	    eval { modules::unload(qw(ppp_deflate bsd_comp ppp serial)) };
	    return 1;
	}
    }
    $::testing;
}

#------------------------------------------------------------------------------
sub cleanIfFailedUpgrade($) {
    my ($o) = @_;

    #- if an upgrade has failed, there should be .mdkgisave files around.
    if ($o->{isUpgrade}) {
	foreach (@filesToSaveForUpgrade) {
	    if (-e "$::prefix/$_" && -e "$::prefix/$_.mdkgisave") {
		rename "$::prefix/$_", "$::prefix/$_.mdkginew"; #- keep new files around in case !
		rename "$::prefix/$_.mdkgisave", "$::prefix/$_";
	    }
	}
    }
}


1;
