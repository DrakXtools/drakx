package Xconfig::xfreeX; # $Id$

use diagnostics;
use strict;

use Xconfig::parse;
use common;
use log;


sub empty_config {
    my ($class) = @_;
    my $raw_X = Xconfig::parse::read_XF86Config_from_string(our $default_header);
    bless $raw_X, $class;
}

sub read {
    my ($class, $file) = @_;
    $file ||= ($::prefix || '') . (bless {}, $class)->config_file;
    my $raw_X = Xconfig::parse::read_XF86Config($file);
    bless $raw_X, $class;
}
sub write {
    my ($raw_X, $file) = @_;
    $file ||= ($::prefix || '') . $raw_X->config_file;
    Xconfig::parse::write_XF86Config($raw_X, $file);
}


my @monitor_fields = qw(VendorName ModelName HorizSync VertRefresh);
sub get_monitors {
    my ($raw_X) = @_;
    my @raw_monitors = $raw_X->get_monitor_sections;
    map { raw_export_section($_, [ 'Identifier', @monitor_fields ]) } @raw_monitors;
}
sub set_monitors {
    my ($raw_X, @monitors) = @_;
    my @raw_monitors = $raw_X->new_monitor_sections(int @monitors);
    mapn { 
	my ($raw_monitor, $monitor) = @_;
	raw_import_section($raw_monitor, $monitor, \@monitor_fields);
    } \@raw_monitors, \@monitors;
}
sub get_monitor {
    my ($raw_X) = @_;
    my @l = $raw_X->get_monitors;
    if (!@l) {
	$raw_X->new_monitor_sections(1);
	@l = $raw_X->get_monitors;
    }
    $l[0]
}

my @keyboard_fields = qw(XkbLayout XkbModel XkbDisable XkbOptions);
sub get_keyboard {
    my ($raw_X) = @_;
    my $raw_kbd = $raw_X->get_keyboard_section;
    raw_export_section($raw_kbd, \@keyboard_fields);
}
sub set_keyboard {
    my ($raw_X, $kbd) = @_;
    my $raw_kbd = eval { $raw_X->get_keyboard_section } || $raw_X->new_keyboard_section;
    raw_import_section($raw_kbd, $kbd);
    $raw_X->set_Option('keyboard', $raw_kbd, keys %$kbd);
}

#- example: { Protocol => 'IMPS/2', Device => '/dev/psaux', Emulate3Buttons => undef, Emulate3Timeout => 50, ZAxisMapping => [ '4 5', '6 7' ] }
my @mouse_fields = qw(Protocol Device ZAxisMapping Emulate3Buttons Emulate3Timeout); #-);
sub get_mice {
    my ($raw_X) = @_;
    my @raw_mice = $raw_X->get_mouse_sections;
    map { raw_export_section($_, \@mouse_fields) } @raw_mice;
}
sub set_mice {
    my ($raw_X, @mice) = @_;
    my @raw_mice = $raw_X->new_mouse_sections(int @mice);
    mapn { 
	my ($raw_mouse, $mouse) = @_;
	raw_import_section($raw_mouse, $mouse);
	$raw_X->set_Option('mouse', $raw_mouse, keys %$mouse);
    } \@raw_mice, \@mice;
}

sub get_devices {
    my ($raw_X) = @_;
    my @raw_devices = $raw_X->get_device_sections;
    map {
	my $raw_device = $_;
	my $device = raw_export_section($raw_device, [ 'Identifier', $raw_X->get_device_section_fields ]);
	$device->{Options} = raw_export_section($raw_device, [ grep { (deref_array($raw_device->{$_}))[0]->{Option} } keys %$raw_device ]);
	$device;
    } @raw_devices;
}
sub set_devices {
    my ($raw_X, @devices) = @_;
    my @raw_devices = $raw_X->new_device_sections(int @devices);
    mapn { 
	my ($raw_device, $device) = @_;
	my %Options  = %{$device->{Options} || {}};
	add2hash(\%Options, $device->{'Options_' . $raw_X->name});
	raw_import_section($raw_device, $device, [ $raw_X->get_device_section_fields ]);
	raw_import_section($raw_device, \%Options);
	$_->{Option} = 1 foreach map { deref_array($raw_device->{$_}) } keys %Options;
	$raw_device->{''} = [ { post_comment => $device->{raw_LINES} } ] if $device->{raw_LINES};
    } \@raw_devices, \@devices;
}

sub get_device {
    my ($raw_X) = @_;
    first(get_devices($raw_X));
}

sub get_default_screen {
    my ($raw_X) = @_;
    my @l = $raw_X->get_Sections('Screen');
    my @m = grep { $_->{Identifier} && val($_->{Identifier}) eq 'screen1' || 
		   $_->{Driver} && val($_->{Driver}) =~ /svga|accel/ } @l;
    first(@m ? @m : @l);
}
sub set_screens {
    my ($raw_X, @screens) = @_;
    my @raw_screens = $raw_X->new_screen_sections(int @screens);
    mapn { 
	my ($raw_screen, $screen) = @_;
	raw_import_section($raw_screen, $screen);
    } \@raw_screens, \@screens;
}

sub get_modules {
    my ($raw_X) = @_;
    my $raw_Module = $raw_X->get_Section('Module') or return;
    my $Module = raw_export_section($raw_Module, ['Load']);
    @{$Module->{Load} || []};
}
sub add_load_module {
    my ($raw_X, $module) = @_;
    my $raw_Module = $raw_X->get_Section('Module') || $raw_X->new_module_section;

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

sub get_resolution {
    my ($raw_X, $Screen) = @_;
    $Screen ||= $raw_X->get_default_screen or return {};

    my $depth = val($Screen->{DefaultColorDepth});
    my ($Display) = grep { !$depth || val($_->{l}{Depth}) eq $depth } @{$Screen->{Display} || []} or return {};
    val($Display->{l}{Modes}) =~ /(\d+)x(\d+)/ or return {};
    { X => $1, Y => $2, Depth => val($Display->{l}{Depth}) };
}

sub set_resolution {
    my ($raw_X, $resolution, $Screen) = @_;
    $Screen ||= $raw_X->get_default_screen or internal_error('no screen');

    $Screen->{DefaultColorDepth} = { val => $resolution->{Depth} };
    $Screen->{Display} = [ map {
	my $modes = do {
	    if ($resolution->{fbdev}) {
		'"default"';
	    } else {
		my @Modes = grep { /(\d+)x/ && $1 <= $resolution->{X} } reverse our @resolutions;
		join(" ", map { qq("$_") } @Modes);
	    }
	};
	{ l => { Depth => { val => $_ }, Modes => { val => $modes } } };
    } $raw_X->depths ];
}


#-##############################################################################
#- common to xfree3 and xfree4
#-##############################################################################
sub default_ModeLine { our $default_ModeLine }


sub get_device_sections {
    my ($raw_X) = @_;
    $raw_X->get_Sections('Device');
}
sub new_device_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_Section('Device');
    map { $raw_X->add_Section('Device', { Identifier => { val => "device$_" } }) } (1 .. $nb_new);
}

sub get_monitor_sections {
    my ($raw_X) = @_;
    $raw_X->get_Sections('Monitor');
}
sub new_monitor_sections {
    my ($raw_X, $nb_new) = @_;
    my $ModeLine = ModeLine_from_string(qq(Section "Monitor"\n) . $raw_X->default_ModeLine . qq(EndSection\n));
    $raw_X->remove_Section('Monitor');
    map { $raw_X->add_Section('Monitor', { Identifier => { val => "monitor$_" }, ModeLine => $ModeLine }) } (1 .. $nb_new);
}

sub new_screen_sections {
    my ($raw_X, $nb_new) = @_;
    $raw_X->remove_Section('Screen');
    map { $raw_X->add_Section('Screen', {}) } (1 .. $nb_new);
}

sub new_module_section {
    my ($raw_X) = @_;
    return $raw_X->add_Section('Module', {});
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
    my ($section, $h, $fields) = @_;
    foreach ($fields ? grep { exists $h->{$_} } @$fields : keys %$h) {
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
    my ($raw_X, $Section, $when) = @_;
    @$raw_X = grep { $_->{name} ne $Section || ($when && $when->($_->{l})) } @$raw_X;
    $raw_X;
}
sub get_Sections {
    my ($raw_X, $Section, $when) = @_;
    map { if_($_->{name} eq $Section && (!$when || $when->($_->{l})), $_->{l}) } @$raw_X;
}
sub get_Section {
    my ($raw_X, $Section, $when) = @_;
    my @l = get_Sections($raw_X, $Section, $when);
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



our @resolutions = ('640x480', '800x600', '1024x768', if_(arch() =~ /ppc/, '1152x768'), '1152x864', '1280x1024', '1400x1050', '1600x1200', '1920x1440', '2048x1536');

our $default_header = << 'END';
# File generated by XFdrake.

# **********************************************************************
# Refer to the XF86Config man page for details about the format of
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
    AllowMouseOpenFail # allows the server to start up even if the mouse doesn't work
EndSection
END

our $default_ModeLine = arch() =~ /ppc/ ? << 'END_PPC' : << 'END';
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
    # Sony Vaio C1(X,XS,VE,VN)?
    # 1024x480 @ 85.6 Hz, 48 kHz hsync
    ModeLine "1024x480"    65.00 1024 1032 1176 1344   480  488  494  563 -hsync -vsync
    
    # TV fullscreen mode or DVD fullscreen output.
    # 768x576 @ 79 Hz, 50 kHz hsync
    ModeLine "768x576"     50.00  768  832  846 1000   576  590  595  630
    # 768x576 @ 100 Hz, 61.6 kHz hsync
    ModeLine "768x576"     63.07  768  800  960 1024   576  578  590  616
END

1;

