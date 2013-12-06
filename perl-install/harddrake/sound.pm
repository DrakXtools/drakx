package harddrake::sound;

# TODO: 
#    o ensure sound is not user (either dsp/midi/sequencer/mixer)
#    o fix sound/alsa services

use strict;
use common;
use run_program;
use modules;
use list_modules;
use detect_devices;
use log;

sub is_pulseaudio_enabled() {
    my $soundprofile = common::read_alternative('soundprofile');
    $soundprofile =~ /pulse$/;
}

sub set_pulseaudio {
    my ($val) = @_;

    my $alterative = '/etc/sound/profiles/' . ($val ? 'pulse' : 'alsa');
    return if ! -d $alterative;

    common::symlinkf_update_alternatives('soundprofile', $alterative);

    # (cg) This config file will eventually be dropped, but it is still needed for now
    # as several packages/patches depend on it.
    my $config_file = "$::prefix/etc/sysconfig/pulseaudio";
    $val = 'PULSE_SERVER_TYPE=' . ($val ? 'personal' : 'none') . "\n";
    my $done;
    substInFile {
        if (/^PULSE_SERVER_TYPE=/) {
            $_ = $val;
            $done = 1;
        }
    } $config_file;
    append_to_file($config_file, $val) if !$done;
}


my $pa_startup_scriptfile = "$::prefix/etc/pulse/default.pa";

sub is_pulseaudio_glitchfree_enabled() {
    return -f $pa_startup_scriptfile &&
      cat_($pa_startup_scriptfile) !~ /^load-module\s+module-(udev|hal)-detect\s+tsched=0/m;
}

sub set_pulseaudio_glitchfree {
    my ($val) = @_;

    return if ! -f $pa_startup_scriptfile;

    substInFile {
        if ($val) {
            s/^(load-module\s+module-(udev|hal)-detect)\s+tsched=0/$1/;
        } else {
            s/^(load-module\s+module-(udev|hal)-detect).*/$1 tsched=0/;
        }
    } $pa_startup_scriptfile;
}

my $pa_client_conffile = "$::prefix/etc/pulse/client.conf";

sub set_PA_autospan {
    my ($val) = @_;

    return if ! -f $pa_client_conffile;

    $val = 'autospawn = ' . bool2yesno($val) . "\n";
    my $done;
    substInFile {
        if (/^autospawn\s*=/) {
            $_ = $val;
            $done = 1;
        }
    } $pa_client_conffile;
    append_to_file($pa_client_conffile, $val) if !$done;
}


sub rooted { run_program::rooted($::prefix, @_) }

sub unload { modules::unload(@_) if $::isStandalone }

sub load { 
    my ($modules_conf, $name) = @_;
    modules::load_and_configure($modules_conf, $name) if $::isStandalone;
}

sub do_switch {
    my ($in, $modules_conf, $old_driver, $new_driver, $index) = @_;
    return if $old_driver eq $new_driver;
    my $_wait = $in->wait_message(N("Please wait"), N("Please Wait... Applying the configuration"));
    log::explanations("removing old $old_driver\n");
    if ($::isStandalone) {
        rooted("service sound stop");
        rooted("service alsa stop") if $old_driver =~ /^snd_/;
        unload($old_driver);    # run_program("/sbin/modprobe -r $driver"); # just in case ...
    }
    $modules_conf->remove_module($old_driver);
    configure_one_sound_slot($modules_conf, $index, $new_driver);
    $modules_conf->write;
    if ($new_driver =~ /^snd_/) {   # new driver is an alsa one
        $in->do_pkgs->ensure_binary_is_installed(qw(alsa-utils alsactl), 1);
        $in->do_pkgs->ensure_binary_is_installed(qw(aoss aoss), 1);
        rooted("service alsa start") if $::isStandalone;
        rooted("/sbin/chkconfig --add alsa")  if $::isStandalone;
        load($modules_conf, $new_driver) if $::isStandalone;   # service alsa is buggy
    } else { rooted("/sbin/chkconfig --del alsa") }
    log::explanations("loading new $new_driver\n");
    rooted("/sbin/chkconfig --add sound"); # just in case ...
    rooted("service sound start") if $::isStandalone;
}

sub config {
    my ($in, $modules_conf, $device) = @_;
    my $driver = $device->{current_driver} || $device->{driver};

    my @alternative = $driver ne $device->{driver} ? $device->{driver} : ();
    if ($driver eq "unknown") {
        $in->ask_from(N("No known driver"), 
                      N("There's no known driver for your sound card (%s)",
                        $device->{description}),
                      [ get_any_driver_entry($in, $modules_conf, $driver, $device) ]);
    } else {
        my $new_driver = $driver;
        push @alternative, $driver;
        my %des = modules::category2modules_and_description('multimedia/sound');
        
        my $is_pulseaudio_installed = (-f $pa_startup_scriptfile && -f $pa_client_conffile && -d '/etc/sound/profiles/pulse');
        my $is_pulseaudio_enabled = is_pulseaudio_enabled();
        my $is_pulseaudio_glitchfree_enabled = is_pulseaudio_glitchfree_enabled();

        my $old_value = $is_pulseaudio_enabled;

        my $write_config = sub {
            return if !$is_pulseaudio_installed;
            set_pulseaudio($is_pulseaudio_enabled);
            set_pulseaudio_glitchfree($is_pulseaudio_glitchfree_enabled);
            set_PA_autospan($is_pulseaudio_enabled);
            if ($is_pulseaudio_enabled) {
                my $lib = (arch() =~ /x86_64/ ? 'lib64' : 'lib');
                $in->do_pkgs->ensure_is_installed($lib . 'alsa-plugins-pulseaudio',
                                                    '/usr/' . $lib . '/alsa-lib/libasound_module_pcm_pulse.so');
            }
            if ($old_value ne $is_pulseaudio_enabled) {
                require any;
                any::ask_for_X_restart($in);
            }
        };

        my @common = (
            {
                text => N("Enable PulseAudio"),
                type => 'bool', val => \$is_pulseaudio_enabled,
                disabled => sub { !$is_pulseaudio_installed },
            },
            {
                text => N("Use Glitch-Free mode"),
                type => 'bool', val => \$is_pulseaudio_glitchfree_enabled,
                disabled => sub { !$is_pulseaudio_installed || !$is_pulseaudio_enabled },
            },
            {
                advanced => 1,
                val => N("Reset sound mixer to default values"),
                clicked => sub { run_program::run('reset_sound') }
            },
            {
                advanced => 1,
                val => N("Troubleshooting"), disabled => sub {},
                clicked => sub { &trouble($in) }
            },
        );

        if ($new_driver eq 'unknown') {
            if ($in->ask_from_({
                title => N("No alternative driver"),
                messages => N("There's no known OSS/ALSA alternative driver for your sound card (%s) which currently uses \"%s\"",
                              $device->{description}, $driver),
                          },
                          \@common,
                           )) {
                $write_config->();
            }
        } elsif ($in->ask_from_({ title => N("Sound configuration"),
                                  messages => 
				    $device->{description}.
                          #-PO: here the first %s is either "OSS" or "ALSA", 
                          #-PO: the second %s is the name of the current driver
                          #-PO: and the third %s is the name of the default driver
				  N("\n\nYour card currently uses the %s\"%s\" driver (the default driver for your card is \"%s\")", ($driver =~ /^snd_/ ? "ALSA " : "OSS "), $driver, $device->{driver}),
				  interactive_help => sub {  
				      N("OSS (Open Sound System) was the first sound API. It's an OS independent sound API (it's available on most UNIX(tm) systems) but it's a very basic and limited API.
What's more, OSS drivers all reinvent the wheel.

ALSA (Advanced Linux Sound Architecture) is a modularized architecture which
supports quite a large range of ISA, USB and PCI cards.\n
It also provides a much higher API than OSS.\n
To use alsa, one can either use:
- the old compatibility OSS API
- the new ALSA API that provides many enhanced features but requires using the ALSA library.
");
                                        },
				},
                               [
				if_(@alternative,
                                { 
                                    label => N("Driver:"), val => \$new_driver, list => \@alternative, default => $new_driver, sort =>1,
                                    format => sub { my ($drv) = @_;
                                                    $drv eq 'unknown' ? $drv :
                                                      sprintf(($des{$drv} ? "$des{$drv} (%s [%s])"
                                                                : "%s [%s]"), $drv, $drv =~ /^snd_/ ? 'ALSA' : 'OSS');
                                                }
                                }),
                                @common,
                                ]))
        {
            $write_config->();
            return if $new_driver eq $device->{current_driver};
            log::explanations("switching audio driver from '" . $device->{current_driver} . "' to '$new_driver'\n");
            do_switch($in, $modules_conf, $device->{current_driver}, $new_driver, $device->{sound_slot_index});
            $device->{current_driver} = $new_driver;
        }
    }
  end:
}

sub trouble {
    my ($in) = @_;
    $in->ask_warn(N("Sound troubleshooting"),
                  formatAlaTeX(
                               #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                               N("Below are some basic tips to help debug audio problems, but for accurate and up-to-date tips and tricks, please see:

https://wiki.mageia.org/en/Support:DebuggingSoundProblems



- General Recommendation: Enable PulseAudio. If you have opted to not to use PulseAudio, we would strongly advise you enable it. For the vast majority of desktop use cases, PulseAudio is the recommended and best supported option.



- \"kmix\" (KDE), \"gnome-control-center sound\" (GNOME) and \"pauvucontrol\" (generic) will launch graphical applications to allow you to view your sound devices and adjust volume levels


- \"ps aux | grep pulseaudio\" will check that PulseAudio is running.


- \"pactl stat\" will check that you can connect to the PulseAudio daemon correctly.


- \"pactl list sink-inputs\" will tell you which programs are currently playing sound via PulseAudio.


- \"systemctl status osspd.service\" will tell you the current state of the OSS Proxy Daemon. This is used to enable sound from legacy applications which use the OSS sound API. You should install the \"ossp\" package if you need this functionality.


- \"pacmd ls\" will give you a LOT of debug information about the current state of your audio.


- \"lspcidrake -v | grep -i audio\" will tell you which low-level driver your card uses by default.


- \"/usr/sbin/lsmod | grep snd\" will enable you to check which sound related kernel modules (drivers) are loaded.


- \"alsamixer -c 0\" will give you a text-based mixer to the low level ALSA mixer controls for first sound card


- \"/usr/sbin/fuser -v /dev/snd/pcm* /dev/dsp\" will tell which programs are currently using the sound card directly (normally this should only show PulseAudio)
")));
}

sub get_any_driver_entry {
    my ($in, $modules_conf, $driver, $device) = @_;
    return () if $::isInstall;
    +{
        advanced => 1,
        val => N("Let me pick any driver"), disabled => sub {},
        clicked => sub {
            my $old_driver = $driver;
            if ($in->ask_from(N("Choosing an arbitrary driver"),
                              formatAlaTeX(
                                           #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                                           N("If you really think that you know which driver is the right one for your card
you can pick one from the above list.

The current driver for your \"%s\" sound card is \"%s\" ", $device->{description}, $driver)),
                              [
                               { label => N("Driver:"), val => \$driver, list => [ category2modules("multimedia/sound") ], type => 'combo', default => $driver, sort =>1, separator => '|' },
                              ]
                             )) {
                do_switch($in, $modules_conf, $old_driver, $driver, $device->{sound_slot_index});
                goto end;
            }
        }
    };
}

sub configure_one_sound_slot {
    my ($modules_conf, $index, $driver) = @_;
    $modules_conf->set_sound_slot("sound-slot-$index", $driver);
    $modules_conf->set_options($driver, "xbox=1") if $driver eq "snd_intel8x0" && detect_devices::is_xbox();
    $modules_conf->set_options('snd-ac97-codec', "power_save=1") if $driver =~ /^snd/ && detect_devices::isLaptop()
      && arch() !~ /mips/;
}

sub configure_sound_slots {
    my ($modules_conf) = @_;
    my $altered = 0;
    each_index {
        my $default_driver = $modules_conf->get_alias("sound-slot-$::i");
        if (!member($default_driver, $_->{driver})) {
            $altered ||= $default_driver;
            configure_one_sound_slot($modules_conf, $::i, $_->{driver});
        }
    } detect_devices::getSoundDevices();
    $modules_conf->write if $altered && $::isStandalone;
}


1;
