package Xconfig::xfree; # $Id$

use diagnostics;
use strict;

use common;
use Xconfig::parse;

#- mostly internal only
sub new {
    my ($class, $val) = @_;
    bless $val, $class;
}

sub _conf_files() {
    map { "$::prefix/etc/X11/$_" } 'xorg.conf', 'XF86Config-4', 'XF86Config';
}

################################################################################
# I/O ##########################################################################
################################################################################
sub read_and_prepare_write {
    my ($class) = @_;
    my $file = find { -f $_ } _conf_files();
    my $raw_X = $class->new(Xconfig::parse::read_XF86Config($file));
    my $before = $raw_X->prepare_write;

    if (my ($Keyboard) = $raw_X->get_InputDevices('Keyboard')) {
	$Keyboard->{Driver}{val} = 'keyboard';
    }

    #- ugly hack to fix empty ModeLine lines, XFdrake seems to generate some, but where???
    #- at least this allows fixing the pb by re-running XFdrake 
    foreach ($raw_X->get_Sections('Monitor')) {
	my $l = $_->{ModeLine} or next;
	@$l = grep { $_->{val} } @$l;
    }

    $raw_X, $before;
}
sub read {
    my ($class) = @_;
    first(read_and_prepare_write($class));
}
sub write {
    my ($raw_X, $o_file) = @_;
    my $file = $o_file || first(_conf_files());
    if (!$o_file) {
	foreach (_conf_files()) {
	    if (-l $_) {
		unlink $_;
	    } else {
		renamef($_, "$_.old"); #- there will not be any XF86Config nor XF86Config-4 anymore, we want this!
	    }
	}
	#- keep it for old programs still using this name
	symlink basename($file), "$::prefix/etc/X11/XF86Config";
    }
    Xconfig::parse::write_XF86Config($raw_X, $file);
}
sub prepare_write {
    my ($raw_X) = @_;
    join('', Xconfig::parse::prepare_write_XF86Config($raw_X));
}
sub empty_config {
    my ($class) = @_;
    $class->new(Xconfig::parse::read_XF86Config_from_string(our $default_header));
}

################################################################################
# keyboard #####################################################################
################################################################################
my @keyboard_fields = qw(XkbLayout XkbModel XkbDisable XkbOptions XkbCompat);
sub get_keyboard {
    my ($raw_X) = @_;
    my $raw_kbd = first(map { $raw_X->get_InputDevices($_) } 'keyboard', 'kbd') or die "no keyboard section";
    raw_export_section($raw_kbd, \@keyboard_fields);
}
sub set_keyboard {
    my ($raw_X, $kbd) = @_;
    my $raw_kbd = first(map { $raw_X->get_InputDevices($_) } 'keyboard', 'kbd') || _new_keyboard_section($raw_X);
    raw_import_section($raw_kbd, $kbd);
    _set_Option('keyboard', $raw_kbd, keys %$kbd);
}
sub _new_keyboard_section {
    my ($raw_X) = @_;
    my $raw_kbd = { Identifier => { val => 'Keyboard1' }, Driver => { val => 'keyboard' } };
    $raw_X->add_Section('InputDevice', $raw_kbd);

    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    push @$layout, { val => '"Keyboard1" "CoreKeyboard"' };

    $raw_kbd;
}


################################################################################
# mouse ########################################################################
################################################################################
#- example: { Protocol => 'IMPS/2', Device => '/dev/psaux', Emulate3Buttons => undef, Emulate3Timeout => 50, ZAxisMapping => [ '4 5', '6 7' ] }
my @mouse_fields = qw(Protocol Device ZAxisMapping Emulate3Buttons Emulate3Timeout); #-);
sub get_mice {
    my ($raw_X) = @_;
    my @raw_mice = $raw_X->get_InputDevices('mouse');
    map { raw_export_section($_, \@mouse_fields) } @raw_mice;
}
sub set_mice {
    my ($raw_X, @mice) = @_;
    my @raw_mice = _new_mouse_sections($raw_X, int @mice);
    mapn { 
	my ($raw_mouse, $mouse) = @_;
	raw_import_section($raw_mouse, $mouse);
	_set_Option('mouse', $raw_mouse, keys %$mouse);
    } \@raw_mice, \@mice;
}
sub _new_mouse_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_InputDevices('mouse');
    
    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    @$layout = grep { $_->{val} !~ /^"Mouse/ } @$layout;
    
    $nb_new or return;
    
    my @l = map {
	my $h = { Identifier => { val => "Mouse$_" }, Driver => { val => 'mouse' } };
	$raw_X->add_Section('InputDevice', $h);
    } (1 .. $nb_new);
    
    push @$layout, { val => qq("Mouse1" "CorePointer") };
    push @$layout, { val => qq("Mouse$_" "SendCoreEvents") } foreach 2 .. $nb_new;
    
    @l;
}


################################################################################
# resolution ###################################################################
################################################################################
sub get_resolution {
    my ($raw_X, $o_Screen) = @_;
    my $Screen = $o_Screen || $raw_X->get_default_screen or return {};
    
    my $depth = val($Screen->{DefaultColorDepth} || $Screen->{DefaultDepth});
    my $Display = find { !$depth || val($_->{l}{Depth}) eq $depth } @{$Screen->{Display} || []} or return {};
    $Display->{l}{Virtual} && val($Display->{l}{Virtual}) =~ /(\d+)\s+(\d+)/ or
      val($Display->{l}{Modes}) =~ /(\d+)x(\d+)/ or return {};
    { X => $1, Y => $2, Depth => val($Display->{l}{Depth}) };
}
sub set_resolution {
    my ($raw_X, $resolution, $o_Screen_) = @_;
    
    foreach my $Screen ($o_Screen_ ? $o_Screen_ : $raw_X->get_Sections('Screen')) {
	$Screen ||= $raw_X->get_default_screen or internal_error('no screen');

	my $Mode_name = (any { $_->{l}{Modes} } @{$Screen->{Display} || []}) ? 'Modes' : 'Virtual';
	my $Mode = sprintf($Mode_name eq 'Modes' ? '"%dx%d"' : '%d %d', @$resolution{'X', 'Y'});
	
	delete $Screen->{DefaultDepth};
	$Screen->{DefaultColorDepth} = { val => $resolution->{Depth} eq '32' ? 24 : $resolution->{Depth} };	
	$Screen->{Display} = [ map {
	    { l => { Depth => { val => $_ }, $Mode_name => { val => $Mode } } };
	} 8, 15, 16, 24 ];
    }
    add_gtf_ModeLines($raw_X, $resolution);
}


################################################################################
# device #######################################################################
################################################################################
my @device_fields = qw(VendorName BoardName Driver VideoRam Screen BusID); #-);
sub get_device {
    my ($raw_X) = @_;
    first(get_devices($raw_X));
}
sub get_devices {
    my ($raw_X) = @_;
    my @raw_devices = $raw_X->get_Sections('Device');
    map {
	my $raw_device = $_;
	my $device = raw_export_section($raw_device, [ 'Identifier', @device_fields ]);
	$device->{Options} = raw_export_section($raw_device, [ grep { (deref_array($raw_device->{$_}))[0]->{Option} } keys %$raw_device ]);
	$device;
    } @raw_devices;
}
sub set_devices {
    my ($raw_X, @devices) = @_;
    my @raw_devices = _new_device_sections($raw_X, int @devices);
    mapn { 
	my ($raw_device, $device) = @_;
	my %Options  = %{$device->{Options} || {}};
	raw_import_section($raw_device, $device, \@device_fields);
	raw_import_section($raw_device, \%Options);
	$_->{Option} = 1 foreach map { deref_array($raw_device->{$_}) } keys %Options;
	$raw_device->{''} = [ { post_comment => $device->{raw_LINES} } ] if $device->{raw_LINES};
    } \@raw_devices, \@devices;
}
sub _new_device_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_Section('Device');
    map { $raw_X->add_Section('Device', { Identifier => { val => "device$_" }, DPMS => { Option => 1 } }) } (1 .. $nb_new);
}
sub get_Driver {
    my ($raw_X) = @_;
    my $card = eval { $raw_X->get_device };
    $card && $card->{Driver};
}

################################################################################
# wacoms #######################################################################
################################################################################
sub set_wacoms {
    my ($raw_X, @wacoms) = @_;
    $raw_X->remove_InputDevices('wacom');
    
    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    @$layout = grep { $_->{val} !~ /^"(Stylus|Eraser|Cursor)/ } @$layout;
    
    @wacoms or return;
    
    my %Modes = (Stylus => 'Absolute', Eraser => 'Absolute', Cursor => 'Relative');
    
    each_index {
	my $wacom = $_;
	foreach (keys %Modes) {
	    my $identifier = $_ . ($::i + 1);
	    my $h = { Identifier => { val => $identifier }, 
		      Driver => { val => 'wacom' },
		      Type => { val => lc $_, Option => 1 },
		      Device => { val => $wacom->{Device}, Option => 1 },
		      Mode => { val => $Modes{$_}, Option => 1 },
		      if_($wacom->{USB}, USB => { Option => 1 })
		    };
	    $raw_X->add_Section('InputDevice', $h);
	    push @$layout, { val => qq("$identifier" "AlwaysCore") };
	}
    } @wacoms;
}


################################################################################
# synaptics ####################################################################
################################################################################
sub set_synaptics {
    my ($raw_X, @synaptics) = @_;
    $raw_X->remove_InputDevices('synaptics');

    my $layout = get_ServerLayout($raw_X)->{InputDevice} ||= [];
    @$layout = grep { $_->{val} !~ /^"SynapticsMouse/ } @$layout;

    @synaptics or return;
    add_load_module($raw_X, "synaptics");

    each_index {
	my $synaptics_mouse = $_;
        my $identifier = "SynapticsMouse" . ($::i + 1);
        my $pointer_type = $synaptics_mouse->{Primary} ? "CorePointer" : "AlwaysCore";
        my $h = {
            Identifier => { val => $identifier },
            Driver => { val => "synaptics" },
        };
        my %opts = (
            Device => $synaptics_mouse->{Device},
            Protocol => $synaptics_mouse->{Protocol},
            $synaptics_mouse->{ALPS} ? (
                #- from /usr/share/doc/synaptics-0.14.0/README.alps
                #- and http://qa.mandrakesoft.com/show_bug.cgi?id=14512
                LeftEdge => 120,
                RightEdge => 830,
                TopEdge => 120,
                BottomEdge => 650,
                FingerLow => 14,
                FingerHigh => 15,
                MaxTapTime => 180,
                MaxTapMove => 110,
                EmulateMidButtonTime => 75,
                VertScrollDelta => 20,
                HorizScrollDelta => 20,
                MinSpeed => '0.8',
                MaxSpeed => '1.00',
                AccelFactor => '0.015',
                EdgeMotionMinSpeed => 200,
                EdgeMotionMaxSpeed => 200,
                UpDownScrolling => 1,
                CircularScrolling => 1,
                CircScrollDelta => '0.1',
                CircScrollTrigger => 2,
                UpDownScrolling => 0,
            ) : (
                #- from /usr/share/doc/synaptics-0.14.0/INSTALL
                LeftEdge => 1700,
                RightEdge => 5300,
                TopEdge => 1700,
                BottomEdge => 4200,
                FingerLow => 25,
                FingerHigh => 30,
                MaxTapTime => 180,
                MaxTapMove => 220,
                VertScrollDelta => 100,
                MinSpeed => '0.09',
                MaxSpeed => '0.18',
                AccelFactor => '0.0015',
            ),
            SHMConfig => "on",
        );
        while (my ($k, $v) = each %opts) {
            $h->{$k} = { val => $v, Option => 1 };
        }
        $raw_X->add_Section('InputDevice', $h);
        push @$layout, { val => qq("$identifier" "$pointer_type") };
    } @synaptics;
}


################################################################################
# monitor ######################################################################
################################################################################
my @monitor_fields = qw(VendorName ModelName HorizSync VertRefresh);
sub get_monitors {
    my ($raw_X) = @_;
    my @raw_monitors = $raw_X->get_Sections('Monitor');
    map { 
	my $h = raw_export_section($_, [ 'Identifier', @monitor_fields ]);
	$h->{ModeLine} = $_->{ModeLine} if $_->{ModeLine};
	$h;
    } @raw_monitors;
}
sub set_monitors {
    my ($raw_X, @monitors) = @_;
    my @raw_monitors = _new_monitor_sections($raw_X, int @monitors);
    mapn { 
	my ($raw_monitor, $monitor) = @_;
	raw_import_section($raw_monitor, $monitor, \@monitor_fields);
	$raw_monitor->{ModeLine} = $monitor->{ModeLine} if $monitor->{ModeLine};
    } \@raw_monitors, \@monitors;
}
sub get_or_new_monitors {
    my ($raw_X, $nb_new) = @_;
    my @monitors = $raw_X->get_monitors;

    #- ensure we have exactly $nb_new monitors;
    if ($nb_new > @monitors) {
	@monitors, ({}) x ($nb_new - @monitors);
    } else {
	splice(@monitors, 0, $nb_new);
    }
}
sub _new_monitor_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_Section('Monitor');
    map { $raw_X->add_Section('Monitor', { Identifier => { val => "monitor$_" }, ModeLine => default_ModeLine() }) } (1 .. $nb_new);
}
sub default_ModeLine() {
    ModeLine_from_string(qq(Section "Monitor"\n) . (our $default_ModeLine) . qq(EndSection\n));
}

sub add_gtf_ModeLines {
    my ($raw_X, $resolution) = @_;

    my $banner = 'modeline generated by gtf(1) [handled by XFdrake]';
    my $res = $resolution->{X} . 'x' . $resolution->{Y};
    my @to_add;
    if ($res ne '1280x1024' && 
	  ($res eq '1400x1050' || $res eq '1152x864' || $Xconfig::xfree::resolution2ratio{$res} ne '4/3')) {
	@to_add = map {
	    my $s = run_program::rooted_get_stdout($::prefix, 'gtf', $resolution->{X}, $resolution->{Y}, $_);
	    if (my ($name, $val) = $s =~ /ModeLine\s*"(.*)"(.*)/i) {
		chomp $val;
		$name =~ s/\.00//;	#- nicer that way
		{ val => qq("${name}"$val), pre_comment => "# $banner\n" };
	    } else { () }
	} reverse(sort_numbers(@Xconfig::xfree::vfreqs));
    }

    $raw_X->set_monitors(map {
	@{$_->{ModeLine}} = (
	    (grep { index($_->{pre_comment}, $banner) == -1 } @{$_->{ModeLine}}),
	    @to_add,
	);
	$_;
    } $raw_X->get_monitors);
    
    1;
}


################################################################################
# screens ######################################################################
################################################################################
sub get_default_screen {
    my ($raw_X) = @_;
    my @l = $raw_X->get_Sections('Screen');
    (find { $_->{Identifier} && val($_->{Identifier}) eq 'screen1' || 
	      $_->{Driver} && val($_->{Driver}) =~ /svga|accel/ } @l) || $l[0];
}
sub set_screens {
    my ($raw_X, @screens) = @_;
    my @raw_screens = _new_screen_sections($raw_X, int @screens);
    mapn { 
	my ($raw_screen, $screen) = @_;
	raw_import_section($raw_screen, $screen);
    } \@raw_screens, \@screens;
}
sub _new_screen_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_Section('Screen');
    my @l = map { $raw_X->add_Section('Screen', { Identifier => { val => "screen$_" } }) } (1 .. $nb_new);

    get_ServerLayout($raw_X)->{Screen} = [ 
	{ val => qq("screen1") },
	map { { val => sprintf('"screen%d" RightOf "screen%d"', $_, $_ - 1) } } (2 .. $nb_new)
    ];
    @l;
}
sub is_fbdev {
    my ($raw_X, $o_Screen) = @_;

    my $Screen = $o_Screen || $raw_X->get_default_screen or return;

    my $Device = $raw_X->get_Section_by_Identifier('Device', val($Screen->{Device})) or internal_error("no device named $Screen->{Device}");
    val($Device->{Driver}) eq 'fbdev';
}




################################################################################
# modules ######################################################################
################################################################################
sub get_modules {
    my ($raw_X) = @_;
    my $raw_Module = $raw_X->get_Section('Module') or return;
    my $Module = raw_export_section($raw_Module, ['Load']);
    @{$Module->{Load} || []};
}
sub add_load_module {
    my ($raw_X, $module) = @_;
    my $raw_Module = $raw_X->get_Section('Module') || $raw_X->add_Section('Module', {});

    my %load_modules_comment = (
	dbe => 'Double-Buffering Extension',
	v4l => 'Video for Linux',
	dri => 'direct rendering',
	glx => '3D layer',
	'glx-3.so' => '3D layer',
    );
    my $comment = $load_modules_comment{$module};
    push @{$raw_Module->{Load}}, { val => $module,
				   comment_on_line => $comment && " # $comment",
				 } if !member($module, $raw_X->get_modules);
}
sub remove_load_module {
    my ($raw_X, $module) = @_;
    my $raw_Module = $raw_X->get_Section('Module') or return;
    if (my @l = grep { $_->{val} ne $module } @{$raw_Module->{Load}}) {
	$raw_Module->{Load} = \@l;
    } else {
	$raw_X->remove_Section('Module');
    }
}
sub set_load_module {
    my ($raw_X, $module, $bool) = @_;
    $bool ? add_load_module($raw_X, $module) : remove_load_module($raw_X, $module);
}


#-##############################################################################
#- helpers
#-##############################################################################
sub _set_Option {
    my ($category, $node, @names) = @_;
    
    if (member($category, 'keyboard', 'mouse')) {
	#- everything we export is an Option
	$_->{Option} = 1 foreach map { deref_array($node->{$_}) } @names;
    }
}

sub get_InputDevices {
    my ($raw_X, $Driver) = @_;
    $raw_X->get_Sections('InputDevice', sub { val($_[0]{Driver}) eq $Driver });
}
sub remove_InputDevices {    
    my ($raw_X, $Driver) = @_;
    $raw_X->remove_Section('InputDevice', sub { val($_[0]{Driver}) ne $Driver });
}

sub get_ServerLayout {
    my ($raw_X) = @_;
    $raw_X->get_Section('ServerLayout') ||
      $raw_X->add_Section('ServerLayout', { Identifier => { val => 'layout1' } });
}

#-##############################################################################
#- helpers
#-##############################################################################
sub raw_export_section {
    my ($section, $fields) = @_;

    my $export_name = sub {
	my ($name) = @_;
	my $h = $section->{$name} or return;

	my @l = map { if_(!$_->{commented}, $_->{val}) } deref_array($h) or return;    
	$name => (ref($h) eq 'ARRAY' ? \@l : $l[0]);
    };

    my %h = map { $export_name->($_) } @$fields;
    \%h;
}

sub raw_import_section {
    my ($section, $h, $o_fields) = @_;
    foreach ($o_fields ? grep { exists $h->{$_} } @$o_fields : keys %$h) {
	my @l = map { ref($_) eq 'HASH' ? $_ : { val => $_ } } deref_array($h->{$_});
	$section->{$_} = (ref($h->{$_}) eq 'ARRAY' ? \@l : $l[0]);
    }
}

sub add_Section {
    my ($raw_X, $Section, $h) = @_;
    my @suggested_ordering = qw(Files ServerFlags Module DRI Keyboard Pointer XInput InputDevice Monitor Device Screen ServerLayout);
    my %order = map_index { { lc($_) => $::i } } @suggested_ordering;
    my $e = { name => $Section, l => $h };
    my $added;
    @$raw_X = map { 
	if ($order{lc $_->{name}} > $order{lc $Section} && !$added) {
	    $added = 1;
	    ($e, $_);
	} else { $_ }
    } @$raw_X;
    push @$raw_X, $e if !$added;
    $h;
}
sub remove_Section {
    my ($raw_X, $Section, $o_when) = @_;
    @$raw_X = grep { $_->{name} ne $Section || $o_when && $o_when->($_->{l}) } @$raw_X;
    $raw_X;
}
sub get_Sections {
    my ($raw_X, $Section, $o_when) = @_;
    map { if_(lc($_->{name}) eq lc($Section) && (!$o_when || $o_when->($_->{l})), $_->{l}) } @$raw_X;
}
sub get_Section {
    my ($raw_X, $Section, $o_when) = @_;
    my @l = get_Sections($raw_X, $Section, $o_when);
    @l > 1 and log::l("Xconfig: found more than one Section $Section");
    $l[0];
}
sub get_Section_by_Identifier {
    my ($raw_X, $Section, $Identifier) = @_;
    my @l = get_Sections($raw_X, $Section, sub { val($_[0]{Identifier}) eq $Identifier });
    @l > 1 and die "more than one Section $Section has Identifier $Identifier";
    $l[0];
}

sub val {
    my ($ref) = @_;
    $ref && $ref->{val};
}


sub ModeLine_from_string {
    my ($s) = @_;
    my $raw_X_for_ModeLine = Xconfig::parse::read_XF86Config_from_string($s);
    get_Section($raw_X_for_ModeLine, 'Monitor')->{ModeLine};
}



# http://home.comcast.net/~igpl/Aspect.html
# movies http://www.technosound.co.uk/nav.php?pageid=hcg_widescreen
# esp for 1360x768 http://www.winischhofer.at/linuxsispart1.shtml

# www.dell.com/downloads/global/vectors/2003_cvt.pdf
# file vesamodes in Xorg is DMT Standard Display Modes

# http://www.vesa.org/Public
# http://www.vesa.org/Public/EEDIDguideV1.pdf 

#- http://www.vesa.org/Public/CVT
our @CVT_ratios = qw(4/3 16/9 16/10 5/4 15/9 3/2);
our @CVT_vfreqs = qw(50 60 75 85); # and also 60Hz "reduced blanking" in CVT

our @vfreqs = (@CVT_vfreqs, qw(100 120));

our %ratio2resolutions = (

    # first all the CVT_ratios

    # 1.25
    '5/4' => [ qw(640x512 720x576 1280x1024 1800x1440) ],
		# SXGA=1280x1024 QSXGA=2560x2048

    # 1.33
    '4/3' => [
	qw(320x240 480x360 640x480 800x600 832x624 
	   1024x768 1152x864 1280x960 1400x1050 
	   1600x1200 1920x1440 2048x1536), # 768x576 1792x1344 1856x1392
	    # DBLSCAN: 400x300 416x312 512x384 576x432 700x525 896x672 928x696 960x720
    ],		# VGA=640x480, SVGA=800x600, XGA=1024x768, SXGA+=1400x1050, UXGA=1600x1200, QXGA=2048x1536 QSXGA+=2800x2100, QUXGA=3200x2400

    # 1.5
    '3/2' => [ qw(360x240 720x480 1152x768) ], # 576x384 (DBLSCAN of 1152x768)

    # 1.6
    '16/10' => [ qw(1280x800 1440x900 1600x1000 1680x1050 1920x1200) ], # 320x200 640x400 960x600 2560x1600
                # WSXGA+=1680x1050, WUXGA=1920x1200, WQUXGA=3840x2400

    # 1.67
    '15/9' => [ qw(1280x768) ], # 800x480
		# WXGA=1280x768 or ??? (should be 1366x768)
    
    # 1.78
    '16/9' => [ qw(1280x720 1600x900 1920x1080) ], # 960x540 1024x576


    # now more weird things

    # 1.32
    # '192/145' => [ qw(1152x870) ],

    # 1.328
    # '85/64' => [ qw(1360x1024) ],

    # 1.42
    # '17/12' => [ qw(544x384) ] ,

    # 1.56
    # '25/16' => [ qw(1600x1024) ], # WSXGA, (DBLSCAN 800x512)

    # 1.707
    # '128/75' => [ qw(1024x600) ],

    # 1.767
    # '53/30' => [ qw(848x480) ],

    # 1.771
    # '85/48' => [ qw(1360x768) ],

    # 1.775
    # '71/40' => [ qw(852x480) ],

    # 1.783
    # '107/60' => [ qw(856x480) ],

    N_("_:weird aspect ratio\nother") => [
	# 2.13 = 32/15
	qw(1024x480 1280x600), # VAIO

	# 2.67 = 8/3
	qw(2048x768 2560x960 3200x1200),

	# 4.0 = 4/1
	qw(3072x768 3456x864 3840x960 4800x1200),

	# ?? 352x288 640x350 (DBLSCAN 320x175) 720x400 (DBLSCAN 360x200)
    ],
);

our %resolution2ratio = map_each { map { $_ => $::a } @$::b } %ratio2resolutions;
our @resolutions = map_each { @$::b } %ratio2resolutions;

foreach my $ratio (keys %ratio2resolutions) {
    if ($ratio =~ m!^(\d+)/(\d+)$!) {
	my $eval = $2 / $1;
	foreach (@{$ratio2resolutions{$ratio}}) {
	    my ($x, $y) = /(\d+)x(\d+)/;
	    my $y2 = round($x * $eval);
	    $y == $y2 or do {
		my $good_ratio = (find { m!^(\d+)/(\d+)$! && $y == round($x * $2 / $1) } keys %ratio2resolutions) || '??';
		die "bad ratio $ratio for resolution $_, it should be $good_ratio\n";
	    };
	}
    }
}

our $default_header = <<'END';
# File generated by XFdrake.

# **********************************************************************
# Refer to the xorg.conf man page for details about the format of
# this file.
# **********************************************************************

Section "Files"
    # Multiple FontPath entries are allowed (they are concatenated together)
    # By default, Mandrake 6.0 and later now use a font server independent of
    # the X server to render fonts.
    FontPath "unix/:-1"
EndSection

Section "ServerFlags"
    #DontZap # disable <Crtl><Alt><BS> (server abort)
    #DontZoom # disable <Crtl><Alt><KP_+>/<KP_-> (resolution switching)
    AllowMouseOpenFail # allows the server to start up even if the mouse does not work
END

require detect_devices;
$default_header .= <<'END_XBOX' if detect_devices::is_xbox();
    Option "PciProbe1" "false"
    Option "PciProbe2" "false"
    Option "PciForceConfig1" "false"
    Option "PciForceConfig2" "false"
    Option "PciOsConfig" "true"
END_XBOX

$default_header .= <<'END';
EndSection
END

our $default_ModeLine = arch() =~ /ppc/ ? <<'END_PPC' : <<'END';
    # Apple iMac modes
    ModeLine "1024x768"   78.525 1024 1049 1145 1312   768  769  772  800 +hsync +vsync
    ModeLine "800x600"    62.357  800  821  901 1040   600  601  604  632 +hsync +vsync
    ModeLine "640x480"    49.886  640  661  725  832   480  481  484  514 +hsync +vsync
    # Apple monitors tend to do 832x624
    ModeLine "832x624"    57      832  876  940 1152   624  625  628  667 -hsync -vsync
    # Apple PowerBook G3
    ModeLine "800x600"    100     800  816  824  840   600  616  624  640 -hsync -vsync
    # Apple TI Powerbook 
    ModeLine "1152x768"   78.741 1152 1173 1269 1440   768  769  772  800 +vsync +vsync
    # Pismo Firewire G3   
    ModeLine "1024x768"   65     1024 1032 1176 1344   768  771  777  806 -hsync -vsync
    # iBook2
    ModeLine "1024x768"   65     1024 1048 1184 1344   768  771  777  806 -hsync -vsync
    # 17" Apple Studio Display
    ModeLine "1024x768"   112.62 1024 1076 1248 1420 768 768 780 808 +hsync +vsync
    # HiRes Apple Studio Display
    ModeLine "1280x1024"  135    1280 1288 1392 1664  1024 1027 1030 1064
    # Another variation
    ModeLine "1280x1024"  134.989 1280 1317 1429 1688  1024 1025 1028 1066 +hsync +vsync
END_PPC
    # TV fullscreen mode or DVD fullscreen output.
    # 768x576 @ 79 Hz, 50 kHz hsync
    ModeLine "768x576"     50.00  768  832  846 1000   576  590  595  630
    # 768x576 @ 100 Hz, 61.6 kHz hsync
    ModeLine "768x576"     63.07  768  800  960 1024   576  578  590  616
END

1;
