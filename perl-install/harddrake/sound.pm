package harddrake::sound;
# lists filled with Danny Tholen help, enhanced by Thierry Vignaud
#
# No ALSA for OSS's 
#    o tv cards: btaudio,
#    o isa cards: msnd_pinnacle, pas2, 
#    o pci cards: ad1889, sam9407
# No OSS for ALSA's
#    o pci cards: snd-als4000, snd-es968, snd-hdsp
#    o isa cards: snd-azt2320, snd-cs4231, snd-cs4236, 
#      snd-dt0197h, snd-korg1212, snd-rme32

# TODO: 
#    o ensure sound isn't user (either dsp/midi/sequencer/mixer)
#    o fix sound/alsa services

use strict;
use common;
use interactive;
use run_program;
use modules;
use list_modules;
use detect_devices;
use log;

my $has_nvaudio = -x '/lib/modules/' . c::kernel_version() . '/';

our %alsa2oss = 
    (
     "snd-ad1816a" => [ "ad1816" ], # isa
     "snd-ad1848"  => [ "ad1848", "pss" ], # isa
     "snd-ali5451" => [ "trident" ],
     "snd-als100"  => [ "sb" ], # isa
     "snd-als4000" => [ "unknown" ],
     "snd-azt2320" => [ "unknown" ], # isa
     "snd-azt3328" => [ "unknown" ], # isa
     "snd-cmi8330" => [ "sb" ], # isa
     "snd-cmipci"  => [ "cmpci" ],
     "snd-cs4231"  => [ "unknown" ], # isa
     "snd-cs4232"  => [ "cs4232" ],  # isa
     "snd-cs4236"  => [ "ad1848" ], # isa
     "snd-cs4281"  => [ "cs4281" ],
     "snd-cs46xx"  => [ "cs46xx" ],
     "snd-dt0197h" => [ "unknown" ], # isa
     "snd-emu10k1" => [ "audigy", "emu10k1" ],
     "snd-ens1370" => [ "es1370" ],
     "snd-ens1371" => [ "es1371" ],
     "snd-es1688"  => [ "sb" ], # isa
     "snd-es18xx"  => [ "sb" ], # isa
     "snd-es1938"  => [ "esssolo1" ],
     "snd-es1968"  => [ "maestro" ], # isa
     "snd-es968"   => [ "sb" ],
     "snd-fm801"   => [ "forte" ],
     "snd-gusclassic" => [ "gus" ], # isa
     "snd-gusextreme" => [ "gus" ], # isa
     "snd-gusmax"  => [ "gus" ],    # isa
     "snd-hdsp" => [ "unknown" ],
     "snd-ice1712" => [ "ice1712" ], # isa
     "snd-intel8x0" => [ "ali5455", "i810_audio", "nvaudio" ],
     "snd-interwave" => [ "gus" ],  # isa
     "snd-korg1212" => [ "unknown" ], # isa
     "snd-maestro3" => [ "maestro3" ],
     "snd-mpu401"  => [ "mpu401" ],
     "snd-nm256"   => [ "nm256_audio" ],
     "snd-opl3sa2" => [ "opl3", "opl3sa", "opl3sa2" ], # isa
     "snd-opti93x" => [ "mad16" ],
     "snd-rme32"   => [ "unknown" ], # isa
     "snd-rme96"   => [ "rme96xx" ], # pci
     "snd-rme9652" => [ "rme96xx" ], # pci
     "snd-sb16"    => ["sscape", "sb"],
     "snd-sb8"     => [ "sb" ],
     "snd-sbawe"   => [ "awe_wave" ],
     "snd-sgalaxy" => [ "sgalaxy" ], # isa
     "snd-sonicvibes" => [ "sonicvibes" ],
     "snd-trident" => [ "trident" ],
     "snd-usb-audio" => [ "audio" ], # usb
     "snd-via82xx"  => [ "via82cxxx_audio" ],
     "snd-wavefront" => [ "wavefront" ], # isa
     "snd-ymfpci"  => [ "ymfpci" ]
     );


our %oss2alsa = 
    (
     "ad1816"  => [ "snd-ad1816a" ],
     "ad1848"  => [ "snd-ad1848", "snd-cs4236" ],
     "ad1889"  => [ "unknown" ],
     "ali5455" => [ "snd-intel8x0" ],
     "audigy"  => [ "snd-emu10k1" ],
     "audio" => [ "snd-usb-audio" ], # usb
     "awe_wave" => [ "snd-sbawe" ],
     "btaudio" => [ "unknown" ],
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
     "pss" => [ "snd-ad1848" ],
     "rme96xx" => [ "snd-rme96", "snd-rme9652" ],
     "sam9407" => [ "unknown" ],
     "sb"      => [ "snd-als100", "snd-cmi8330", "snd-es1688", "snd-es18xx", "snd-es968", "snd-sb8", "snd-sb16" ],
     "sgalaxy" => [ "snd-sgalaxy" ],
     "sonicvibes" => [ "snd-sonicvibes" ],
     "sscape"  => [ "snd-sb16" ],
     "trident" => [ "snd-ali5451", "snd-trident" ],
     "via82cxxx_audio" => [ "snd-via82xx" ],
     "wavefront" => [ "snd-wavefront" ],
     "ymfpci"  => [ "snd-ymfpci" ]
     );

my @blacklist = qw(cs46xx cs4281);
my $blacklisted = 0;

sub rooted { run_program::rooted($::prefix, @_) }

sub unload { modules::unload(@_) if $::isStandalone || $blacklisted }

sub load { modules::load(@_) if $::isStandalone || $blacklisted }

sub get_alternative {
    my ($driver) = @_;
    $alsa2oss{$driver} || $oss2alsa{$driver};
}

sub do_switch {
    my ($old_driver, $new_driver) = @_;
    log::explanations("removing old $old_driver\n");
    rooted("service sound stop") unless $blacklisted;
    rooted("service alsa stop") if $old_driver =~ /^snd-/ && !$blacklisted;
    unload($old_driver); #    run_program("/sbin/modprobe -r $driver"); # just in case ...
    modules::remove_module($old_driver); # completed by the next add_alias()
    modules::add_alias("sound-slot-$::i", $new_driver);
    modules::write_conf();
    if ($new_driver =~ /^snd-/) {
        rooted("service alsa start") unless $blacklisted;
        rooted("/sbin/chkconfig --add alsa");
        load($new_driver); # service alsa is buggy
    } else { rooted("/sbin/chkconfig --del alsa") }
    log::explanations("loading new $new_driver\n");
    rooted("/sbin/chkconfig --add sound"); # just in case ...
    rooted("service sound start") unless $blacklisted;
}

sub switch {
    my ($in, $device) = @_;
    my $driver = $device->{current_driver};
    $driver ||= $device->{driver};

    foreach (@blacklist) { $blacklisted = 1 if $driver eq $_ }
    my $alternative = get_alternative($driver);
    if ($alternative) {
        my $new_driver = $alternative->[0];
        if ($new_driver eq 'unknown') {
            $in->ask_from(N("No alternative driver"),
                          N("There's no known OSS/ALSA alternative driver for your sound card (%s) which currently uses \"%s\"",
                            $device->{description}, $driver),
                          [
                           &get_any_driver_entry($in, $driver, $device),
                          ]
                         );
        } elsif ($in->ask_from_({ title => N("Sound configuration"),
                                  messages => 
				  N("Here you can select an alternative driver (either OSS or ALSA) for your sound card (%s).",
				    $device->{description}) .
				  N("\n\nYour card currently use the %s\"%s\" driver (default driver for your card is \"%s\")", ($driver =~ /^snd-/ ? "ALSA " : "OSS "), $driver, $device->{driver}),
				  interactive_help => sub {  
				      N("OSS (Open Sound System) was the first sound API. It's an OS independant sound API (it's available on most unices systems) but it's a very basic and limited API.
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
                                    label => N("Driver:"), val => \$new_driver, list => $alternative, default => $new_driver, sort =>1,
                                    format => sub {
                                        my %des = modules::category2modules_and_description('multimedia/sound');
                                        "$_[0] (" . $des{$_[0]} . ')';
                                    },
                                    allow_empty_list => 1,
                                },
                                {
                                    val => N("Trouble shooting"), disabled => sub {},
                                    clicked => sub { &trouble($in) }
                                },
                                &get_any_driver_entry($in, $driver, $device),
                                ]))
        {
            return if $new_driver eq $driver;
            log::explanations("switching audio driver from '$driver' to '$new_driver'\n");
            $in->ask_warn(N("Warning"), N("The old \"%s\" driver is blacklisted.\n
It has been reported to oops the kernel on unloading.\n
The new \"%s\" driver'll only be used on next bootstrap.", $driver, $new_driver)) if $blacklisted;
            my $wait = $in->wait_message(N("Please wait"), N("Please Wait... Applying the configuration"));
            do_switch($driver, $new_driver);
            undef $wait;
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
                      [ &get_any_driver_entry($in, $driver, $device) ]);
    } else {
        $in->ask_warn(N("Unkown driver"), 
                      N("Error: The \"%s\" driver for your sound card is unlisted"),
                      $driver);
    }
  end:
}

sub config {
    my ($in, $device) = @_;
    switch($in, $device);
}


sub trouble {
    my ($in) = @_;
    $in->ask_warn(N("Sound trouble shooting"),
                  formatAlaTeX(N("The classic bug sound tester is to run the following commands:


- \"lspcidrake -v | fgrep AUDIO\" will tell you which driver your card use
by default

- \"grep snd-slot /etc/modules.conf\" will tell you what driver it
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

sub choose_any_driver {
    my ($in, $driver, $card) = @_;
    my $old_driver = $driver;
    if ($in->ask_from(N("Choosing an arbitratry driver"),
                      formatAlaTeX(N("If you really think that you know which driver is the right one for your card
you can pick one in the above list.

The current driver for your \"%s\" sound card is \"%s\" ", $card, $driver)),
                      [
                       { label => N("Driver:"), val => \$driver, list => [ category2modules("multimedia/sound") ], type => 'combo', default => $driver, sort =>1, separator => '|' },
                      ]
                     )) {
        
        do_switch($old_driver, $driver);
    }
}

sub get_any_driver_entry {
    my ($in, $driver, $device) = @_;
    {
        val => N("Let me pick any driver"), disabled => sub {},
        clicked => sub { &choose_any_driver($in, $driver, $device->{description}); goto end }
    }
}


sub configure_sound_slots {
    each_index {
        modules::add_alias("sound-slot-$::i", $_->{driver});
    } detect_devices::getSoundDevices();
}


1;
