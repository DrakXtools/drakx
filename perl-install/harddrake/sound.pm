package harddrake::sound;
# lists filled with Danny Tholen help, enhanced by Thierry Vignaud
#
# No ALSA for OSS's 
#    o isa cards: msnd_pinnacle, pas2, 
#    o pci cards: ad1889, sam9407
# No OSS for ALSA's
#    o pci cards: snd_als4000, snd_es968, snd_hdsp
#    o isa cards: snd_azt2320, snd_cs4231, snd_cs4236, 
#      snd_dt0197h, snd_korg1212, snd_rme32
#    o pcmcia cards: snd_vxp440 snd_vxpocket

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


our %alsa2oss = 
    (
     if_(arch() =~ /ppc/, "snd_powermac" => [ "dmasound_pmac" ]),
     if_(arch() =~ /sparc/,
         "snd_sun_amd7930" => [ "unknown" ],
         "snd_sun_cs4231" => [ "unknown" ],
         "snd_sun_dbri" => [ "unknown" ],
        ),
     "snd_ad1816a" => [ "ad1816" ], # isa
     "snd_ad1848"  => [ "ad1848", "pss" ], # isa
     "snd_ad1889"  => [ "ad1889" ],
     "snd_ali5451" => [ "trident" ],
     "snd_als100"  => [ "sb" ], # isa
     "snd_als300"  => [ "unknown" ],
     "snd_als4000" => [ "unknown" ],
     "snd_aoa"     => [ "unknown" ],
     "snd_asihpi"  => [ "unknown" ],
     "snd_atiixp"  => [ "unknown" ],
     "snd_au8810"  => [ "unknown" ],
     "snd_au8820"  => [ "unknown" ],
     "snd_au8830"  => [ "unknown" ],
     "snd_audigyls" => [ "unknown" ], # pci, renamed as snd_ca0106
     "snd_azt2320" => [ "unknown" ], # isa
     "snd_azt3328" => [ "unknown" ], # isa
     "snd_azx"     => [ "unknown" ],
     "snd_bt87x"   => [ "btaudio" ],
     "snd_ca0106"  => [ "unknown" ], # pci
     "snd_cmi8330" => [ "sb" ], # isa
     "snd_cmi8788" => [ "unknown" ], # pci
     "snd_cmipci"  => [ "cmpci" ],
     "snd_cs4231"  => [ "unknown" ], # isa
     "snd_cs4232"  => [ "cs4232" ],  # isa
     "snd_cs4236"  => [ "ad1848" ], # isa
     "snd_cs4281"  => [ "cs4281" ],
     "snd_cs46xx"  => [ "cs46xx" ],
     "snd_cs5530"  => [ "unknown" ],
     "snd_cs5535audio" => [ "unknown" ],
     "snd_darla20" => [ "unknown" ],
     "snd_darla24" => [ "unknown" ],
     "snd_dt0197h" => [ "unknown" ], # isa
     "snd_dt019x"  => [ "unknown" ], # isa
     "snd_echo3g"  => [ "unknown" ],
     "snd_emu10k1" => [ "audigy", "emu10k1" ],
     "snd_emu10k1x" => [ "unknown" ],
     "snd_ens1370" => [ "es1370" ],
     "snd_ens1371" => [ "es1371" ],
     "snd_es1688"  => [ "sb" ], # isa
     "snd_es18xx"  => [ "sb" ], # isa
     "snd_es1938"  => [ "esssolo1" ],
     "snd_es1968"  => [ "maestro" ], # isa
     "snd_es968"   => [ "sb" ],
     "snd_fm801"   => [ "forte" ],
     "snd_gina20"  => [ "unknown" ],
     "snd_gina24"  => [ "unknown" ],
     "snd_gina3g"  => [ "unknown" ],
     "snd_gusclassic" => [ "gus" ], # isa
     "snd_gusextreme" => [ "gus" ], # isa
     "snd_gusmax"  => [ "gus" ],    # isa
     "snd_hda_intel"    => [ "unknown" ],
     "snd_hdspm"   => [ "unknown" ],
     "snd_hdsp"    => [ "unknown" ],
     "snd_ice1712" => [ "unknown" ], # isa
     "snd_ice1724" => [ "unknown" ], # isa
     "snd_indi"    => [ "unknown" ], # pci
     "snd_indigo"  => [ "unknown" ], # pci
     "snd_indigodj" => [ "unknown" ], # pci
     "snd_indigoio" => [ "unknown" ], # pci
     "snd_intel8x0" => [ "ali5455", "i810_audio", "nvaudio" ],
     "snd_interwave" => [ "gus" ],  # isa
     "snd_interwave_stb" => [ "unknown" ], # isa
     "snd_korg1212" => [ "unknown" ], # isa
     "snd_layla20" => [ "unknown" ],
     "snd_layla24" => [ "unknown" ],
     "snd_layla3g" => [ "unknown" ],
     "snd_maestro3" => [ "maestro3" ],
     "snd_mia"     => [ "unknown" ],
     "snd_mixart"  => [ "unknown" ],
     "snd_mona"    => [ "unknown" ],
     "snd_mpu401"  => [ "mpu401" ],
     "snd_nm256"   => [ "nm256_audio" ],
     "snd_opl3sa2" => [ "opl3", "opl3sa", "opl3sa2" ], # isa
     "snd_opti92x_ad1848" => [ "unknown" ], # isa
     "snd_opti92x_cs4231" => [ "unknown" ], # isa
     "snd_opti93x" => [ "mad16" ],
     "snd_pcxhr"   => [ "unknown" ], # pci
     "snd_riptide"    => [ "unknown" ],
     "snd_rme32"   => [ "unknown" ], # isa
     "snd_rme96"   => [ "rme96xx" ], # pci
     "snd_rme9652" => [ "rme96xx" ], # pci
     "snd_sb16"    => ["sscape", "sb"],
     "snd_sb8"     => [ "sb" ],
     "snd_sbawe"   => [ "awe_wave" ],
     "snd_sgalaxy" => [ "sgalaxy" ], # isa
     "snd_sonicvibes" => [ "sonicvibes" ],
     "snd_sscape"  => [ "sscape" ], # isa
     "snd_trident" => [ "trident" ],
     "snd_usb_audio" => [ "audio" ], # usb
     "snd_usb_caiaq"  => [ "unknown" ],
     "snd_usb_usx2y"  => [ "unknown" ],
     "snd_via82xx"  => [ "via82cxxx_audio" ],
     "snd_vx222"   => [ "unknown" ],
     "snd_vxp440"  => [ "unknown" ], # pcmcia
     "snd_vxpocket" => [ "unknown" ], # pcmcia
     "snd_wavefront" => [ "wavefront" ], # isa
     "snd_ymfpci"  => [ "ymfpci" ],
     );


our %oss2alsa = 
    (
     if_(arch() =~ /ppc/, "dmasound_pmac" => [ "snd_powermac" ]),
     "ad1816"  => [ "snd_ad1816a" ],
     "ad1848"  => [ "snd_ad1848", "snd_cs4236" ],
     "ad1889"  => [ "snd_ad1889" ],
     "ali5455" => [ "snd_intel8x0" ],
     "audigy"  => [ "snd_emu10k1" ],
     "audio"   => [ "snd_usb_audio" ], # usb
     "awe_wave" => [ "snd_sbawe" ],
     "btaudio" => [ "snd_bt87x" ],
     "cmpci"   => [ "snd_cmipci" ],
     "cs4232"  => [ "snd_cs4232" ],
     "cs4281"  => [ "snd_cs4281" ],
     "cs46xx"  => [ "snd_cs46xx" ],
     "emu10k1" => [ "snd_emu10k1" ],
     "es1370"  => [ "snd_ens1370" ],
     "es1371"  => [ "snd_ens1371" ],
     "esssolo1" => [ "snd_es1938" ],
     "forte"   => [ "snd_fm801" ],
     "gus"     => ["snd_interwave", "snd_gusclassic", "snd_gusmax", "snd_gusextreme"],
     "i810_audio" => [ "snd_intel8x0" ],
     "ice1712" => [ "snd_ice1712" ],
     "mad16"   => [ "snd_opti93x" ],
     "maestro" => [ "snd_es1968" ],
     "maestro3" => [ "snd_maestro3" ],
     "mpu401"  => [ "snd_mpu401" ],
     "msnd_pinnacle" => [ "unknown" ],
     "nm256_audio" => [ "snd_nm256" ],
     "nvaudio" => [ "snd_intel8x0" ],
     "opl3"    => [ "snd_opl3sa2" ],
     "opl3sa"  => [ "snd_opl3sa2" ],
     "opl3sa2" => [ "snd_opl3sa2" ],
     "pas2"    => [ "unknown" ],
     "pss"     => [ "snd_ad1848" ],
     "rme96xx" => [ "snd_rme96", "snd_rme9652" ],
     "sam9407" => [ "unknown" ],
     "sb"      => [ "snd_als100", "snd_cmi8330", "snd_es1688", "snd_es18xx", "snd_es968", "snd_sb8", "snd_sb16" ],
     "sgalaxy" => [ "snd_sgalaxy" ],
     "sonicvibes" => [ "snd_sonicvibes" ],
     "sscape"  => [ "snd_sb16", "snd_sscape" ],
     "trident" => [ "snd_ali5451", "snd_trident" ],
     "via82cxxx_audio" => [ "snd_via82xx" ],
     "wavefront" => [ "snd_wavefront" ],
     "ymfpci"  => [ "snd_ymfpci" ],
     );

my @blacklist = qw(cs46xx cs4281);
my $blacklisted = 0;

sub rooted { run_program::rooted($::prefix, @_) }

sub unload { modules::unload(@_) if $::isStandalone || $blacklisted }

sub load { 
    my ($modules_conf, $name) = @_;
    modules::load_and_configure($modules_conf, $name) if $::isStandalone || $blacklisted;
}

sub get_alternative {
    my ($driver) = @_;
    $alsa2oss{$driver} || $oss2alsa{$driver};
}

sub do_switch {
    my ($in, $modules_conf, $old_driver, $new_driver, $index) = @_;
    return if $old_driver eq $new_driver;
    my $_wait = $in->wait_message(N("Please wait"), N("Please Wait... Applying the configuration"));
    log::explanations("removing old $old_driver\n");
    if ($::isStandalone) {
        rooted("service sound stop") unless $blacklisted;
        rooted("service alsa stop") if $old_driver =~ /^snd_/ && !$blacklisted;
        unload($old_driver);    # run_program("/sbin/modprobe -r $driver"); # just in case ...
    }
    $modules_conf->remove_module($old_driver);
    configure_one_sound_slot($modules_conf, $index, $new_driver);
    $modules_conf->write;
    if ($new_driver =~ /^snd_/) {   # new driver is an alsa one
        $in->do_pkgs->ensure_binary_is_installed(qw(alsa-utils alsactl), 1);
        $in->do_pkgs->ensure_binary_is_installed(qw(aoss aoss), 1);
        rooted("service alsa start") if $::isStandalone && !$blacklisted;
        rooted("/sbin/chkconfig --add alsa")  if $::isStandalone;
        load($modules_conf, $new_driver) if $::isStandalone;   # service alsa is buggy
    } else { rooted("/sbin/chkconfig --del alsa") }
    log::explanations("loading new $new_driver\n");
    rooted("/sbin/chkconfig --add sound"); # just in case ...
    rooted("service sound start") if $::isStandalone && !$blacklisted;
}

sub switch {
    my ($in, $modules_conf, $device) = @_;
    my $driver = $device->{current_driver} || $device->{driver};

    foreach (@blacklist) { $blacklisted = 1 if $driver eq $_ }
    my @alternative = $driver ne 'unknown' ? @{get_alternative($driver)} : ();
    unless ($driver eq $device->{driver} || member($device->{driver}, @alternative)) {
	push @alternative, @{get_alternative($device->{driver})}, $device->{driver};
    }
    if (@alternative) {
        my $new_driver = $driver;
        push @alternative, $driver;
        my %des = modules::category2modules_and_description('multimedia/sound');

        if ($new_driver eq 'unknown') {
            $in->ask_from(N("No alternative driver"),
                          N("There's no known OSS/ALSA alternative driver for your sound card (%s) which currently uses \"%s\"",
                            $device->{description}, $driver),
                          [
                           get_any_driver_entry($in, $modules_conf, $driver, $device),
                          ]
                         );
        } elsif ($in->ask_from_({ title => N("Sound configuration"),
                                  messages => 
				  N("Here you can select an alternative driver (either OSS or ALSA) for your sound card (%s).",
				    $device->{description}) .
                          #-PO: here the first %s is either "OSS" or "ALSA", 
                          #-PO: the second %s is the name of the current driver
                          #-PO: and the third %s is the name of the default driver
				  N("\n\nYour card currently use the %s\"%s\" driver (default driver for your card is \"%s\")", ($driver =~ /^snd_/ ? "ALSA " : "OSS "), $driver, $device->{driver}),
				  interactive_help => sub {  
				      N("OSS (Open Sound System) was the first sound API. It's an OS independent sound API (it's available on most UNIX(tm) systems) but it's a very basic and limited API.
What's more, OSS drivers all reinvent the wheel.

ALSA (Advanced Linux Sound Architecture) is a modularized architecture which
supports quite a large range of ISA, USB and PCI cards.\n
It also provides a much higher API than OSS.\n
To use alsa, one can either use:
- the old compatibility OSS api
- the new ALSA api that provides many enhanced features but requires using the ALSA library.
");
                                        },
				},
                               [
                                { 
                                    label => N("Driver:"), val => \$new_driver, list => \@alternative, default => $new_driver, sort =>1,
                                    allow_empty_list => 1, 
                                    format => sub { my ($drv) = @_;
                                                    $drv eq 'unknown' ? $drv :
                                                      sprintf(($des{$drv} ? "$des{$drv} (%s [%s])"
                                                                : "%s [%s]"), $drv, $drv =~ /^snd_/ ? 'ALSA' : 'OSS');
                                                }
                                },
                                {
                                    val => N("Trouble shooting"), disabled => sub {},
                                    clicked => sub { &trouble($in) }
                                },
                                get_any_driver_entry($in, $modules_conf, $driver, $device),
                                ]))
        {
            return if $new_driver eq $device->{current_driver};
            log::explanations("switching audio driver from '" . $device->{current_driver} . "' to '$new_driver'\n");
            $in->ask_warn(N("Warning"), N("The old \"%s\" driver is blacklisted.\n
It has been reported to oops the kernel on unloading.\n
The new \"%s\" driver will only be used on next bootstrap.", $device->{current_driver}, $new_driver)) if $blacklisted;
            do_switch($in, $modules_conf, $device->{current_driver}, $new_driver, $device->{sound_slot_index});
            $device->{current_driver} = $new_driver;
        }
    } elsif ($driver =~ /^Bad:/) {
        $driver =~ s/^Bad://;
        $in->ask_warn(N("No open source driver"), 
                      N("There's no free driver for your sound card (%s), but there's a proprietary driver at \"%s\".",
                        $device->{description}, $driver));
    } elsif ($driver eq "unknown") {
        $in->ask_from(N("No known driver"), 
                      N("There's no known driver for your sound card (%s)",
                        $device->{description}),
                      [ get_any_driver_entry($in, $modules_conf, $driver, $device) ]);
    } else {
        $in->ask_warn(N("Unknown driver"), 
                      N("Error: The \"%s\" driver for your sound card is unlisted",
                      $driver));
    }
  end:
}

sub config {
    my ($in, $modules_conf, $device) = @_;
    switch($in, $modules_conf, $device);
}


sub trouble {
    my ($in) = @_;
    $in->ask_warn(N("Sound trouble shooting"),
                  formatAlaTeX(
                               #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                               N("The classic bug sound tester is to run the following commands:


- \"lspcidrake -v | fgrep AUDIO\" will tell you which driver your card uses
by default

- \"grep sound-slot /etc/modprobe.conf\" will tell you what driver it
currently uses

- \"/sbin/lsmod\" will enable you to check if its module (driver) is
loaded or not

- \"/sbin/chkconfig --list sound\" and \"/sbin/chkconfig --list alsa\" will
tell you if sound and alsa services're configured to be run on
initlevel 3

- \"aumix -q\" will tell you if the sound volume is muted or not

- \"/sbin/fuser -v /dev/dsp\" will tell which program uses the sound card.
")));
}

sub get_any_driver_entry {
    my ($in, $modules_conf, $driver, $device) = @_;
    return () if $::isInstall;
    +{
        val => N("Let me pick any driver"), disabled => sub {},
        clicked => sub {
            my $old_driver = $driver;
            if ($in->ask_from(N("Choosing an arbitrary driver"),
                              formatAlaTeX(
                                           #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
                                           N("If you really think that you know which driver is the right one for your card
you can pick one in the above list.

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
    $modules_conf->set_options('snd-ac97-codec', "power_save=1") if $driver =~ /^snd/ && detect_devices::isLaptop();
}

sub configure_sound_slots {
    my ($modules_conf) = @_;
    my $altered = 0;
    each_index {
        my $default_driver = $modules_conf->get_alias("sound-slot-$::i");
        if (!member($default_driver, @{get_alternative($_->{driver})}, $_->{driver})) {
            $altered ||= $default_driver;
            configure_one_sound_slot($modules_conf, $::i, $_->{driver});
        }
    } detect_devices::getSoundDevices();
    $modules_conf->write if $altered && $::isStandalone;
}


1;
