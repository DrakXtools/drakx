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
    c::kernel_version() =~ /^\Q2.6/ && $mappings_24_26{$modname} || $modname;
}
sub mapping_26_24 {
    my ($modname) = @_;
    c::kernel_version() =~ /^\Q2.6/ && $mappings_26_24{$modname} || $modname;
}

#-###############################################################################
#- module loading
#-###############################################################################
# handles dependencies
sub load_raw {
    my ($l, $h_options) = @_;
    if ($::testing) {
	log::l("i would load module $_ ($h_options->{$_})") foreach @$l;
    } elsif ($::isStandalone || $::move) {
	run_program::run('/sbin/modprobe', $_, split(' ', $h_options->{$_})) 
	  or !run_program::run('/sbin/modprobe', '-n', $_) #- ignore missing modules
	  or die "insmod'ing module $_ failed" foreach @$l;
    } else {
	load_raw_install($l, $h_options);
    }
    sleep 2 if any { /^(usb-storage|mousedev|printer)$/ } @$l;
}
sub load {
    my (@l) = @_;
    @l = map {
	dependencies_closure(mapping_24_26($_));
    } @l;

    @l = remove_loaded_modules(@l) or return;

    load_raw(\@l, {});
}

# eg: load_and_configure($modules_conf, 'vfat', 'reiserfs', [ ne2k => 'io=0xXXX', 'dma=5' ])
sub load_and_configure {
    my ($conf, $module, $o_options) = @_;

    my $category = module2category($module) || '';
    my $network_devices = $category =~ m!network/(main|gigabit|usb|wireless)! && [ detect_devices::getNet() ];

    my @l = remove_loaded_modules(dependencies_closure(mapping_24_26($module))) or return;
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
	  if_(arch() !~ /ppc/, 'parport_pc', 'imm', 'ppa'),
	  if_(detect_devices::usbStorage(), 'usb-storage'),
      ),
      if_(arch() =~ /ppc/, 
	  if_($category =~ /scsi/, 'mesh', 'mac53c94'),
	  if_($category =~ /net/, 'bmac', 'gmac', 'mace', 'airport'),
	  if_($category =~ /sound/, 'dmasound_pmac'),
      ),
    );
    grep {
	$o_wait_message->($_->{description}, $_->{driver}) if $o_wait_message;
	eval { load_and_configure($conf, $_->{driver}, $_->{options}) };
	$_->{error} = $@;

	$_->{try} = 1 if member($_->{driver}, 'hptraid', 'ohci1394'); #- don't warn when this fails

	!($_->{error} && $_->{try});
    } probe_category($category),
      map { { driver => $_, description => $_, try => 1 } } @try_modules;
}

sub probe_category {
    my ($category) = @_;

    my @modules = category2modules($category);

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
    push @l, intersection([ qw(bttv cx8800 saa7134) ],
			  [ map { $_->{driver} } detect_devices::probeall() ]);
    my @l_26 = @l;
    if (my ($agp) = probe_category('various/agpgart')) {
	push @l_26, $agp->{driver};
    }
    append_to_modules_loaded_at_startup("$::prefix/etc/modules", @l);
    append_to_modules_loaded_at_startup("$::prefix/etc/modprobe.preload", @l_26);
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
    difference2([ uniq(@l) ], [ map { my $s = $_; $s =~ s/_/-/g; $s, $_ } loaded_modules() ])
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

    $name = mapping_26_24($name); #- need to stay with 2.4 names, modutils will allow booting 2.4 and 2.6

    if (my $category = module2category($name)) {
	when_load_category($conf, $name, $category);
    }

    if (my $above = $conf->get_above($name)) {
	load($above); #- eg: for snd-pcm-oss set by set_sound_slot()
    }
}

sub when_load_category {
    my ($conf, $name, $category) = @_;

    if ($category =~ m,disk/(scsi|hardware_raid|usb|firewire),) {
	$conf->add_probeall('scsi_hostadapter', $name);
	eval { load('sd_mod') };
    } elsif ($category eq 'bus/usb') {
	$conf->add_probeall('usb-interface', $name);
        -f '/proc/bus/usb/devices' or eval {
            require fs; fs::mount('/proc/bus/usb', '/proc/bus/usb', 'usbdevfs');
            #- ensure keyboard is working, the kernel must do the job the BIOS was doing
            sleep 4;
            load("usbkbd", "keybdev") if detect_devices::usbKeyboards();
        }
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
    if (!-e $cz) {
	unlink $_ foreach glob_("/lib/modules*.cz*");
	require install_any;
        install_any::getAndSaveFile("Mandrake/mdkinst$cz", $cz) or die "failed to get modules $cz: $!";
    }
    eval {
	require packdrake;
	my $packer = new packdrake($cz, quiet => 1);
	$packer->extract_archive($dir, map { name2file($_) } @modules);
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
            my $rc = run_program::run(["/usr/bin/insmod_", "insmod"], '2>', \$stdout, $m, split(' ', $options->{$_}));
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
