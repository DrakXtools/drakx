package modules; # $Id$

use strict;

use common;
use detect_devices;
use run_program;
use log;
use list_modules;
use modules::any_conf;

sub modules_descriptions() {
    my $f = '/lib/modules/' . c::kernel_version() . '/modules.description';
    -e $f or $f = '/lib/modules.description';
    map { /(\S+)\s+(.*)/ } cat_($f);
}

sub module2description { +{ modules_descriptions() }->{$_[0]} }

sub category2modules_and_description {
    my ($categories) = @_;
    my %modules_descriptions = modules_descriptions();
    map { $_ => $modules_descriptions{$_} } category2modules($categories);
}

my %mappings_24_26 = (
    "usb-ohci" => "ohci-hcd",
    "usb-uhci" => "uhci-hcd",
    "uhci" => "uhci-hcd",
    "printer" => "usblp",
    "bcm4400" => "b44",
    "3c559" => "3c359",
    "3c90x" => "3c59x",
    "dc395x_trm" => "dc395x",
);
my %mappings_26_24 = reverse %mappings_24_26;
$mappings_26_24{'uhci-hcd'} = 'usb-uhci';

sub mapping_24_26 {
    my ($modname) = @_;
    $mappings_24_26{$modname} || $modname;
}
sub mapping_26_24 {
    my ($modname) = @_;
    $mappings_26_24{$modname} || $modname;
}

sub cond_mapping_24_26 {
    my ($modname) = @_;
    c::kernel_version() =~ /^\Q2.6/ && $mappings_24_26{$modname} || $modname;
}

#-###############################################################################
#- module loading
#-###############################################################################
# handles dependencies
sub load_raw {
    my ($l, $h_options) = @_;
    if ($::testing || $::local_install) {
	log::l("i would load module $_ ($h_options->{$_})") foreach @$l;
    } elsif ($::isInstall && !$::move) {
	load_raw_install($l, $h_options);
    } else {
	run_program::run('/sbin/modprobe', $_, split(' ', $h_options->{$_})) 
	  or !run_program::run('/sbin/modprobe', '-n', $_) #- ignore missing modules
	  or die "insmod'ing module $_ failed" foreach @$l;
    }
    sleep 2 if any { /^(usb-storage|mousedev|printer)$/ } @$l;
}
sub load_with_options {
    my ($l, $h_options) = @_;

    my @l = map {
	dependencies_closure(cond_mapping_24_26($_));
    } @$l;

    @l = remove_loaded_modules(@l) or return;

    load_raw(\@l, $h_options);
}
sub load {
    my (@l) = @_;
    load_with_options(\@l, {});
}

# eg: load_and_configure($modules_conf, 'vfat', 'reiserfs', [ ne2k => 'io=0xXXX', 'dma=5' ])
sub load_and_configure {
    my ($conf, $module, $o_options) = @_;

    my $category = module2category($module) || '';
    my $network_devices = $category =~ m!network/(main|gigabit|usb|wireless)! && [ detect_devices::getNet() ];

    my @l = remove_loaded_modules(dependencies_closure(cond_mapping_24_26($module)));
    load_raw(\@l, { $module => $o_options });

    if ($network_devices) {
	$conf->set_alias($_, $module) foreach difference2([ detect_devices::getNet() ], $network_devices);
    }

    if (c::kernel_version() =~ /^\Q2.6/ && member($module, 'imm', 'ppa') 
	&& ! -d "/proc/sys/dev/parport/parport0/devices/$module") {
	log::l("$module loaded but is not useful, removing");
	unload($module);
	return;
    }

    $conf->set_options($module, $o_options) if $o_options;

    when_load($conf, $module);
}

sub unload {
    if ($::testing) {
	log::l("rmmod $_") foreach @_;
    } else {
	run_program::run("rmmod", $_) foreach @_;
    }
}

sub load_category {
    my ($conf, $category, $o_wait_message) = @_;

    my @try_modules = (
      if_($category =~ /scsi/,
	  if_(detect_devices::usbStorage(), 'usb-storage'),
      ),
      arch() =~ /ppc/ ? (
	  if_($category =~ /scsi/,
	    if_(detect_devices::has_mesh(), 'mesh'),
	    if_(detect_devices::has_53c94(), 'mac53c94'),
	  ),
	  if_($category =~ /net/, 'bmac', 'gmac', 'mace', 'airport'),
      ) : (),
    );
    my @l = (
	(map {
	    my $other = { ahci => 'ata_piix', ata_piix => 'ahci' }->{$_->{driver}};
	    $_->{try} = 1 if $other;
	    ($_, if_($other, { %$_, driver => $other }));
	} probe_category($category)),
	(map { { driver => $_, description => $_, try => 1 } } @try_modules),
    );

    foreach (@l) {
	$o_wait_message->($_->{description}, $_->{driver}) if $o_wait_message;
	eval { load_and_configure($conf, $_->{driver}, $_->{options}) };
	$_->{error} = $@;

	$_->{try} = 1 if member($_->{driver}, 'hptraid', 'ohci1394'); #- do not warn when this fails
    }
    grep { !($_->{error} && $_->{try}) } @l;
}

sub load_parallel_zip {
    my ($conf) = @_;

    arch() !~ /ppc/ or return;

    eval { load('parport_pc') };
    grep { 
	eval { load_and_configure($conf, $_); 1 };
    } 'imm', 'ppa';
}

sub probe_category {
    my ($category) = @_;

    my @modules = category2modules($category);

    if_($category =~ /sound/ && arch() =~ /ppc/ && detect_devices::get_mac_model() !~ /IBM/,
	{ driver => 'snd-powermac', description => 'Macintosh built-in' },
    ),
    grep {
	if ($category eq 'network/isdn') {
	    my $b = $_->{driver} =~ /ISDN:([^,]*),?([^,]*)(?:,firmware=(.*))?/;
	    if ($b) {
                $_->{driver} = $1;
                $_->{type} = $2;
                $_->{type} =~ s/type=//;
                $_->{firmware} = $3;
                $_->{driver} eq "hisax" and $_->{options} .= " id=HiSax";
	    }
	    $b;
	} else {
	    member($_->{driver}, @modules);
	}
    } detect_devices::probeall();
}


#-###############################################################################
#- modules.conf functions
#-###############################################################################
sub write_preload_conf {
    my ($conf) = @_;
    my @l;
    push @l, 'scsi_hostadapter' if $conf->get_probeall('scsi_hostadapter');
    push @l, detect_devices::probe_name('Module');
    push @l, 'nvram' if detect_devices::isLaptop();
    push @l, map { $_->{driver} } probe_category($_) foreach qw(multimedia/dvb multimedia/tv various/laptop input/joystick various/crypto);
    push @l, 'padlock' if cat_("/proc/cpuinfo") =~ /rng_en/;
    push @l, 'evdev' if detect_devices::getSynapticsTouchpads();
    my @l_26 = @l;
    push @l_26, map { $_->{driver} } probe_category('various/agpgart');
    append_to_modules_loaded_at_startup("$::prefix/etc/modules", @l);
    append_to_modules_loaded_at_startup("$::prefix/etc/modprobe.preload", @l_26);
}

sub append_to_modules_loaded_at_startup_for_all_kernels {
    append_to_modules_loaded_at_startup($_, @_) foreach "$::prefix/etc/modules", "$::prefix/etc/modprobe.preload";
}

sub append_to_modules_loaded_at_startup {
    my ($file, @l) = @_;
    my $l = join '|', map { '^\s*' . $_ . '\s*$' } @l;
    log::l("to put in $file ", join(", ", @l));

    substInFile { 
	$_ = '' if $l && /$l/;
	$_ .= join '', map { "$_\n" } @l if eof;
    } $file;
}


#-###############################################################################
#- internal functions
#-###############################################################################
sub loaded_modules() { 
    map { /(\S+)/ } cat_("/proc/modules");
}
sub remove_loaded_modules {
    my (@l) = @_;
    difference2([ uniq(@l) ], [ map { my $s = $_; $s =~ s/_/-/g; $s, $_ } loaded_modules() ]);
}

sub read_already_loaded { 
    my ($conf) = @_;
    when_load($conf, $_) foreach reverse loaded_modules();
}

my $module_extension = c::kernel_version() =~ /^\Q2.4/ ? 'o' : 'ko';

sub name2file {
    my ($name) = @_;
    "$name.$module_extension";
}

sub when_load {
    my ($conf, $name) = @_;

    if (my $category = module2category($name)) {
	when_load_category($conf, $name, $category);
    }

    if (my $above = $conf->get_above($name)) {
	load($above); #- eg: for snd-pcm-oss set by set_sound_slot()
    }
}

sub when_load_category {
    my ($conf, $name, $category) = @_;

    if ($category =~ m,disk/(ide|scsi|hardware_raid|sata|usb|firewire),) {
	$conf->add_probeall('scsi_hostadapter', $name);
	eval { load('sd_mod') };
    } elsif ($category eq 'bus/usb') {
	$conf->add_probeall('usb-interface', $name);
        -f '/proc/bus/usb/devices' or eval {
            require fs::mount; fs::mount::usbfs('');
            #- ensure keyboard is working, the kernel must do the job the BIOS was doing
            sleep 4;
            load("usbkbd", "keybdev") if detect_devices::usbKeyboards();
        };
    } elsif ($category eq 'bus/firewire') {
	$conf->set_alias('ieee1394-controller', $name);
    } elsif ($category =~ /sound/) {
	my $sound_alias = find { /^sound-slot-[0-9]+$/ && $conf->get_alias($_) eq $name } $conf->modules;
	$sound_alias ||= 'sound-slot-0';
	$conf->set_sound_slot($sound_alias, $name);
    }
}

#-###############################################################################
#- isInstall functions
#-###############################################################################
sub cz_file() { 
    "/lib/modules" . (arch() eq 'sparc64' && "64") . ".cz-" . c::kernel_version();
}

sub extract_modules {
    my ($dir, @modules) = @_;
    my $cz = cz_file();
    if (!-e $cz && !$::local_install) {
	unlink $_ foreach glob_("/lib/modules*.cz*");
	require install_any;
        install_any::getAndSaveFile("install/stage2/live$cz", $cz) or die "failed to get modules $cz: $!";
    }
    eval {
	require packdrake;
	my $packer = new packdrake($cz, quiet => 1);
	$packer->extract_archive($dir, map { name2file($_) } @modules) if @modules;
	map { $dir . '/' . name2file($_) } @modules;
    };
}

sub load_raw_install {
    my ($l, $options) = @_;

    extract_modules('/tmp', @$l);
    my @failed = grep {
	my $m = '/tmp/' . name2file($_);
	if (-e $m) {
            my $stdout;
            my $rc = run_program::run(["insmod_", "insmod"], '2>', \$stdout, $m, split(' ', $options->{$_}));
            log::l(chomp_($stdout)) if $stdout;
            if ($rc) {
                unlink $m;
                '';
            } else {
		'error';
            }
	} else {
	    log::l("missing module $_");
	    'error';
	}
    } @$l;

    die "insmod'ing module " . join(", ", @failed) . " failed" if @failed;

}

1;
