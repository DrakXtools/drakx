package harddrake::sound;
# lists filled with Danny Tholen help, enhanced by Thierry Vignaud
#
# No ALSA for OSS's 
#    o isa cards: msnd_pinnacle, pas2, 
#    o pci cards: ad1889, sam9407
# No OSS for ALSA's
#    o pci cards: snd-als4000, snd-es968, snd-hdsp
#    o isa cards: snd-azt2320, snd-cs4231, snd-cs4236, 
#      snd-dt0197h, snd-korg1212, snd-rme32
#    o pcmcia cards: snd-vxp440 snd-vxpocket

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
     if_(arch() =~ /ppc/, "snd-powermac" => [ "dmasound_pmac" ]),
     if_(arch() =~ /sparc/,
         "snd-sun-amd7930" => [ "unknown" ],
         "snd-sun-cs4231" => [ "unknown" ],
         "snd-sun-dbri" => [ "unknown" ],
        ),
     "snd-ad1816a" => [ "ad1816" ], # isa
     "snd-ad1848"  => [ "ad1848", "pss" ], # isa
     "snd-ad1889"  => [ "ad1889" ],
     "snd-ali5451" => [ "trident" ],
     "snd-als100"  => [ "sb" ], # isa
     "snd-als4000" => [ "unknown" ],
     "snd-atiixp"  => [ "unknown" ],
     "snd-au8810"  => [ "unknown" ],
     "snd-au8820"  => [ "unknown" ],
     "snd-au8830"  => [ "unknown" ],
     "snd-audigyls" => [ "unknown" ], # pci, renamed as snd-ca0106
     "snd-azt2320" => [ "unknown" ], # isa
     "snd-azt3328" => [ "unknown" ], # isa
     "snd-azx"     => [ "unknown" ],
     "snd-bt87x"   => [ "btaudio" ],
     "snd-ca0106"  => [ "unknown" ], # pci
     "snd-cmi8330" => [ "sb" ], # isa
     "snd-cmipci"  => [ "cmpci" ],
     "snd-cs4231"  => [ "unknown" ], # isa
     "snd-cs4232"  => [ "cs4232" ],  # isa
     "snd-cs4236"  => [ "ad1848" ], # isa
     "snd-cs4281"  => [ "cs4281" ],
     "snd-cs46xx"  => [ "cs46xx" ],
     "snd-darla20" => [ "unknown" ],
     "snd-darla24" => [ "unknown" ],
     "snd-dt0197h" => [ "unknown" ], # isa
     "snd-dt019x"  => [ "unknown" ], # isa
     "snd-emu10k1" => [ "audigy", "emu10k1" ],
     "snd-emu10k1x" => [ "unknown" ],
     "snd-ens1370" => [ "es1370" ],
     "snd-ens1371" => [ "es1371" ],
     "snd-es1688"  => [ "sb" ], # isa
     "snd-es18xx"  => [ "sb" ], # isa
     "snd-es1938"  => [ "esssolo1" ],
     "snd-es1968"  => [ "maestro" ], # isa
     "snd-es968"   => [ "sb" ],
     "snd-fm801"   => [ "forte" ],
     "snd-gina20"  => [ "unknown" ],
     "snd-gina24"  => [ "unknown" ],
     "snd-gina3g"  => [ "unknown" ],
     "snd-gusclassic" => [ "gus" ], # isa
     "snd-gusextreme" => [ "gus" ], # isa
     "snd-gusmax"  => [ "gus" ],    # isa
     "snd-hda-intel"    => [ "unknown" ],
     "snd-hdspm"   => [ "unknown" ],
     "snd-hdsp"    => [ "unknown" ],
     "snd-ice1712" => [ "unknown" ], # isa
     "snd-ice1724" => [ "unknown" ], # isa
     "snd-indi"    => [ "unknown" ], # pci
     "snd-indigo"  => [ "unknown" ], # pci
     "snd-indigodj" => [ "unknown" ], # pci
     "snd-indigoio" => [ "unknown" ], # pci
     "snd-intel8x0" => [ "ali5455", "i810_audio", "nvaudio" ],
     "snd-interwave" => [ "gus" ],  # isa
     "snd-interwave-stb" => [ "unknown" ], # isa
     "snd-korg1212" => [ "unknown" ], # isa
     "snd-layla20" => [ "unknown" ],
     "snd-layla24" => [ "unknown" ],
     "snd-layla3g" => [ "unknown" ],
     "snd-maestro3" => [ "maestro3" ],
     "snd-mia"     => [ "unknown" ],
     "snd-mixart"  => [ "unknown" ],
     "snd-mona"    => [ "unknown" ],
     "snd-mpu401"  => [ "mpu401" ],
     "snd-nm256"   => [ "nm256_audio" ],
     "snd-opl3sa2" => [ "opl3", "opl3sa", "opl3sa2" ], # isa
     "snd-opti92x-ad1848" => [ "unknown" ], # isa
     "snd-opti92x-cs4231" => [ "unknown" ], # isa
     "snd-opti93x" => [ "mad16" ],
     "snd-pcxhr"   => [ "unknown" ], # pci
     "snd-riptide"    => [ "unknown" ],
     "snd-rme32"   => [ "unknown" ], # isa
     "snd-rme96"   => [ "rme96xx" ], # pci
     "snd-rme9652" => [ "rme96xx" ], # pci
     "snd-sb16"    => ["sscape", "sb"],
     "snd-sb8"     => [ "sb" ],
     "snd-sbawe"   => [ "awe_wave" ],
     "snd-sgalaxy" => [ "sgalaxy" ], # isa
     "snd-sonicvibes" => [ "sonicvibes" ],
     "snd-sscape"  => [ "sscape" ], # isa
     "snd-trident" => [ "trident" ],
     "snd-usb-audio" => [ "audio" ], # usb
     "snd-via82xx"  => [ "via82cxxx_audio" ],
     "snd-vx222"   => [ "unknown" ],
     "snd-vxp440"  => [ "unknown" ], # pcmcia
     "snd-vxpocket" => [ "unknown" ], # pcmcia
     "snd-wavefront" => [ "wavefront" ], # isa
     "snd-ymfpci"  => [ "ymfpci" ],
     );


our %oss2alsa = 
    (
     if_(arch() =~ /ppc/, "dmasound_pmac" => [ "snd-powermac" ]),
     "ad1816"  => [ "snd-ad1816a" ],
     "ad1848"  => [ "snd-ad1848", "snd-cs4236" ],
     "ad1889"  => [ "snd-ad1889" ],
     "ali5455" => [ "snd-intel8x0" ],
     "audigy"  => [ "snd-emu10k1" ],
     "audio"   => [ "snd-usb-audio" ], # usb
     "awe_wave" => [ "snd-sbawe" ],
     "btaudio" => [ "snd-bt87x" ],
     "cmpci"   => [ "snd-cmipci" ],
     "cs4232"  => [ "snd-cs4232" ],
     "cs4281"  => [ "snd-cs4281" ],
     "cs46xx"  => [ "snd-cs46xx" ],
     "emu10k1" => [ "snd-emu10k1" ],
     "es1370"  => [ "snd-ens1370" ],
     "es1371"  => [ "snd-ens1371" ],
     "esssolo1" => [ "snd-es1938" ],
     "forte"   => [ "snd-fm801" ],
     "gus"     => ["snd-interwave", "snd-gusclassic", "snd-gusmax", "snd-gusextreme"],
     "i810_audio" => [ "snd-intel8x0" ],
     "ice1712" => [ "snd-ice1712" ],
     "mad16"   => [ "snd-opti93x" ],
     "maestro" => [ "snd-es1968" ],
     "maestro3" => [ "snd-maestro3" ],
     "mpu401"  => [ "snd-mpu401" ],
     "msnd_pinnacle" => [ "unknown" ],
     "nm256_audio" => [ "snd-nm256" ],
     "nvaudio" => [ "snd-intel8x0" ],
     "opl3"    => [ "snd-opl3sa2" ],
     "opl3sa"  => [ "snd-opl3sa2" ],
     "opl3sa2" => [ "snd-opl3sa2" ],
     "pas2"    => [ "unknown" ],
     "pss"     => [ "snd-ad1848" ],
     "rme96xx" => [ "snd-rme96", "snd-rme9652" ],
     "sam9407" => [ "unknown" ],
     "sb"      => [ "snd-als100", "snd-cmi8330", "snd-es1688", "snd-es18xx", "snd-es968", "snd-sb8", "snd-sb16" ],
     "sgalaxy" => [ "snd-sgalaxy" ],
     "sonicvibes" => [ "snd-sonicvibes" ],
     "sscape"  => [ "snd-sb16", "snd-sscape" ],
     "trident" => [ "snd-ali5451", "snd-trident" ],
     "via82cxxx_audio" => [ "snd-via82xx" ],
     "wavefront" => [ "snd-wavefront" ],
     "ymfpci"  => [ "snd-ymfpci" ],
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
        rooted("service alsa stop") if $old_driver =~ /^snd-/ && !$blacklisted;
        unload($old_driver);    # run_program("/sbin/modprobe -r $driver"); # just in case ...
    }
    $modules_conf->remove_module($old_driver);
    $modules_conf->set_sound_slot("sound-slot-$index", $new_driver);
    $modules_conf->write;
    if ($new_driver =~ /^snd-/) {   # new driver is an alsa one
        $in->do_pkgs->ensure_binary_is_installed('alsa-utils', 'alsactl');
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
    my @alternative = @{get_alternative($driver)};
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
				  N("\n\nYour card currently use the %s\"%s\" driver (default driver for your card is \"%s\")", ($driver =~ /^snd-/ ? "ALSA " : "OSS "), $driver, $device->{driver}),
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
                                    help => join("\n\n", map { qq("$_": ) . $des{$_} } @alternative),
                                    allow_empty_list => 1, 
                                    format => sub { my ($drv) = @_;
                                                    sprintf(($des{$drv} ? "$des{$drv} (%s [%s])"  : "%s [%s]"), $drv, $drv =~ /^snd[-_]/ ? 'ALSA' : 'OSS');
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

- \"grep sound-slot /etc/modules.conf\" will tell you what driver it
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


sub configure_sound_slots {
    my ($modules_conf) = @_;
    my $altered = 0;
    each_index {
        my $default_driver = $modules_conf->get_alias("sound-slot-$::i");
        if (!member($default_driver, @{get_alternative($_->{driver})}, $_->{driver})) {
            $altered ||= $default_driver;
            $modules_conf->set_sound_slot("sound-slot-$::i", $_->{driver});
	    $modules_conf->set_options($_->{driver}, "xbox=1") if $_->{driver} eq "snd-intel8x0" && detect_devices::is_xbox();
        }
    } detect_devices::getSoundDevices();
    $modules_conf->write if $altered && $::isStandalone;
}


1;
