package Xconfigurator;

use diagnostics;
use strict;
use vars qw($in $install $resolution_wanted @depths @resolutions @accelservers @allservers %videomemory @ramdac_name @ramdac_id @clockchip_name @clockchip_id %keymap_translate @vsync_range %standard_monitors $intro_text $finalcomment_text $s3_comment $cirrus_comment $probeonlywarning_text $monitorintro_text $hsyncintro_text $vsyncintro_text $XF86firstchunk_text $keyboardsection_start $keyboardsection_part2 $keyboardsection_end $pointersection_text1 $pointersection_text2 $monitorsection_text1 $monitorsection_text2 $monitorsection_text3 $monitorsection_text4 $modelines_text_Trident_TG_96xx $modelines_text $devicesection_text $screensection_text1);

use pci_probing::main;
use common qw(:common :file);
use log;

use Xconfigurator_consts;

my $tmpconfig = "/tmp/Xconfig";

1;

sub setVirtual($) {
    my $vt = '';
    local *C; 
    sysopen C, "/dev/console", 2 or die "failed to open /dev/console: $!";
    ioctl(C, c::VT_GETSTATE(), $vt) or die "ioctl VT_GETSTATE failed";
    ioctl(C, c::VT_ACTIVATE(), $_[0]) or die "ioctl VT_ACTIVATE failed";
    ioctl(C, c::VT_WAITACTIVE(), $_[0]) or die "ioctl VT_WAITACTIVE failed";
    unpack "S", $vt;
}

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    local *F;
    open F, $file or die "file $file not found";

    my $lineno = 0; foreach (<F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and last;

	my ($cmd, $val) = /(\S+)\s*(.*)/ or log::l("bad line $lineno ($_)"), next;

	my $f = $ {{ 
	    LINE => sub { push @{$card->{lines}}, $val unless $val eq "VideoRam" },
	    NAME => sub {
		$cards{$card->{type}} = $card if $card;
		$card = { type => $val };
	    },
	    SEE => sub {
		my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";
    
		push @{$card->{lines}}, @{$c->{lines} || []};
		add2hash($card->{flags}, $c->{flags});
		add2hash($card, $c);
	    },
	    CHIPSET => sub { $card->{chipset} = $val; 
			     $card->{flags}->{needVideoRam} = 1 if member($val, qw(mgag10 mgag200 RIVA128));
			 },
	    SERVER => sub { $card->{server} = $val; },
	    RAMDAC => sub { $card->{ramdac} = $val; },
	    DACSPEED => sub { $card->{dacspeed} = $val; },
	    CLOCKCHIP => sub { $card->{clockchip} = $val; $card->{flags}->{noclockprobe} = 1; },
	    NOCLOCKPROBE => sub { $card->{flags}->{noclockprobe} = 1 },
	    UNSUPPORTED => sub { $card->{flags}->{unsupported} = 1 },
	}}{$cmd};

	$f ? &$f() : log::l("unknown line $lineno ($_)");
    }
    push @{$cards{S3}->{lines}}, $s3_comment;
    push @{$cards{'CL-GD'}->{lines}}, $cirrus_comment;

    # this entry is broken in X11R6 cards db 
    $cards{I128}->{flags}->{noclockprobe} = 1;

    %cards;
}

sub readMonitorsDB {
    my ($file) = @_;
    my %monitors;

    local *F;
    open F, $file or die "can't open monitors database ($file): ?!";
    my $lineno = 0; foreach (<F>) {
	$lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;

	my @fields = qw(type bandwidth hsyncrange vsyncrange);
	my @l = split /\s*;\s*/;
	@l == @fields or log::l("bad line $lineno ($_)"), next;
	
	my %l; @l{@fields} = @l;
	$monitors{$l{type}} = \%l;
    }
    while (my ($k, $v) = each %standard_monitors) {
	$monitors{$k} = 
	  $monitors{$v->[0]} = 
	    { hsyncrange => $v->[1], vsyncrange => $v->[2] };
    }
    %monitors;
}

sub rewriteInittab {
    my ($runlevel) = @_;
    {
	local (*F, *G);
	open F, "/etc/inittab" or die "cannot open /etc/inittab: $!";
	open G, "> /etc/inittab-" or die "cannot write in /etc/inittab-: $!";
    
	foreach (<F>) {
	    print G /^id:/ ? "id:$runlevel:initdefault:\n" : $_;
	}
    }
    unlink("/etc/inittab");
    rename("/etc/inittab-", "/etc/inittab");
}

sub findLegalModes {
    my ($card) = @_;
    my $mem = $card->{memory} || 1000000;

    foreach (@resolutions) {
	my ($h, $v) = split 'x';
	
	foreach $_ (@depths) {
	    push @{$card->{depth}->{$_}}, [ $h, $v ] if 1024 * $mem >= $h * $v * $_ / 8;
	}
    }
}

sub cardConfigurationAuto() {
    my $card;
    if (my ($c) = pci_probing::main::probe('video')) {
	local $_;
	($card->{identifier}, $_) = @$c;
	$card->{type} = $1 if /Card:(.*)/;
	$card->{server} = $1 if /Server:(.*)/;
    }
    $card;
}

sub cardConfiguration(;$) {
    my $card = shift || {};

    my %cards = readCardsDB("/usr/X11R6/lib/X11/Cards");

    add2hash($card, cardConfigurationAuto()) unless $card->{type} || $card->{server} || $::expert;
    add2hash($card, { type => $in->ask_from_list('', _("Choose a graphic card"), [keys %cards]) }) unless $card->{type} || $card->{server};
    add2hash($card, $cards{$card->{type}}) if $card->{type};
    add2hash($card, { vendor => "Unknown", board => "Unknown" });

    $card->{prog} = "/usr/X11R6/bin/XF86_$card->{server}";

    -x $card->{prog} or !defined $install or &$install($card->{server});
    -x $card->{prog} or die "server $card->{server} is not available (should be in $card->{prog})";

    unless ($::testing) {
	unlink("/etc/X11/X");
	symlink("../../$card->{prog}", "/etc/X11/X");
    }

    unless ($card->{type}) {
	$card->{flags}->{noclockprobe} = member($card->{server}, qw(I128 S3 S3V Mach64));
    }

    $card->{flags}->{needVideoRam} and
      $card->{memory} ||= 
	$videomemory{$in->ask_from_list_('', 
					 _("Give your graphic card memory size"), 
					 [ sort { $videomemory{$a} <=> $videomemory{$b} } 
					   keys %videomemory])};
    $card;
}

sub monitorConfiguration(;$) {
    my $monitor = shift || {};

    my %monitors = readMonitorsDB("MonitorsDB");

    add2hash($monitor, { type => $in->ask_from_list('', _("Choose a monitor"), [keys %monitors]) }) unless $monitor->{type};
    add2hash($monitor, $monitors{$monitor->{type}});
    add2hash($monitor, { vendor => "Unknown", model => "Unknown" });
    $monitor;
}

sub testConfig($) {
    my ($o) = @_;
    my ($resolutions, $clocklines);

    write_XF86Config($o, $tmpconfig);

    local *F;
    open F, "$o->{card}->{prog} :9 -probeonly -pn -xf86config $tmpconfig 2>&1 |";
    foreach (<F>) {
	#$videomemory = $2 if /(videoram|Video RAM):\s*(\d*)/;
	# look for clocks
	push @$clocklines, $1 if /clocks: (.*)/ && !/(pixel |num)clocks:/;

	push @$resolutions, [ $1, $2 ] if /: Mode "(\d+)x(\d+)": mode clock/;
	print;
    }
    close F or die "X probeonly failed";

    ($resolutions, $clocklines);
}

sub testFinalConfig($) {
    my ($o) = @_;

    write_XF86Config($o, $::testing ? $tmpconfig : "/etc/X11/XF86Config");

    my $pid; unless ($pid = fork) {
	my @l = "X";
	@l = ($o->{card}->{prog}, "-xf86config", $tmpconfig) if $::testing;
	exec @l, ":9" or exit 1;
    }
    do { sleep 1; } until (c::Xtest(':0'));

    local *F;
    open F, "|perl" or die;
    print F "use lib qw(", join(' ', @INC), ");\n";
    print F q{
	use interactive_gtk;
        use my_gtk qw(:wrappers);

	$ENV{DISPLAY} = ":9";
        gtkset_mousecursor(2);
        gtkset_background(200, 210, 210);
        my ($h, $w) = Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW)->get_size;
        $my_gtk::force_position = [ $w / 3, $h / 2.4 ];
	$my_gtk::force_focus = 1;
	exit !interactive_gtk->new->ask_yesorno('', _("It this ok?"));
    };
    my $rc = close F;
    kill 2, $pid;

    $rc;
}

sub autoResolutions($) {
    my ($o) = @_;
    my $card = $o->{card};

    my $hres_wanted = first(split 'x', $o->{resolution_wanted});

    # For the mono and vga16 server, no further configuration is required.
    return if member($card->{server}, "Mono", "VGA16");

    # Configure the modes order.
    my ($ok, $best);
    foreach (reverse @depths) {
	local $card->{default_depth} = $_;

	my ($resolutions, $clocklines) = eval { testConfig($o) };
	if ($@ || !$resolutions) {
	    delete $card->{depth}->{$_};
	} else {
	    $card->{clocklines} ||= $clocklines unless $card->{flags}->{noclockprobe};
	    $card->{depth}->{$_} = $resolutions;

	    $ok ||= $resolutions;
	    my ($b) = sort { $b->[0] <=> $a->[0] } @$resolutions;

	    # require $resolution_wanted, no matter what bpp this requires
	    $card->{default_depth} = $_, last if $b->[0] >= $hres_wanted;
	}
    }
    $ok or die "no valid modes";
}


sub resolutionsConfiguration {
    my ($o, $manual) = @_;
    my $card = $o->{card};

    # some of these guys hate to be poked               
    # if we dont know then its at the user's discretion
    #my $manual ||= 
    #  $card->{server} =~ /^(TGA|Mach32)/ || 
    #  $card->{name} =~ /^Riva 128/ ||
    #  $card->{chipset} =~ /^(RIVA128|mgag)/ ||
    #  $::expert;
    #
    #my $unknown = 
    #  member($card->{server}, qw(S3 S3V I128 Mach64)) ||
    #  member($card->{type}, 
    #	      "Matrox Millennium (MGA)",
    #	      "Matrox Millennium II",
    #	      "Matrox Millennium II AGP",
    #	      "Matrox Mystique",
    #	      "Matrox Mystique",
    #	      "S3",
    #	      "S3V",
    #	      "I128",
    #	     ) ||
    #  $card->{type} =~ /S3 ViRGE/;
    #
    #$unknown and $manual ||= !$in->ask_okcancel('', [ _("I can try to autodetect information about graphic card, but it may freeze :("),
    #						       _("Do you want to try?") ]);
    
    findLegalModes($card);

    unless ($manual || $::expert || !$in->ask_okcancel(_("Automatic resolutions"), 
_("I can try to find the available resolutions (eg: 800x600).
Alas it can freeze sometimes
Do you want to try?"))) {
	# swith to virtual console 1 (hopefully not X :)
	my $vt = setVirtual(1);
	autoResolutions($o);
	# restore the virtual console
	setVirtual($vt);
    }
    my %l;
    foreach ($card->{depth})

    ask_from_list(_("Resolution"),
		  _("Choose resolution and color depth"),
		  [ ]);
}


# * Create the XF86Config file. 
sub write_XF86Config {
    my ($o, $file) = @_;
    my $O;

    local *F;
    open F, ">$file" or die "can't write XF86Config in $file: $!";

    print F $XF86firstchunk_text;

    # Write keyboard section.     
    $O = $o->{keyboard};
    print F $keyboardsection_start;

    print F "    RightAlt        ", ($O->{altmeta} ? "ModeShift" : "Meta"), "\n";
    print F $keyboardsection_part2;
    print F qq(    XkbLayout       "$O->{xkb_keymap}"\n);
    print F $keyboardsection_end;

    # Write pointer section.     
    $O = $o->{mouse};
    print F $pointersection_text1;
    print F qq(    Protocol    "$O->{type}"\n);
    print F qq(    Device      "$O->{device}"\n);
    # this will enable the "wheel" or "knob" functionality if the mouse supports it 
    print F "    ZAxisMapping 4 5\n" if
      member($O->{type}, qw(IntelliMouse IMPS/2 ThinkingMousePS/2 NetScrollPS/2 NetMousePS/2 MouseManPlusPS/2));

    print F $pointersection_text2;
    print F "#" unless $O->{emulate3buttons};
    print F "    Emulate3Buttons\n";
    print F "#" unless $O->{emulate3buttons};
    print F "    Emulate3Timeout    50\n\n";
    print F "# ChordMiddle is an option for some 3-button Logitech mice\n\n";
    print F "#" unless $O->{chordmiddle};
    print F "    ChordMiddle\n\n";
    print F "    ClearDTR\n" if $O->{cleardtrrts};
    print F "    ClearRTS\n\n"  if $O->{cleardtrrts};
    print F "EndSection\n\n\n";

    # Write monitor section.     
    $O = $o->{monitor};
    print F $monitorsection_text1;
    print F qq(    Identifier "$O->{type}"\n);
    print F qq(    VendorName "$O->{vendor}"\n);
    print F qq(    ModelName  "$O->{model}"\n);
    print F "\n";
    print F $monitorsection_text2;
    print F qq(    HorizSync  $O->{hsyncrange}\n);
    print F "\n";
    print F $monitorsection_text3;
    print F qq(    VertRefresh $O->{vsyncrange}\n);
    print F "\n";
    print F $monitorsection_text4;
    print F ($o->{card}->{type} eq "TG 96" ? 
	     $modelines_text_Trident_TG_96xx :
	     $modelines_text);
    print F "EndSection\n\n\n";

    # Write Device section.     
    $O = $o->{card};
    print F $devicesection_text;
    print F qq(Section "Device"\n);
    print F qq(    Identifier  "$O->{type}"\n);
    print F qq(    VendorName  "$O->{vendor}"\n);
    print F qq(    BoardName   "$O->{board}"\n);

    print F "#" if $O->{memory} && !$O->{flags}->{needVideoRam};
    print F "    VideoRam    $O->{memory}\n" if $O->{memory};

    print F map { "    $_\n" } @{$O->{lines}};

    print F qq(    Ramdac      "$O->{ramdac}"\n) if $O->{ramdac};
    print F qq(    Dacspeed    "$O->{dacspeed}"\n) if $O->{dacspeed};

    if ($O->{clockchip}) {
	print F qq(    Clockchip   "$O->{clockchip}"\n);
    } else {
	print F "    # Clock lines\n";
	print F "    Clocks $_\n" foreach (@{$O->{clocklines}});
    }
    print F "EndSection\n\n\n";

    # Write Screen sections.     
    print F $screensection_text1;

    my $screen = sub {
	my ($server, $defdepth, $device, $depths) = @_;
	print F qq(

Section "Screen"
    Driver "$server"
    Device      "$device"
    Monitor     "$o->{monitor}->{type}"
);
	print F "    DefaultColorDepth $defdepth\n" if $defdepth;

        foreach (sort { $a <=> $b } keys %$depths) {
	    my $m = join(" ", 
			 map { '"' . join("x", @$_) . '"' }
			 sort { $b->[0] <=> $a->[0] } @{$depths->{$_}});
	    print F qq(    Subsection "Display"\n);
	    print F qq(        Depth       $_\n) if $_;
	    print F qq(        Modes       $m\n);
	    print F qq(        ViewPort    0 0\n);
	    print F qq(    EndSubsection\n);
	}
	print F "EndSection\n";
    };
    
    # SVGA screen section.
    print F qq(
# The Colour SVGA server
);

    if ($O->{server} eq 'SVGA') {
	&$screen("svga", $O->{default_depth}, $O->{type}, $O->{depth});
    } else {
	&$screen("svga", '', "Generic VGA", { 8 => [[ 320, 200 ]] });
    }

    &$screen("vga16", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"), 
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("vga2", '',
	     (member($O->{server}, "Mono", "VGA16") ? $O->{type} : "Generic VGA"), 
	     { '' => [[ 640, 480 ], [ 800, 600 ]]});

    &$screen("accel", $O->{default_depth}, $O->{type}, $O->{depth});
}

sub XF86check_link {
    my ($void) = @_;

    my $f = "/etc/X11/XF86Config";
    touch($f);

    my $l = "/usr/X11R6/lib/X11/XF86Config";

    if (-e $l && (stat($f))[1] != (stat($l))[1]) { # compare the inode, must be the sames
	-e $l and unlink($l) || die "can't remove bad $l";
	symlink "../../../../etc/X11/XF86Config", $l;
    }
}


# * Program entry point. 
sub main {
    my ($default, $interact, $install_pkg) = @_;
    my $o = $default;
    $in = $interact;
    $install = $install_pkg;

    $o->{resolution_wanted} ||= $resolution_wanted;
    
    XF86check_link();

    $o->{card} = cardConfiguration($o->{card});

    $o->{monitor} = monitorConfiguration($o->{monitor});

    resolutionsConfiguration($o);

    my $ok = testFinalConfig($o);
    my $quit;

    until ($ok || $quit) {

	my %c = my @c = (
	   __("Change Monitor") => sub { $o->{monitor} = monitorConfiguration() },
           __("Change Graphic card") => sub { $o->{card} = cardConfiguration() },
	   __("Change Resolution") => sub { resolutionsConfiguration($o, 1) },
	   __("Test again") => sub { $ok = testFinalConfig($o) },
	   __("Quit") => sub { $quit = 1 },
        );
	&{$c{$in->ask_from_list_('', 
				 _("What do you want to do?"),
				 [ grep { !ref } @c ])}};
    }
    
    # Success 
#    rewriteInittab($rc ? 3 : 5) unless $::testing;
}
