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


sub rooted { run_program::rooted($::prefix, @_) }

sub unload { modules::unload(@_) if $::isStandalone }

sub load { 
    my ($modules_conf, $name) = @_;
    modules::load_and_configure($modules_conf, $name) if $::isStandalone;
}

sub config {
    my ($in, $modules_conf, $device) = @_;
    my $driver = $device->{current_driver} || $device->{driver};

    my @alternative = $driver ne $device->{driver} ? $device->{driver} : ();
    if ($driver eq "unknown") {
        $in->ask_warn(N("No known driver"),
                      N("There's no known driver for your sound card (%s)",
                        $device->{description}));
    } else {
        push @alternative, $driver;
        my %des = modules::category2modules_and_description('multimedia/sound');
        
        my $is_pulseaudio_installed = -f $pa_startup_scriptfile && -d '/etc/sound/profiles/pulse';
        my $is_pulseaudio_enabled = is_pulseaudio_enabled();
        my $is_pulseaudio_glitchfree_enabled = is_pulseaudio_glitchfree_enabled();

        my $old_value = $is_pulseaudio_enabled;

        my $write_config = sub {
            return if !$is_pulseaudio_installed;
            set_pulseaudio($is_pulseaudio_enabled);
            set_pulseaudio_glitchfree($is_pulseaudio_glitchfree_enabled);
            if ($is_pulseaudio_enabled) {
                my $lib = get_libdir();
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
                val => N("Troubleshooting"), disabled => sub {},
                clicked => sub { &trouble($in) }
            },
        );

        if ($driver eq 'unknown') {
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
                                  interactive_help_id => 'soundConfig',
                                  messages => 
				    $device->{description} .
				  "\n\n" . N("Your card uses the \"%s\" driver", $driver),
				},
                               \@common,
                                ))
        {
            $write_config->();
        }
    }
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

sub configure_one_sound_slot {
    my ($modules_conf, $index, $driver) = @_;
    $modules_conf->set_sound_slot("sound-slot-$index", $driver);
    $modules_conf->set_options($driver, "xbox=1") if $driver eq "snd_intel8x0" && detect_devices::is_xbox();
    $modules_conf->set_options('snd-ac97-codec', "power_save=1") if $driver =~ /^snd/ && detect_devices::isLaptop();
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
