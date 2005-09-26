package move; # $Id$

#- Copyright (c) 2004-2005 Mandriva
#-
#- This program is free software; you can redistribute it and/or modify
#- it under the terms of the GNU General Public License as published by
#- the Free Software Foundation; either version 2, or (at your option)
#- any later version.
#-
#- This program is distributed in the hope that it will be useful,
#- but WITHOUT ANY WARRANTY; without even the implied warranty of
#- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#- GNU General Public License for more details.
#-
#- You should have received a copy of the GNU General Public License
#- along with this program; if not, write to the Free Software
#- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

use diagnostics;
use strict;

use c;
use common;
use modules;
use fs;
use fsedit;
use run_program;
use partition_table qw(:types);
use log;
use lang;
use detect_devices;

sub symlinkf_short {
    my ($dest, $file) = @_;
    if (my $l = readlink $dest) {
	$dest = $l if $l =~ m!^/!;
    }
    -d $file and log::l("$file already exists and is a directory! writing in directory may be needed, not overwriting"), return;
    symlinkf($dest, $file);
}

#- run very soon at stage2 start, setup things on tmpfs rw / that
#- were not necessary to start stage2 itself (there were setup
#- by stage1 of course)
sub init {
    my ($o) = @_;

    check_for_xserver() and c::bind_textdomain_codeset('libDrakX2', 'UTF8');


    -d '/lib/modules/' . c::kernel_version() or warn("ERROR: kernel package " . c::kernel_version() . " not installed\n"), c::_exit(1);

    modules::load_category('bus/usb'); 
    *c::pcmcia_probe = \&detect_devices::pcmcia_probe;
    $o->{pcmcia} ||= !$::noauto && c::pcmcia_probe();
    install_steps::setupSCSI($o);

drakx_stuff:
    $o->{steps}{$_} = { reachable => 1, text => $_ }
      foreach qw(autoSelectLanguage configMove selectMouse setRootPassword addUser configureNetwork miscellaneous selectMouse);
    $o->{orderedSteps_orig} = $o->{orderedSteps};
    $o->{orderedSteps} = [ qw(selectLanguage acceptLicense selectMouse setupSCSI miscellaneous selectKeyboard setRootPassword addUser configureNetwork configMove ) ];
    $o->{steps}{first} = $o->{orderedSteps}[0];
}

    


sub enable_service {
    run_program::run('/sbin/chkconfig', '--level', 5, $_[0], 'on');
}

sub disable_service {
    run_program::run('/sbin/chkconfig', '--del', $_[0], 'on');
}

sub install2::configMove {
    my $o = $::o;

    security::level::set($o->{security});

    require install_steps;
    install_steps::addUser($o); # for test, when replaying wizard on an already configured machine
    while ($#{$o->{users}} eq -1) {
        install_steps::addUser($o);
    }

    $::noauto and goto after_autoconf;

    my $_wait = $o->wait_message(N("Auto configuration"), N("Please wait, detecting and configuring devices..."));

    #- automatic printer, timezone, network configs
    require install_steps_interactive;
    if (cat_('/proc/mounts') !~ /nfs/) {
        install_steps_interactive::configureNetwork($o);
        enable_service('network');
    }
    enable_service('netfs');
    install_steps_interactive::summaryBefore($o);

    modules::load_category('multimedia/sound');
    enable_service('sound');

    detect_devices::isLaptop() or enable_service('numlock');

after_autoconf:
    require timezone;
    timezone::write($o->{timezone});

    $o->{useSupermount} = 1;
    fs::set_removable_mntpoints($o->{all_hds});    
    require fs::mount_options;
    fs::mount_options::set_all_default($o->{all_hds}, %$o, lang::fs_options($o->{locale}));

    $o->{modules_conf}->write;
    require mouse;
    mouse::write_conf($o, $o->{mouse}, 1);  #- write xfree mouse conf
    detect_devices::install_addons('');

    foreach my $step (@{$o->{orderedSteps_orig}}) {
        next if member($step, @{$o->{orderedSteps}});
        while (my $f = shift @{$o->{steps}{$step}{toBeDone} || []}) {
            log::l("doing remaining toBeDone for undone step $step");
            eval { &$f() };
            $o->ask_warn(N("Error"), [
N("An error occurred, but I don't know how to handle it nicely.
Continue at your own risk."). formatError($@) || $@ ]) if $@;
        }
    }
    run_program::run('killall', 'Xorg');
    output_p("$::prefix/etc/rpm/macros", "%_install_langs all\n");
    # workaround init reading inittab before any.pm alters it:
    if ($::o->{autologin}) {
        run_program::run('chkconfig', 'dm', 'on');
        run_program::run('telinit', 'Q');
    }
    # prevent dm service to fail to startup because of /tmp/.font-unix's permissions:
    run_program::run('service', 'xfs', 'stop');
    c::_exit(0);
}



sub automatic_xconf {
    my ($o) = @_;

    log::l('automatic XFree configuration');
    
    any::devfssymlinkf($o->{mouse}, 'mouse');
    local $o->{mouse}{device} = 'mouse';
    
    require Xconfig::default;
    require class_discard;
    $o->{raw_X} = Xconfig::default::configure(class_discard->new, { KEYBOARD => 'uk' }, $o->{mouse}); #- using uk instead of us for now to have less warnings
    
    require Xconfig::main;
    Xconfig::main::configure_everything_auto_install($o->{raw_X}, class_discard->new, {},
                                                     { allowNVIDIA_rpms => sub { [] }, allowATI_rpms => sub { [] }, allowFB => $o->{allowFB} });

    modules::load_category('various/agpgart'); 

    my $file = '/etc/X11/XF86Config';
    $file = "$file-4" if -e "$file-4";
    my ($Driver) = cat_($file) =~ /Section "Device".*Driver\s*"(.*?)"/s;
    if ($Driver eq 'nvidia') {
        modules::load('nvidia');
    }
    my $lib = 'libGL.so.1';
    symlinkf_short(-e "/usr/lib/$lib.$Driver" ? "/usr/lib/$lib.$Driver" : "/usr/X11R6/lib/$lib", "/etc/X11/$lib");
}

sub handleI18NClp {}


1;
