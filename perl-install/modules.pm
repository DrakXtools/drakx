package modules; # $Id$

use strict;
use vars qw(%conf);

use common;
use detect_devices;
use run_program;
use log;
use list_modules;

%conf = ();

sub category2modules_and_description {
    my ($categories) = @_;
    my $f = '/lib/modules/' . c::kernel_version() . '/modules.description';
    -e $f or $f = '/lib/modules.description';
    my %modules_descriptions = map { /(\S+)\s+(.*)/ } cat_($f);
    map { $_ => $modules_descriptions{$_} } category2modules($categories);
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
	my ($name, @options) = ref $_ ? @$_ : $_;
	$options{$name} = \@options;
	dependencies_closure($name);
    } @_;

    @l = difference2([ uniq(@l) ], [ loaded_modules() ]) or return;

    my $network_module = do {
	my ($network_modules, $other) = partition { module2category($_) =~ m,network/(main|usb), } @l;
	if (@$network_modules > 1) {
	    # do it one by one
	    load($_) foreach @$network_modules;
	    load(@$other);
	    return;
	}
	$network_modules->[0];
    };
    my @network_devices = $network_module ? detect_devices::getNet() : ();

    if ($::testing || $::blank) {
	log::l("i would load module $_ (@{$options{$_}})") foreach @l;
    } elsif ($::isStandalone || $::live) {
	run_program::run('/sbin/modprobe', $_, @{$options{$_}}) 
	  or !run_program::run('/sbin/modprobe', '-n', $_) #- ignore missing modules
	  or die "insmod'ing module $_ failed" foreach @l;
    } else {
	load_raw(map { [ $_ => $options{$_} ] } @l);
    }
    sleep 2 if grep { /^(usb-storage|mousedev|printer)$/ } @l;

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
    my ($category, $wait_message, $probe_type) = @_;

    #- probe_category returns the PCMCIA cards. It doesn't know they are already
    #- loaded, so:
    read_already_loaded();

    my @try_modules = (
      if_($category =~ /scsi/,
	  if_(arch() !~ /ppc/, 'imm', 'ppa'),
	  if_(detect_devices::usbStorage(), 'usb-storage'),
      ),
      if_(arch() =~ /ppc/, 
	  if_($category =~ /scsi/, 'mesh', 'mac53c94'),
	  if_($category =~ /net/, 'bmac', 'gmac', 'mace'),
	  if_($category =~ /sound/, 'dmasound_awacs'),
      ),
    );
    grep {
	$wait_message->($_->{description}, $_->{driver}) if $wait_message;
	eval { load([ $_->{driver}, $_->{options} ]) };
	$_->{error} = $@;

	!($@ && $_->{try});
    } probe_category($category, $probe_type),
      map { { driver => $_, description => $_, try => 1 } } @try_modules;
}

sub probe_category {
    my ($category, $probe_type) = @_;

    my @modules = category2modules($category);

    grep {
	if ($category eq 'network/isdn') {
	    my $b = $_->{driver} =~ /ISDN:([^,]*),?([^,]*),?(.*)/;
	    if ($b) {
		$_->{driver} = $1;
		$_->{options} = $2;
		$_->{firmware} = $3;
		$_->{firmware} =~ s/firmware=//;
		$_->{driver} eq "hisax" and $_->{options} .= " id=HiSax";
	    }
	    $b;
	} else {
	    member($_->{driver}, @modules);
	}
    } detect_devices::probeall($probe_type);
}

sub load_ide {
    eval { load("ide-cd") }
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
    $conf{$name}{options} = $new_option;
}
sub add_alias { 
    my ($alias, $module) = @_;
    $module =~ /ignore/ and return;
    /\Q$alias/ && $conf{$_}{alias} && $conf{$_}{alias} eq $module and return $_ foreach keys %conf;
    log::l("adding alias $alias to $module");
    $conf{$alias}{alias} ||= $module;
    $conf{$module}{above} = 'snd-pcm-oss' if $module =~ /^snd-/;
    $alias;
}
sub add_probeall {
    my ($alias, $module) = @_;

    my $l = $conf{$alias}{probeall} ||= [];
    @$l = uniq(@$l, $module);
    log::l("setting probeall $alias to @$l");
}

sub remove_alias($) {
    my ($name) = @_;
    foreach (keys %conf) {
	$conf{$_}{alias} && $conf{$_}{alias} eq $name or next;
	delete $conf{$_}{alias};
	return 1;
    }
    0;
}

sub remove_module($) {
    my ($name) = @_;
    remove_alias($name);
    delete $conf{$name};
    0;
}

sub read_conf {
    my ($file) = @_;
    my %c;

    foreach (cat_($file)) {
	next if /^\s*#/;
	my ($type, $alias, $val) = split(/\s+/, chomp_($_), 3) or next;

	$val = [ split ' ', $val ] if $type eq 'probeall';

	$c{$alias}{$type} = $val;
    }
    #- cheating here: not handling aliases of aliases
    while (my ($k, $v) = each %c) {
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

    \%c;
}

sub mergein_conf {
    my ($file) = @_;
    my $modconfref = read_conf($file);
    while (my ($key, $value) = each %$modconfref) {
	$conf{$key}{alias} = $value->{alias} if !exists $conf{$key}{alias};
	$conf{$key}{options} = $value->{options} if $value->{options};
	push @{$conf{$key}{probeall} ||= []}, deref($value->{probeall});
    }
}

sub write_conf {
    my ($prefix) = @_;

    my $file = "$prefix/etc/modules.conf";
    rename "$prefix/etc/conf.modules", $file; #- make the switch to new name if needed

    #- Substitute new aliases in modules.conf (if config has changed)
    substInFile {
	my ($type,$alias,$module) = split(/\s+/, chomp_($_), 3);
	if ($type eq 'post-install' && $alias eq 'supermount') {	    
	    #- remove the post-install supermount stuff.
	    $_ = '';
	} elsif ($type eq 'alias' && $alias =~ /scsi_hostadapter|usb-interface/) {
	    #- remove old aliases which are replaced by probeall
	    $_ = '';
	} elsif (
	    $conf{$alias}{$type}  &&
	    $conf{$alias}{$type} ne $module)  {
	    my $v = join(' ', uniq(deref($conf{$alias}{$type})));
	    $_ = "$type $alias $v\n";
	}
    } $file;

    my $written = read_conf($file);

    local *F;
    open F, ">> $file" or die("cannot write module config file $file: $!\n");
    while (my ($mod, $h) = each %conf) {
	while (my ($type, $v) = each %$h) {
	    my $v2 = join(' ', uniq(deref($v)));
	    print F "$type $mod $v2\n" 
	      if $v2 && !$written->{$mod}{$type};
	}
    }
    my @l;
    push @l, 'scsi_hostadapter' if !is_empty_array_ref($conf{scsi_hostadapter}{probeall});
    push @l, 'bttv' if grep { $_->{driver} eq 'bttv' } detect_devices::probeall();
    append_to_etc_modules($prefix, @l);
}

sub append_to_etc_modules {
    my ($prefix, @l) = @_;
    my $l = join '|', map { '^\s*'.$_.'\s*$' } @l;
    log::l("to put in modules ", join(", ", @l));

    substInFile { 
	$_ = '' if $l && /$l/;
	$_ .= join '', map { "$_\n" } @l if eof;
    } "$prefix/etc/modules";
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

    if (c::kernel_version() =~ /^2\.2/) {
	my $msg = _("PCMCIA support no longer exists for 2.2 kernels. Please use a 2.4 kernel.");
	log::l($msg);
	return $msg;
    }

    log::l("i try to configure pcmcia services");

    symlink "/tmp/stage2/$_", $_ foreach "/etc/pcmcia";

    eval {
	load("pcmcia_core");
	load($pcic);
	load("ds");
    };

    #- run cardmgr in foreground while it is configuring the card.
    run_program::run("cardmgr", "-f", "-m" ,"/modules");
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
sub loaded_modules { 
    map { /(\S+)/ } cat_("/proc/modules");
}
sub read_already_loaded { 
    when_load($_) foreach reverse loaded_modules();
}

sub when_load {
    my ($name, @options) = @_;
    my $category = module2category($name);

    if ($category =~ m,disk/(scsi|hardware_raid|usb),) {
	add_probeall('scsi_hostadapter', $name);
	eval { load('sd_mod') };
    }
    load('snd-pcm-oss') if $name =~ /^snd-/;
    add_alias('sound-slot-0', $name) if $category =~ /sound/;
    add_alias('ieee1394-controller', $name) if member($name, 'ohci1394');
    add_probeall('usb-interface', $name) if $name =~ /usb-[uo]hci/ || $name eq 'ehci-hcd';

    $conf{$name}{options} = join " ", @options if @options;
}

sub cz_file { 
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
	$packer->extract_archive($dir, map { "$_.o" } @modules);
    };
}

sub load_raw {
    my @l = @_;

    extract_modules('/tmp', map { $_->[0] } @l);
    my @failed = grep {
	my $m = "/tmp/$_->[0].o";
	if (-e $m && run_program::run(["/usr/bin/insmod_", "insmod"], '2>', '/dev/tty5', $m, @{$_->[1]})) {
	    unlink $m;
	    '';
	} else {
	    log::l("missing module $_->[0]") if !-e $m;
	    -e $m;
	}
    } @l;

    die "insmod'ing module " . join(", ", map { $_->[0] } @failed) . " failed" if @failed;

    foreach (@l) {
	if ($_->[0] =~ /usb-[uo]hci/) {
	    eval {
		require fs; fs::mount('/proc/bus/usb', '/proc/bus/usb', 'usbdevfs');
		#- ensure keyboard is working, the kernel must do the job the BIOS was doing
		sleep 2;
		load("usbkbd", "keybdev") if detect_devices::usbKeyboards();
	    }
	}
    }
}

sub get_parameters {
    my %conf;
    foreach (split(' ', get_options($_[0]))) {
	   /(.*)=(.*)/;
	   $conf{$1} = $2;
    };
    %conf;
}


1;
