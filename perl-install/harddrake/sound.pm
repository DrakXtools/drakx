package harddrake::sound;
# lists filled with Danny Tholen help, enhanced by Thierry Vignaud
#
# No ALSA for OSS's 
#    o btaudio (tv card),
#    o isa cards: msnd_pinnacle, pas2, 
# No OSS for ALSA's
#    o pci cards: snd-ali5451, snd-als4000, snd-es968, snd-fm801,
#      snd-hdsp, snd-via8233
#    o isa cards: snd-als100, snd-azt2320, snd-cmi8330, snd-cs4231,
#      snd-cs4236, snd-dt0197h, snd-es18xx,snd-es1688, snd-ice1712,
#      snd-korg1212, snd-rme32, snd-rme96
#    o usb cards: snd-usb-audio

# TODO: 
#    o ensure sound isn't user (either dsp/midi/sequencer/mixer)
#    o fix sound/alsa services

use strict;
use common;
use interactive;
use run_program;
use modules;
use standalone;

my %alsa2oss = 
    (
	"snd-ad1816a" => [ "ad1816" ], # isa
	"snd-ad1848"  => [ "ad1848" ], # isa
	"snd-ali5451" => [ "unknown" ],
	"snd-als100"  => [ "unknown" ], # isa
	"snd-als4000" => [ "unknown" ],
	"snd-azt2320" => [ "unknown" ], # isa
	"snd-cmi8330" => [ "unknown" ], # isa
	"snd-cmipci"  => [ "cmpci" ],
	"snd-cs4231"  => [ "unknown" ], # isa
	"snd-cs4232"  => [ "cs4232" ],  # isa
	"snd-cs4236"  => [ "unknown" ], # isa
	"snd-cs4281"  => [ "cs4281" ],
	"snd-cs46xx"  => [ "cs46xx" ],
	"snd-dt0197h" => [ "unknown" ], # isa
	"snd-emu10k1" => [ "audigy", "emu10k1" ],
	"snd-ens1370" => [ "es1370" ],
	"snd-ens1371" => [ "es1371" ],
	"snd-es1688"  => [ "unknown" ], # isa
	"snd-es18xx"  => [ "unknown" ], # isa
	"snd-es1938"  => [ "esssolo1" ],
	"snd-es1968"  => [ "maestro" ], # isa
	"snd-es968"   => [ "unknown" ],
	"snd-fm801"   => [ "unknown"],
	"snd-gusclassic" => [ "gus" ], # isa
	"snd-gusextreme" => [ "gus" ], # isa
	"snd-gusmax"  => [ "gus" ],    # isa
	"snd-hdsp" => [ "unknown" ],
	"snd-ice1712" => [ "unknown" ], # isa
	"snd-intel8x0" => [ "i810_audio" ],
	"snd-interwave" => [ "gus" ],  # isa
	"snd-korg1212" => [ "unknown" ], # isa
	"snd-maestro3" => [ "maestro3" ],
	"snd-mpu401"  => [ "mpu401" ],
	"snd-nm256"   => [ "nm256_audio" ],
	"snd-opl3sa2" => [ "opl3", "opl3sa", "opl3sa2" ], # isa
	"snd-opti93x" => [ "mad16" ],
	"snd-rme32"   => [ "unknown" ], # isa
	"snd-rme96"   => [ "unknown" ], # isa
	"snd-rme9652g" => [ "rme96xx" ],
	"snd-sb16"    => ["sscape", "sb"],
	"snd-sb8"     => [ "sb" ],
	"snd-sbawe"   => [ "awe_wave" ],
	"snd-sgalaxy" => [ "sgalaxy" ], # isa
	"snd-sonicvibes" => [ "sonicvibes" ],
	"snd-trident" => [ "trident" ],
	"snd-usb-audio" => [ "unknown" ], # usb
	"snd-via686"  => [ "via82cxxx_audio" ],
	"snd-via8233" => [ "unknown" ],
	"snd-wavefront" => [ "wavefront" ], # isa
	"snd-ymfpci"  => [ "ymfpci" ]
	);


my %oss2alsa = 
    (
	"ad1816"  => [ "snd-ad1816a" ],
	"ad1848"  => [ "snd-ad1848" ],
	"audigy"  => [ "snd-emu10k1" ],
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
	"gus"     => ["snd-interwave", "snd-gusclassic", "snd-gusmax", "snd-gusextreme"],
	"i810_audio" => [ "snd-intel8x0"],
	"mad16"   => [ "snd-opti93x" ],
	"maestro" => [ "snd-es1968" ],
	"maestro3" => [ "snd-maestro3" ],
	"mpu401"  => [ "snd-mpu401" ],
	"msnd_pinnacle" => [ "unknown" ],
	"msnd_pinnacle" =>  [ "unknown" ],
	"nm256_audio" => [ "snd-nm256" ],
	"opl3"    => [ "snd-opl3sa2" ],
	"opl3sa"  => [ "snd-opl3sa2" ],
	"opl3sa2" => [ "snd-opl3sa2" ],
	"pas2"    => [ "unknown" ],
	"rme96xx" => [ "snd-rme9652.o.g" ],
	"sb"      => ["snd-sb8", "snd-sb16"],
	"sgalaxy" => [ "snd-sgalaxy" ],
	"sonicvibes" => [ "snd-sonicvibes" ],
	"sscape"  => [ "snd-sb16" ],
	"trident" => [ "snd-trident" ],
	"via82cxxx_audio" => [ "snd-via686" ],
	"wavefront" => [ "snd-wavefront" ],
	"ymfpci"  => [ "snd-ymfpci" ]
	);

sub get_alternative {
    my ($driver) = @_;
    if ($alsa2oss{$driver}) {
	   $alsa2oss{$driver};
    } elsif ($oss2alsa{$driver}) {
	   $oss2alsa{$driver}
    } else { {} }
}

sub do_switch {
    my ($old_driver, $new_driver) = @_;
    standalone::explanations("removing old $old_driver\n");
    run_program::run("service sound stop");
    run_program::run("service alsa stop") if $old_driver =~ /^snd-/;
    modules::unload($old_driver); #    run_program("/sbin/modprobe -r $driver"); # just in case ...
    modules::remove_module($old_driver); # completed by the next add_alias()
    modules::add_alias('sound-slot-$::i', $new_driver);
    modules::write_conf;
    if ($new_driver =~ /^snd-/) {
	   run_program::run("service alsa start");
	   run_program::run("/sbin/chkconfig --add alsa");
	   modules::load($new_driver); # service alsa is buggy
    } else { run_program::run("/sbin/chkconfig --del alsa") }
    standalone::explanations("loading new $new_driver\n");
    run_program::run("/sbin/chkconfig --add sound"); # just in case ...
    run_program::run("service sound start");
}

sub switch {
    my ($in, $device) = @_;
    my $driver = $device->{driver};
    my $alternative = get_alternative($driver);
#    $alternative = [ "i810_audio", "snd-intel8x0"];
    if ($alternative) {
	   my $new_driver = $alternative->[0];
	   if ($driver eq "unknown") {
		  $in->ask_warn(_("No alternative driver"),
							_("There's no known OSS/ALSA alternative driver for your sound card (%s)",
							  $device->{description}));
	   } elsif ($in->ask_from(_("Sound configuration"),
						 _("Here you can select an alternative driver (either OSS or ALSA) for your sound card (%s)",
							  $device->{description}),
						 [
						  { label => _("Driver :"), val => \$new_driver, list => $alternative, default => $new_driver, sort =>1, format => sub {
							 my %des = modules::category2modules_and_description('multimedia/sound');
							 "$_[0] (". $des{$_[0]};
						  }, allow_empty_list => 1 }
						  ]))
	   {
		  standalone::explanations("switching audio driver from '$driver' to '$new_driver'\n");
		  do_switch($driver, $new_driver);
	   }
    } elsif ($driver eq "unknown") {
	   $in->ask_warn(_("No known driver"), 
						 _("There's no known driver for your sound card (%s)",
							  $device->{description}));
    } elsif (is_listed($driver)) {
    } else {
	   $in->ask_warn(_("Unkown driver"), 
							 _("The \"%s\" driver for your sound card is unlisted\n
Please send the output of the \"lspcidrake -v\" command to
Thierry Vignaud <tvignaud at mandrakesoft dot com>
with subject: unlisted sound driver")
							   , $driver);
    }
}

sub config {
    my ($in, $device) = @_;
    switch($in, $device);

}
