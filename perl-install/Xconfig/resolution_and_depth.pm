package Xconfig::resolution_and_depth; # $Id$

use diagnostics;
use strict;

use common;


our %depth2text = (
      8 => N_("256 colors (8 bits)"),
     15 => N_("32 thousand colors (15 bits)"),
     16 => N_("65 thousand colors (16 bits)"),
     24 => N_("16 million colors (24 bits)"),
);
our @depths_available = ikeys(%depth2text);

my @bios_vga_modes = (
    { bios => 769, X =>  640, Y =>  480, Depth =>  8 },
    { bios => 771, X =>  800, Y =>  600, Depth =>  8 },
    { bios => 773, X => 1024, Y =>  768, Depth =>  8 },
    { bios => 775, X => 1280, Y => 1024, Depth =>  8 },
    { bios => 777, X => 1600, Y => 1200, Depth =>  8 }, 
    { bios => 784, X =>  640, Y =>  480, Depth => 15 },
    { bios => 787, X =>  800, Y =>  600, Depth => 15 },
    { bios => 790, X => 1024, Y =>  768, Depth => 15 },
    { bios => 793, X => 1280, Y => 1024, Depth => 15 },
    { bios => 796, X => 1600, Y => 1200, Depth => 15 }, 
    { bios => 785, X =>  640, Y =>  480, Depth => 16 },
    { bios => 788, X =>  800, Y =>  600, Depth => 16 },
    { bios => 791, X => 1024, Y =>  768, Depth => 16 },
    { bios => 794, X => 1280, Y => 1024, Depth => 16 },
    { bios => 797, X => 1600, Y => 1200, Depth => 16 }, 
);

sub from_bios {
    my ($bios) = @_;
    find { $_->{bios} == $bios } @bios_vga_modes;
}

sub bios_vga_modes() { @bios_vga_modes }

sub size2default_resolution {
    my ($size) = @_; #- size in inch

    require detect_devices;
    if (arch() =~ /ppc/) {
	return "1024x768" if detect_devices::get_mac_model() =~ /^PowerBook|^iMac/;
    } elsif (detect_devices::is_xbox()) {
	return "640x480";
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
    $resolution or return '';

    $resolution->{X} ? sprintf("%sx%s %dbpp", @$resolution{'X', 'Y', 'Depth'}) : 'frame-buffer';
}

sub allowed {
    my ($card) = @_;

    my ($prefered_depth, @resolution_and_depth);
    
    if ($card->{Driver} eq 'fbdev') {
	@resolution_and_depth = grep { $_->{Depth} == 16 } @bios_vga_modes;
    } else {
	my @depths;
	if ($card->{Driver} eq 'fglrx') {
	    @depths = 24;
	} elsif ($card->{BoardName} eq 'RIVA128') { 
	    @depths = qw(8 15 24);
	} elsif ($card->{use_DRI_GLX}) {
	    $prefered_depth = 16;
	    @depths = (16, 24);
	} else {
	    @depths = our @depths_available;
	}
	my @resolutions = @Xconfig::xfree::resolutions;

	push @resolution_and_depth,
	  map {
	      my $Depth = $_;
	      map { m/(\d+)x(\d+)/ && { X => $1, Y => $2, Depth => $Depth } } @resolutions;
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
sub filter_using_HorizSync_VertRefresh {
    my ($HorizSync, $VertRefresh, @resolutions) = @_;
    my $max_hsync = 1000 * max(split(/[,-]/, $HorizSync));
    my ($min_vsync, $max_vsync) = (min(split(/[,-]/, $VertRefresh)), max(split(/[,-]/, $VertRefresh)));

    #- enforce at least 60Hz, if max_vsync > 100 (ie don't do it on LCDs which are ok with low vsync)
    $min_vsync = max(60, $min_vsync) if $max_vsync > 100;

    #- computing with {Y} which is active sync instead of total sync, but that's ok
    grep { $max_hsync / $_->{Y} > $min_vsync } @resolutions;
}

sub choose {
    my ($in, $default_resolution, @resolutions) = @_;

    my $resolution = $default_resolution || {};
    $in->ask_from(N("Resolutions"), "",
		  [ {
		     val => \$resolution, type => 'list', sort => 0,
		     list => [ sort { $a->{X} <=> $b->{X} } @resolutions ],
		     format => \&to_string,
		    } ]) or return;
    $resolution;
}


sub choices {
    my ($_raw_X, $resolution_wanted, $card, $monitors) = @_;
    $resolution_wanted ||= {};

    my ($prefered_depth, @resolutions) = allowed($card);

    @resolutions = filter_using_HorizSync_VertRefresh($monitors->[0]{HorizSync}, $monitors->[0]{VertRefresh}, @resolutions) if $monitors->[0]{HorizSync};
    @resolutions = filter_using_VideoRam($card->{VideoRam}, @resolutions) if $card->{VideoRam};

    #- sort it, so we can take the first one when we want the "best"
    @resolutions = sort { $b->{X} <=> $a->{X} || $b->{Y} <=> $a->{Y} || $b->{Depth} <=> $a->{Depth} } @resolutions;

    if ($resolution_wanted->{X} && !$resolution_wanted->{Y}) {
	#- assuming ratio 4/3
	$resolution_wanted->{Y} = round($resolution_wanted->{X} * 3 / 4);
    } elsif (!$resolution_wanted->{X}) {
	if ($monitors->[0]{preferred_resolution}) {
	    put_in_hash($resolution_wanted, $monitors->[0]{preferred_resolution});
	} elsif ($monitors->[0]{ModelName} =~ /^Flat Panel (\d+)x(\d+)$/) {
	    put_in_hash($resolution_wanted, { X => $1, Y => $2 });
	} else {
	    my ($X, $Y) = split('x', size2default_resolution($monitors->[0]{diagonal_size} * 1.08 || 14));
	    put_in_hash($resolution_wanted, { X => $X, Y => $Y });
	}
    }
    my @matching = grep { $_->{X} eq $resolution_wanted->{X} && $_->{Y} eq $resolution_wanted->{Y} } @resolutions;
    if (!@matching) {
	#- hard choice :-(
	#- first trying the greater resolution with same ratio
	my $ratio = $resolution_wanted->{X} / $resolution_wanted->{Y};
	@matching = grep { abs($ratio - $_->{X} / $_->{Y}) < 0.01 } @resolutions;
    }
    if (!@matching) {
	#- really hard choice :'-(
	#- take the first available resolution <= the wanted resolution
	@matching = grep { $_->{X} < $resolution_wanted->{X} } @resolutions;
    }
    if (!@matching) {
	@matching = @resolutions;
    }

    my $default_resolution;
    foreach my $Depth ($resolution_wanted->{Depth}, $prefered_depth) {
	$Depth and $default_resolution ||= find { $_->{Depth} eq $Depth } @matching;
    }
    $default_resolution ||= $matching[0];

    $default_resolution, @resolutions;
}

sub configure {
    my ($in, $raw_X, $card, $monitors, $b_auto) = @_;

    my ($default_resolution, @resolutions) = choices($raw_X, $raw_X->get_resolution, $card, $monitors);

    if ($b_auto) {
	#- use $default_resolution
	if ($card->{Driver} eq 'fglrx') {
	    $default_resolution = first(find { $default_resolution->{Y} eq $_->{Y} && $_->{Depth} == 24 }
					$default_resolution, @resolutions);
	    $default_resolution ||= first(find { $_->{Depth} == 24 } $default_resolution, @resolutions);
	}
    } elsif ($in->isa('interactive::gtk')) {
	$default_resolution = choose_gtk($in, $card, $default_resolution, @resolutions) or return;
    } else {
	$default_resolution = choose($in, $default_resolution, @resolutions) or return;
    }
    set_resolution($raw_X, $default_resolution);

    $default_resolution;
}

sub configure_auto_install {
    my ($raw_X, $card, $monitors, $old_X) = @_;

    my $resolution_wanted = do {
	my ($X, $Y) = split('x', $old_X->{resolution_wanted});
	{ X => $X, Y => $Y, Depth => $old_X->{default_depth} };
    };

    my ($default_resolution) = choices($raw_X, $resolution_wanted, $card, $monitors);
    $default_resolution or die "you selected an unusable depth";

    set_resolution($raw_X, $default_resolution);

    $default_resolution;
}

sub set_resolution {
    my ($raw_X, $resolution) = @_; 
    $raw_X->set_resolution($resolution);
    set_default_background($resolution);
}
sub set_default_background {
    my ($resolution) = @_;

    my $ratio = $resolution->{X} / $resolution->{Y};
    my $dir = "$::prefix/usr/share/mdk/backgrounds";
    my %theme = getVarsFromSh('/etc/sysconfig/bootsplash');
    my @l = 
      sort {
	  $a->[1] <=> $b->[1] || $b->[2] <=> $a->[2] || $a->[3] <=> $b->[3];
      } map {
	  if (my ($X, $Y) = /^$theme{THEME}-(\d+)x(\d+).png$/) {
	      [
		  $_, 
		  int(abs($ratio - $X / $Y) * 100), #- we want the nearest ratio (precision .01)
		  $X >= $resolution->{X}, #- then we don't want a resolution smaller
		  abs($X - $resolution->{X}), #- the nearest resolution
	      ];
	  } else { () }
      } all($dir);

    symlinkf $l[0][0], "$dir/default.png";
}

sub resolution2ratio {
    my ($resolution, $b_non_strict) = @_;
    my $res = $resolution->{X} . 'x' . $resolution->{Y};
    $res eq '1280x1024' && $b_non_strict ? '4/3' : $Xconfig::xfree::resolution2ratio{$res};
}

sub choose_gtk {
    my ($in, $card, $default_resolution, @resolutions) = @_;

    $_->{ratio} ||= resolution2ratio($_) foreach @resolutions;

    my $chosen_Depth = $default_resolution->{Depth};
    my $chosen_res = { X => $default_resolution->{X} || 1024, Y => $default_resolution->{Y} };
    my $chosen_ratio = resolution2ratio($chosen_res, 'non-strict') || '4/3';

    my $filter_on_ratio = sub {
	grep {
	    !$chosen_ratio
	      || $_->{ratio} eq $chosen_ratio 
	      || $chosen_ratio eq '4/3' && "$_->{X}x$_->{Y}" eq '1280x1024';
	} @_;
    };
    my $filter_on_Depth = sub {
	grep { $_->{Depth} == $chosen_Depth } @_;
    };
    my $filter_on_res = sub {
	grep { $_->{X} == $chosen_res->{X} && $_->{Y} == $chosen_res->{Y} } @_;
    };
    #- $chosen_res must be one of @resolutions, so that it has a correct {ratio} field
    $chosen_res = first($filter_on_res->(@resolutions)) || $resolutions[0];

    require ugtk2;
    mygtk2->import;
    ugtk2->import(qw(:create :helpers :wrappers));
    my $W = ugtk2->new(N("Resolution"), modal => 1);

    my %monitor_images_x_res = do {
	my @l = qw(640 800 1024 1152 1280 1400 1600 1920 2048);
	my %h = map { $_ => ugtk2::_find_imgfile("monitor-$_.png") } @l;

	#- for the other, use the biggest smaller
	foreach my $x_res (uniq map { $_->{X} } @resolutions) {
	    my $x_res_ = max(grep { $_ <= $x_res } @l);
	    $h{$x_res} ||= $h{$x_res_} || $h{640};
	}
	%h;
    };

    my $res2text = sub { "$_[0]{X}x$_[0]{Y}" . ($chosen_ratio || $_[0]{ratio} =~ /other/ ? '' : "  ($_[0]{ratio})") };
    my @matching_ratio;
    my $proposed_resolutions = [];
    my $set_proposed_resolutions = sub {
	my ($suggested_res) = @_;
	@matching_ratio = $filter_on_ratio->(@resolutions);
	gtkval_modify(\$proposed_resolutions, [ 
	    (reverse uniq_ { $res2text->($_) } @matching_ratio),
	    if_($chosen_ratio, { text => N_("Other") }),
	]);
	if (!$filter_on_res->(@matching_ratio)) {
	    my $res = $suggested_res || find { $_->{X} == $chosen_res->{X} } @matching_ratio;
	    gtkval_modify(\$chosen_res, $res || $matching_ratio[0]);
	}
    };
    $set_proposed_resolutions->();

    my $depth_combo = gtknew('ComboBox', width => 220, 
			     text_ref => \$chosen_Depth,
			     format => sub { translate($depth2text{$_[0]}) },
			     list => [ uniq(reverse map { $_->{Depth} } @resolutions) ],
			     changed => sub {
				 my @matching_Depth = $filter_on_Depth->(@matching_ratio);
				 if (!$filter_on_res->(@matching_Depth)) {
				     gtkval_modify(\$chosen_res, $matching_Depth[0]);
				 }
			     });
    my $previous_res = $chosen_res;
    my $res_combo = gtknew('ComboBox', 
			   text_ref => \$chosen_res,
			   format => sub { $_[0]{text} ? translate($_[0]{text}) : &$res2text },
			   list_ref => \$proposed_resolutions,
			   changed => sub {
			       if ($chosen_res->{text}) {
				   undef $chosen_ratio;
				   $set_proposed_resolutions->($previous_res);
			       } else {
				   my @matching_res = $filter_on_res->(@matching_ratio);
				   if (!$filter_on_Depth->(@matching_res)) {
				       gtkval_modify(\$chosen_Depth, $matching_res[0]{Depth});
				   }
				   $previous_res = $chosen_res;
			       }
			   });
    my $pix_colors = gtknew('Image', 
			    file_ref => \$chosen_Depth,
			    format => sub {
				$_[0] >= 24 ? "colors.png" : $_[0] >= 15 ? "colors16.png" : "colors8.png";
			    });
    my $pixmap_mo = gtknew('Image', 
			   file_ref => \$chosen_res,
			   format => sub {
			       $monitor_images_x_res{$_[0]{X}} or internal_error("no image for resolution $chosen_res->{X}");
			   });

    my $help_sub = $in->interactive_help_sub_display_id('configureX_resolution');
    gtkadd($W->{window},
	   gtkpack_($W->create_box_with_title(N("Choose the resolution and the color depth"),
					      if_($card->{BoardName}, "(" . N("Graphics card: %s", $card->{BoardName}) . ")"),
					     ),
		    1, '',
		    0, $pixmap_mo,
		    0, gtknew('HBox', children => [
			  1, '',
			  0, gtknew('Table', col_spacings => 5, row_spacings => 5, 
				    children => [
						 [ $res_combo, gtknew('Label', text => "") ],
						 [ $depth_combo, gtknew('Frame', shadow_type => 'etched_out', child => $pix_colors) ],
						]),
			  1, '',
		       ]),
	            1, '',
		    0, gtkadd($W->create_okcancel(N("Ok"), N("Cancel"), '', if_($help_sub, [ N("Help"), $help_sub, 1 ]))),
		    ));
    $W->{ok}->grab_focus;

    $W->main or return;

    find { $_->{X} == $chosen_res->{X} && 
	   $_->{Y} == $chosen_res->{Y} && 
	   $_->{Depth} == $chosen_Depth } @resolutions;
}

1;
