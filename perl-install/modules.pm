package modules; # $Id$

use strict;
use vars qw(%conf %mappings_24_26 %mappings_26_24);

use common;
use detect_devices;
use run_program;
use log;
use list_modules;

%conf = ();

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

%mappings_24_26 = ("usb-ohci" => "ohci-hcd",
                   "usb-uhci" => "uhci-hcd",
                   "uhci" => "uhci-hcd",
                   "printer" => "usblp",
                   "bcm4400" => "b44",
                   "3c559" => "3c359",
                   "3c90x" => "3c59x",
                   "dc395x_trm" => "dc395x");
%mappings_26_24 = reverse %mappings_24_26;
sub mapping_24_26 {
    return map { c::kernel_version() =~ /^\Q2.6/ ? $mappings_24_26{$_} || $_ : $_ } @_;
}
sub mapping_26_24 {
    my ($modname) = @_;
    if (c::kernel_version() =~ /^\Q2.6/) {
        if ($modname eq 'uhci-hcd') {
            return 'usb-uhci';
        } else {
            return $mappings_26_24{$modname} || $modname;
        }
    }
    $modname;
}

#-###############################################################################
#- module loading
#-###############################################################################
# handles dependencies
# eg: load('vfat', 'reiserfs', [ ne2k => 'io=0xXXX', 'dma=5' ])
sub load {
    #- keeping the order of modules
    my %options;
    my @l = map {
	my ($name, @options) = ref($_) ? @$_ : $_;
	$options{$name} = \@options;
	dependencies_closure(mapping_24_26($name));
    } @_;

    @l = difference2([ uniq(@l) ], [ map { my $s = $_; $s =~ s/_/-/g; $s, $_ } loaded_modules() ]) or return;

    my $network_module = do {
	my ($network_modules, $other) = partition { module2category($_) =~ m,network/(main|gigabit|usb|wireless), } @l;
	if (@$network_modules > 1) {
	    # do it one by one
	    load($_) foreach @$network_modules;
	    load(@$other);
	    return;
	}
	$network_modules->[0];
    };
    my @network_devices = $network_module ? detect_devices::getNet() : ();

    if ($::testing) {
	log::l("i would load module $_ (" . join(" ", @{$options{$_}}) . ")") foreach @l;
    } elsif ($::isStandalone || $::move) {
	run_program::run('/sbin/modprobe', $_, @{$options{$_}}) 
	  or !run_program::run('/sbin/modprobe', '-n', $_) #- ignore missing modules
	  or die "insmod'ing module $_ failed" foreach @l;
    } else {
	load_raw(map { [ $_ => $options{$_} ] } @l);
    }
    sleep 2 if any { /^(usb-storage|mousedev|printer)$/ } @l;

    if ($network_module) {
	add_alias($_, $network_module) foreach difference2([ detect_devices::getNet() ], \@network_devices);
    }
    when_load($_, @{$options{$_}}) foreach @l;
}

sub unload {
    if ($::testing) {
	log::l("rmmod $_") foreach @_;
    } else {
	run_program::run("rmmod", $_) foreach @_;
    }
}

sub load_category {
    my ($category, $o_wait_message) = @_;

    #- probe_category returns the PCMCIA cards. It doesn't know they are already
    #- loaded, so:
    read_already_loaded();

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
	eval { load([ $_->{driver}, if_($_->{options}, $_->{options}) ]) };
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
sub get_alias {
    my ($alias) = @_;
    $conf{$alias}{alias};
}
sub get_probeall {
    my ($alias) = @_;
    $conf{$alias}{probeall};
}
sub get_options {
    my ($name) = @_;
    $conf{$name}{options};
}
sub set_options {
    my ($name, $new_option) = @_;
    log::l(qq(set option "$new_option" for module "$name"));
    $conf{$name}{options} = $new_option;
}
sub add_alias { 
    my ($alias, $module) = @_;
    $module =~ /ignore/ and return;
    /\Q$alias/ && $conf{$_}{alias} && $conf{$_}{alias} eq $module and return $_ foreach keys %conf;
    log::l("adding alias $alias to $module");
    $conf{$alias}{alias} = $module;
    $conf{$module}{above} = 'snd-pcm-oss' if $module =~ /^snd-/;
    $alias;
}
sub add_probeall {
    my ($alias, $module) = @_;

    my $l = $conf{$alias}{probeall} ||= [];
    @$l = uniq(@$l, $module);
    log::l("setting probeall $alias to @$l");
}
sub remove_probeall {
    my ($alias, $module) = @_;

    my $l = $conf{$alias}{probeall} ||= [];
    @$l = grep { $_ ne $module } @$l;
    log::l("setting probeall $alias to @$l");
}

sub remove_alias($) {
    my ($name) = @_;
    log::l(qq(removing alias "$name"));
    remove_alias_regexp("^$name\$");
}

sub remove_alias_regexp($) {
    my ($aliased) = @_;
    log::l(qq(removing all aliases that match "$aliased"));
    foreach (keys %conf) {
        delete $conf{$_}{alias} if /$aliased/;
    }
}

sub remove_alias_regexp_byname($) {
    my ($name) = @_;
    log::l(qq(removing all aliases which names match "$name"));
    foreach (keys %conf) {
        delete $conf{$_} if /$name/;
    }
}

sub remove_module($) {
    my ($name) = @_;
    remove_alias($name);
    log::l("removing module $name");
    delete $conf{$name};
    0;
}

sub read_conf {
    my ($file) = @_;
    my %c;

    foreach (cat_($file)) {
	next if /^\s*#/;
	s/#.*$//;
	my ($type, $alias, $val) = split(/\s+/, chomp_($_), 3) or next;
	$val =~ s/\s+$//;

	$val = [ split ' ', $val ] if $type eq 'probeall';

	$c{$alias}{$type} = $val;
    }
    #- cheating here: not handling aliases of aliases
    while (my ($_k, $v) = each %c) {
	if (my $a = $v->{alias}) {
	    local $c{$a}{alias};
	    delete $v->{probeall};
	    add2hash($c{$a}, $v);
	}
    }
    #- convert old aliases to new probeall
    foreach my $name ('scsi_hostadapter', 'usb-interface') {
	my @old_aliases = 
	  map { $_->[0] } sort { $a->[1] <=> $b->[1] } 
	  map { if_(/^$name(\d*)/ && $c{$_}{alias}, [ $_, $1 || 0 ]) } keys %c;
	foreach my $alias (@old_aliases) {
	    push @{$c{$name}{probeall} ||= []}, delete $c{$alias}{alias};
	}
    }
    # Convert alsa driver from old naming system to new one (snd-card-XXX => snd-XXX)
    # Ensure correct upgrade for snd-via683 and snd-via8233 drivers
    foreach my $alias (sort keys %c) {
        $c{$alias}{alias} =~ s/^snd-card/snd/;
        $c{$alias}{alias} = 'snd-via82xx' if $c{$alias}{alias} =~ /^snd-via686|^snd-via8233/;
    }

    \%c;
}

sub mergein_conf {
    my ($file) = @_;
    my $modconfref = read_conf($file);
    while (my ($key, $value) = each %$modconfref) {
	$conf{$key}{alias} ||= $value->{alias};
	$conf{$key}{options} = $value->{options} if $value->{options};
	push @{$conf{$key}{probeall} ||= []}, deref($value->{probeall});
    }
}

sub write_conf() {
    my $file = "$::prefix/etc/modules.conf";
    rename "$::prefix/etc/conf.modules", $file; #- make the switch to new name if needed

    #- Substitute new aliases in modules.conf (if config has changed)
    substInFile {
	my ($type, $alias, $module) = split(/\s+/, chomp_($_), 3);
	if ($type eq 'post-install' && $alias eq 'supermount') {	    
	    #- remove the post-install supermount stuff.
	    $_ = '';
	} elsif ($type eq 'alias' && $alias =~ /scsi_hostadapter|usb-interface/) {
	    #- remove old aliases which are replaced by probeall
	    $_ = '';
     } elsif ($type eq 'above') {
         # Convert alsa driver from old naming system to new one (snd-card-XXX => snd-XXX)
         # Ensure correct upgrade for snd-via683 and snd-via8233 drivers
         s/snd-card/snd/g;
         s/snd-via686|snd-via8233/snd-via82xx/g;
	} elsif ($conf{$alias}{$type} && $conf{$alias}{$type} ne $module) {
	    my $v = join(' ', uniq(deref($conf{$alias}{$type})));
	    $_ = "$type $alias $v\n";
	} elsif ($type eq 'alias' && !defined $conf{$alias}{alias}) { 
         $_ = '';
     }
    } $file;

    my $written = read_conf($file);

    open(my $F, ">> $file") or die("cannot write module config file $file: $!\n");
    while (my ($mod, $h) = each %conf) {
	while (my ($type, $v) = each %$h) {
	    my $v2 = join(' ', uniq(deref($v)));
	    print $F "$type $mod $v2\n" 
	      if $v2 && !$written->{$mod}{$type};
	}
    }
    my @l;
    push @l, 'scsi_hostadapter' if !is_empty_array_ref($conf{scsi_hostadapter}{probeall});
    push @l, grep { detect_devices::matching_driver('^$_$') } qw(bttv cx8800 saa7134);
    my @l_26 = @l;
    if (my ($agp) = probe_category('various/agpgart')) {
	push @l_26, $agp->{driver};
    }
    append_to_modules_loaded_at_startup("$::prefix/etc/modules", @l);
    append_to_modules_loaded_at_startup("$::prefix/etc/modprobe.preload", @l_26);
    #- use module-init-tools script for the moment
    run_program::rooted($::prefix, "/sbin/generate-modprobe.conf", ">", "/etc/modprobe.conf") if -e "$::prefix/etc/modprobe.conf";
}

sub append_to_modules_loaded_at_startup {
    my ($file, @l) = @_;
    my $l = join '|', map { '^\s*'.$_.'\s*$' } @l;
    log::l("to put in $file ", join(", ", @l));

    substInFile { 
	$_ = '' if $l && /$l/;
	$_ .= join '', map { "$_\n" } @l if eof;
    } $file;
}

sub read_stage1_conf {
    mergein_conf($_[0]);
}

#-###############################################################################
#- pcmcia various
#-###############################################################################
sub configure_pcmcia {
    my ($pcic) = @_;

    #- try to setup pcmcia if cardmgr is not running.
    my $running if 0;
    return if $running;
    $running = 1;

    log::l("i try to configure pcmcia services");

    symlink "/tmp/stage2/$_", $_ foreach "/etc/pcmcia";

    eval {
	load("pcmcia_core");
	load($pcic);
	load("ds");
    };

    #- run cardmgr in foreground while it is configuring the card.
    run_program::run("cardmgr", "-f", "-m", "/modules");
    sleep(3);
    
    #- make sure to be aware of loaded module by cardmgr.
    read_already_loaded();
}

sub write_pcmcia {
    my ($prefix, $pcmcia) = @_;

    #- should be set after installing the package above otherwise the file will be renamed.
    setVarsInSh("$prefix/etc/sysconfig/pcmcia", {
	PCMCIA    => bool2yesno($pcmcia),
	PCIC      => $pcmcia,
	PCIC_OPTS => "",
        CORE_OPTS => "",
    });
}


#-###############################################################################
#- internal functions
#-###############################################################################
sub loaded_modules() { 
    map { /(\S+)/ } cat_("/proc/modules");
}
sub read_already_loaded() { 
    when_load($_) foreach reverse loaded_modules();
}

my $module_extension = c::kernel_version() =~ /^\Q2.4/ ? 'o' : 'ko';

sub name2file {
    my ($name) = @_;
    "$name.$module_extension";
}

sub when_load {
    my ($name, @options) = @_;

    $name = mapping_26_24($name); #- need to stay with 2.4 names, modutils will allow booting 2.4 and 2.6

    if ($name =~ /[uo]hci/) {
        -f '/proc/bus/usb/devices' or eval {
            require fs; fs::mount('/proc/bus/usb', '/proc/bus/usb', 'usbdevfs');
            #- ensure keyboard is working, the kernel must do the job the BIOS was doing
            sleep 4;
            load("usbkbd", "keybdev") if detect_devices::usbKeyboards();
        }
    }

    load('snd-pcm-oss') if $name =~ /^snd-/;
    add_alias('ieee1394-controller', $name) if member($name, 'ohci1394');
    add_probeall('usb-interface', $name) if member($name, qw(usb-uhci usb-ohci ehci-hcd uhci-hcd ohci-hcd));

    $conf{$name}{options} = join " ", @options if @options;

    if (my $category = module2category($name)) {
	if (c::kernel_version() =~ /^\Q2.6/ && member($name, 'imm', 'ppa') 
	    && ! -d "/proc/sys/dev/parport/parport0/devices/$name") {
	    unload($name);
	    undef $category;
	}
	if ($category =~ m,disk/(scsi|hardware_raid|usb|firewire),) {
	    add_probeall('scsi_hostadapter', $name);
	    eval { load('sd_mod') };
	}
	add_alias('sound-slot-0', $name) if $category =~ /sound/;
    }
}

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

sub load_raw {
    my @l = @_;

    extract_modules('/tmp', map { $_->[0] } @l);
    my @failed = grep {
	my $m = '/tmp/' . name2file($_->[0]);
	if (-e $m) {
            my $stdout;
            my $rc = run_program::run(["/usr/bin/insmod_", "insmod"], '2>', \$stdout, $m, @{$_->[1]});
            log::l(chomp_($stdout)) if $stdout;
            if ($rc) {
                unlink $m;
                '';
            } else {
		'error';
            }
	} else {
	    log::l("missing module $_->[0]");
	    'error';
	}
    } @l;

    die "insmod'ing module " . join(", ", map { $_->[0] } @failed) . " failed" if @failed;

}

sub get_parameters {
    map { if_(/(.*)=(.*)/, $1 => $2) } split(' ', get_options($_[0]));
}


1;
