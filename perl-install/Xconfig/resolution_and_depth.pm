package Xconfig::resolution_and_depth; # $Id$

use diagnostics;
use strict;

use Xconfig::card;
use Xconfig::monitor;
use common;


our %depth2text = (
      8 => N_("256 colors (8 bits)"),
     15 => N_("32 thousand colors (15 bits)"),
     16 => N_("65 thousand colors (16 bits)"),
     24 => N_("16 million colors (24 bits)"),
     32 => N_("4 billion colors (32 bits)"),
);
our @depths_available = ikeys(%depth2text);

my %min_hsync4x_res = (
     640 => 31.5,
     800 => 35.1,
    1024 => 35.5,
    1152 => 44.0,
    1280 => 51.0,
    1400 => 65.5,
    1600 => 75.0,
    1920 => 90.0,
    2048 => 136.5,
);

my @bios_vga_modes = (
    { bios => 769, X =>  640, Y =>  480, Depth =>  8 },
    { bios => 771, X =>  800, Y =>  600, Depth =>  8 },
    { bios => 773, X => 1024, Y =>  768, Depth =>  8 },
    { bios => 775, X => 1280, Y => 1024, Depth =>  8 },
    { bios => 784, X =>  640, Y =>  480, Depth => 15 },
    { bios => 787, X =>  800, Y =>  600, Depth => 15 },
    { bios => 790, X => 1024, Y =>  768, Depth => 15 },
    { bios => 793, X => 1280, Y => 1024, Depth => 15 },
    { bios => 785, X =>  640, Y =>  480, Depth => 16 },
    { bios => 788, X =>  800, Y =>  600, Depth => 16 },
    { bios => 791, X => 1024, Y =>  768, Depth => 16 },
    { bios => 794, X => 1280, Y => 1024, Depth => 16 },
);

sub size2default_resolution {
    my ($size) = @_; #- size in inch

    if (arch() =~ /ppc/) {
     require detect_devices;
	return "1024x768" if detect_devices::get_mac_model() =~ /^PowerBook|^iMac/;
    }

    my %monitorSize2resolution = (
	13 => "640x480",
	14 => "800x600",
	15 => "800x600",
	16 => "1024x768",
	17 => "1024x768",
	18 => "1024x768",
	19 => "1280x1024",
	20 => "1280x1024",
	21 => "1600x1200",
	22 => "1600x1200",
    );
    $monitorSize2resolution{round($size)} || ($size < 13 ? "640x480" : "1600x1200");
}

sub to_string {
    my ($resolution) = @_;
    $resolution or return;

    sprintf("%sx%s %dbpp", @$resolution{'X', 'Y', 'Depth'});
}

sub allowed {
    my ($card) = @_;

    my ($prefered_depth, @depths, @resolutions, @resolution_and_depth);
    
    my $using_xf4 = Xconfig::card::using_xf4($card);

    if ($using_xf4 ? $card->{Driver} eq 'fbdev' : $card->{server} eq 'FBDev') {
	push @resolution_and_depth, grep { $_->{Depth} == 16 } @bios_vga_modes;
    } elsif ($using_xf4) {
	if ($card->{use_DRI_GLX} || $card->{use_UTAH_GLX}) {
	    $prefered_depth = 16;
	    push @depths, 16;
	    push @depths, 24 if member($card->{Driver}, 'mga', 'tdfx', 'r128', 'radeon');
	}
    } else {
	   if ($card->{server} eq 'Sun24')   { push @depths, 24, 8, 2 }
	elsif ($card->{server} eq 'Sun')     { push @depths, 8, 2 }
	elsif ($card->{server} eq 'SunMono') { push @depths, 2 }
	elsif ($card->{server} eq 'VGA16')   { push @depths, 8; push @resolutions, '640x480' }
        elsif ($card->{BoardName} =~ /SiS/)  { push @depths, 24, 16, 8 }
        elsif ($card->{BoardName} eq 'S3 Trio3D') { push @depths, 24, 16, 8 }
    }
    if (!@resolution_and_depth || @depths || @resolutions) {
	@depths = grep { !($using_xf4 && /32/) } (our @depths_available) if !@depths;
	@resolutions = @Xconfig::xfreeX::resolutions if !@resolutions;

	push @resolution_and_depth,
	  map {
	      my $Depth = $_;
	      map { m/(\d+)x(\d+)/; { X => $1, Y => $2, Depth => $Depth } } @resolutions;
	  } @depths;
    }
    $prefered_depth, @resolution_and_depth;
}

# ($card->{VideoRam} || ($card->{server} eq 'FBDev' ? 2048 : 32768))
sub filter_using_VideoRam {
    my ($VideoRam, @resolutions) = @_;
    my $mem = 1024 * $VideoRam;
    grep { $_->{X} * $_->{Y} * $_->{Depth}/8 <= $mem } @resolutions;
    
}
sub filter_using_HorizSync {
    my ($HorizSync, @resolutions) = @_;
    my $hsync = max(split(/[,-]/, $HorizSync));
    grep { ($min_hsync4x_res{$_->{X}} || 0) <= $hsync } @resolutions;
}

sub choose {
    my ($in, $default_resolution, @resolutions) = @_;

    my $resolution = $default_resolution || {};
    $in->ask_from(N("Resolutions"), "",
		  [ {
		     val => \$resolution, type => 'list', sort => 0,
		     list => [ sort { $a->{X} <=> $b->{X} } @resolutions ],
		     format => sub { "$_[0]{X}x$_[0]{Y} $_[0]{Depth}bpp" },
		    } ])
      and $resolution;
}


sub choices {
    my ($_raw_X, $resolution_wanted, $card, $monitor) = @_;
    $resolution_wanted ||= {};

    my ($prefered_depth, @resolutions) = allowed($card);

    @resolutions = filter_using_HorizSync($monitor->{HorizSync}, @resolutions) if $monitor->{HorizSync};
    @resolutions = filter_using_VideoRam($card->{VideoRam}, @resolutions) if $card->{VideoRam};

    my $x_res = do {
	my $res = $resolution_wanted->{X} || ($monitor->{ModelName} =~ /^Flat Panel (\d+x\d+)$/ ? $1 : size2default_resolution($monitor->{size} || 14));
	my $x_res = first(split 'x', $res);
	#- take the first available resolution <= the wanted resolution
	max map { if_($_->{X} <= $x_res, $_->{X}) } @resolutions;
    };

    my @matching = grep { $_->{X} eq $x_res } @resolutions;
    my @Depths = map { $_->{Depth} } @matching;

    my $Depth = $resolution_wanted->{Depth};
    $Depth = $prefered_depth if !$Depth || !member($Depth, @Depths);
    $Depth = max(@Depths)    if !$Depth || !member($Depth, @Depths);

    #- finding it in @resolutions (well @matching)
    #- (that way, we check it exists, and we get field "bios" for fbdev)
    my @default_resolutions = sort { $b->{Y} <=> $a->{Y} } grep { $_->{Depth} eq $Depth } @matching;
    my $default_resolution = (find { $resolution_wanted->{Y} eq $_->{Y} } @default_resolutions) || $default_resolutions[0];

    $default_resolution, @resolutions;
}

sub configure {
    my ($in, $raw_X, $card, $monitor) = @_;

    my ($default_resolution, @resolutions) = choices($raw_X, $raw_X->get_resolution, $card, $monitor);

    if ($in->isa('interactive::gtk')) {
	$default_resolution = choose_gtk($card, $default_resolution, @resolutions) or return;
    } else {
	$default_resolution = choose($in, $default_resolution, @resolutions) or return;
    }
    $raw_X->set_resolution($default_resolution);

    $default_resolution;
}

sub configure_auto_install {
    my ($raw_X, $card, $monitor, $old_X) = @_;

    my $resolution_wanted = { X => $old_X->{resolution_wanted}, Depth => $old_X->{default_depth} };

    my ($default_resolution) = choices($raw_X, $resolution_wanted, $card, $monitor);
    $default_resolution or die "you selected an unusable depth";

    $raw_X->set_resolution($default_resolution);

    $default_resolution;
}

sub choose_gtk {
    my ($card, $default_resolution, @resolutions) = @_;

    my ($chosen_x_res, $chosen_y_res, $chosen_Depth) = @$default_resolution{'X', 'Y', 'Depth'};
    $chosen_x_res ||= 640;

    my %x_res2depth; push @{$x_res2depth{$_->{X}}}, $_->{Depth} foreach @resolutions;
    my %depth2x_res; push @{$depth2x_res{$_->{Depth}}}, $_->{X} foreach @resolutions;

    require ugtk2;
    ugtk2->import(qw(:create :helpers :wrappers));
    my $W = ugtk2->new(N("Resolution"));

    my %monitor_images_x_res = do {
	my @l = qw(640 800 1024 1152 1280 1400 1600 1920 2048);
	my %h = map { $_ => gtkcreate_img("monitor-$_.png") } @l;

	#- for the other, use the biggest smaller
	foreach my $x_res (uniq map { $_->{X} } @resolutions) {
	    my $x_res_ = max(grep { $_ <= $x_res } @l);
	    $h{$x_res} ||= $h{$x_res_};
	}
	%h;
    };

    my ($depth_combo, $x_res_combo);

    my $pix_colors = gtkcreate_img("colors");
    my $set_chosen_Depth_image = sub {
	$pix_colors = gtkcreate_img(
               $chosen_Depth >= 24 ? "colors.png" :
	       $chosen_Depth >= 15 ? "colors16.png" : "colors8.png");
    };

    my $set_chosen_Depth = sub {
	$chosen_Depth = $_[0];
	$depth_combo->entry->set_text(translate($depth2text{$chosen_Depth}));
	$set_chosen_Depth_image->();
    };

    my $pixmap_mo;
    my $set_chosen_x_res = sub {
	$chosen_x_res = $_[0];
	if ($_[1]) {
	    $chosen_y_res = $_[1];
	} else {
	    #- take one
	    my $one = find { $_->{X} eq $chosen_x_res } @resolutions;
	    $chosen_y_res = $one->{Y};
	}
	my $image = $monitor_images_x_res{$chosen_x_res} or internal_error("no image for resolution $chosen_x_res");
	$pixmap_mo = $image;
    };
    $set_chosen_x_res->($chosen_x_res, $chosen_y_res);

    gtkadd($W->{window},
	   gtkpack_($W->create_box_with_title(N("Choose the resolution and the color depth"),
					      if_($card->{BoardName}, "(" . N("Graphics card: %s", $card->{BoardName}) . ")"),
					     ),
		    1, gtkpack2(new Gtk2::VBox(0,0),
				gtkpack2__(new Gtk2::VBox(0, 15),
					   $pixmap_mo,
					   gtkpack2(new Gtk2::HBox(0,0),
						    create_packtable({ col_spacings => 5, row_spacings => 5 },
	     [ $x_res_combo = new Gtk2::Combo, new Gtk2::Label("") ],
	     [ $depth_combo = new Gtk2::Combo, gtkadd(gtkset_shadow_type(new Gtk2::Frame, 'etched_out'), $pix_colors) ],
							     ),
						   ),
					  ),
			       ),
		    0, gtkadd($W->create_okcancel(N("Ok"), N("Cancel"))),
		    ));
    $depth_combo->disable_activate;
    $depth_combo->set_use_arrows_always(1);
    $depth_combo->entry->set_editable(0);
    $depth_combo->set_popdown_strings(map { translate($depth2text{$_}) } ikeys %depth2x_res);
    $depth_combo->entry->set_size_request(220, -1);
    $depth_combo->entry->signal_connect(changed => sub {
	$depth_combo->entry->get_text eq '' and return;  #- FIXME temporarily workaround gtk suckiness (set_text generates two 'change' signals, one when removing the whole, one for inserting the replacement..)
        my %txt2depth = reverse %depth2text;
	my $s = $depth_combo->entry->get_text;
        $chosen_Depth = $txt2depth{untranslate($s, keys %txt2depth)};
	$set_chosen_Depth_image->();

	if (!member($chosen_x_res, @{$depth2x_res{$chosen_Depth}})) {
	    $set_chosen_x_res->(max(@{$depth2x_res{$chosen_Depth}}));
	}
    });
    $x_res_combo->disable_activate;
    $x_res_combo->set_use_arrows_always(1);
    $x_res_combo->entry->set_editable(0);
    $x_res_combo->set_popdown_strings(uniq map { "$_->{X}x$_->{Y}" } sort { $a->{X} <=> $b->{X} } @resolutions);
    $x_res_combo->entry->signal_connect(changed => sub {
	$x_res_combo->entry->get_text eq '' and return;  #- FIXME temporarily workaround gtk suckiness (set_text generates two 'change' signals, one when removing the whole, one for inserting the replacement..)
	$x_res_combo->entry->get_text =~ /(\d+)x(\d+)/;
	$set_chosen_x_res->($1, $2);
	
	if (!member($chosen_Depth, @{$x_res2depth{$chosen_x_res}})) {
	    $set_chosen_Depth->(max(@{$x_res2depth{$chosen_x_res}}));
	}
    });
    $set_chosen_Depth->($chosen_Depth);
    $W->{ok}->grab_focus;

    $x_res_combo->entry->set_text($chosen_x_res . "x" . $chosen_y_res);
    $W->main or return;

    find { $_->{X} == $chosen_x_res && 
	   $_->{Y} == $chosen_y_res && 
	   $_->{Depth} == $chosen_Depth } @resolutions);
}

1;
