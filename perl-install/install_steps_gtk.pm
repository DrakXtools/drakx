package install_steps_gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive::gtk);

#-######################################################################################
#- misc imports
#-######################################################################################
use pkgs;
use install_steps_interactive;
use interactive::gtk;
use common;
use my_gtk qw(:helpers :wrappers);
use Gtk;
use devices;
use modules;
use install_gtk;
use install_any;
use mouse;
use help;
use log;

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    my $old = $SIG{__DIE__};
    $SIG{__DIE__} = sub { $_[0] !~ /my_gtk\.pm/ and goto $old };

    $ENV{DISPLAY} ||= $o->{display} || ":0";
    unless ($::testing) {
	if ($ENV{DISPLAY} eq ":0" && !$::live) {
	    my $f = "/tmp/Xconf";
	    install_gtk::createXconf($f, @{$o->{mouse}}{"XMOUSETYPE", "device"}, $o->{mouse}{wacom}[0]);
	    devices::make("/dev/kbd");

	    local (*T1, *T2);
	    open T1, ">/dev/tty5";
	    open T2, ">/dev/tty6";

	    my $launchX = sub {
		my $ok = 1;
		my $xpmac_opts = cat_("/proc/cmdline");
		unless (-d "/var/log") { mkdir("/var/log") }
		local $SIG{CHLD} = sub { $ok = 0 if waitpid(-1, c::WNOHANG()) > 0 };
		unless (fork) {
		    exec $_[0], (arch() =~ /^sparc/ || arch() eq "ppc" ? () : ("-kb")), "-dpms","-s" ,"240",
		      ($_[0] =~ /Xpmac/ ? $xpmac_opts !~ /ofonly/ ? ("-mode", "17", "-depth", "32") : ("-mach64"):()),
		      ($_[0] =~ /Xsun/ || $_[0] =~ /Xpmac/ ? ("-fp", "/usr/X11R6/lib/X11/fonts:unscaled") :
		       ("-allowMouseOpenFail", "-xf86config", $f)) or exit 1;
		}
		foreach (1..60) {
		    sleep 1;
		    log::l("Server died"), return 0 if !$ok;
		    if (c::Xtest($ENV{DISPLAY})) {
			fork || exec("aewm-drakx") || exec("true");
			return 1;
		    }
		}
		log::l("Timeout!!");
		0;
	    };
	    my @servers = qw(FBDev VGA16); #-)
	    if (arch() eq "alpha") {
		require Xconfig::card;
		my ($card) = Xconfig::card::probe();
		Xconfig::card::add_to_card__using_Cards($card, $card->{type}) if $card && $card->{type};
		@servers = $card->{server} || "TGA";
		#-@servers = qw(SVGA 3DLabs TGA) 
	    } elsif (arch() =~ /^sparc/) {
		local $_ = cat_("/proc/fb");
		if (/Mach64/) { @servers = qw(Mach64) }
		elsif (/Permedia2/) { @servers = qw(3DLabs) }
		else { @servers = qw(Xsun24) }
	    } elsif (arch() =~ /ia64/) {
		@servers = 'XFree86';
	    } elsif (arch() eq "ppc") {
	    	@servers = qw(Xpmac);
            }

	    foreach (@servers) {
		log::l("Trying with server $_");
		my $dir = "/usr/X11R6/bin";
		my $prog = /Xsun|Xpmac|XFree86/ ? $_ : "XF86_$_";
		unless (-x "$dir/$prog") {
		    unlink $_ foreach glob_("$dir/X*");
		    install_any::getAndSaveFile("Mandrake/mdkinst$dir/$prog", "$dir/$prog") or die "failed to get server $prog: $!";
		    chmod 0755, "$dir/$prog";
		}
		if (/FB/) {
		    !$o->{vga16} && $o->{allowFB} or next;

		    $o->{allowFB} = &$launchX($prog) #- keep in mind FB is used.
		      and goto OK;
		} else {
		    $o->{vga16} = 1 if /VGA16/;
		    &$launchX($prog) and goto OK;
		}
	    }
	    return undef;
	}
    }
  OK:
    install_gtk::init_sizes();
    install_gtk::install_theme($o, install_gtk::default_theme($o));
    install_gtk::create_logo_window($o);

    $my_gtk::force_center = [ $::rootwidth - $::windowwidth, $::logoheight, $::windowwidth, $::windowheight ];

    $o = (bless {}, ref $type || $type)->SUPER::new($o);
    $o->interactive::gtk::new;
    $o;
}

sub enteringStep {
    my ($o, $step) = @_;

    printf "Entering step `%s'\n", $o->{steps}{$step}{text};
    $o->SUPER::enteringStep($step);
    install_gtk::create_steps_window($o);
    install_gtk::create_help_window($o); #- HACK: without this it doesn't work (reaches step doPartitionDisks then fail)
    $o->set_help($o->{step});
}
sub leavingStep {
    my ($o, $step) = @_;
    $o->SUPER::leavingStep($step);
}


sub charsetChanged {
    my ($o) = @_;
    Gtk->set_locale;
    install_gtk::install_theme($o);
    install_gtk::create_steps_window($o);
}

#-######################################################################################
#- Steps Functions
#-######################################################################################
sub selectLanguage {
    my ($o, $first_time) = @_;
    $o->SUPER::selectLanguage;
  
    $o->ask_warn('',
_("Your system is low on resources. You may have some problem installing
Mandrake Linux. If that occurs, you can try a text install instead. For this,
press `F1' when booting on CDROM, then enter `text'.")) if $first_time && availableRamMB() < 60; # 60MB

}

#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;
    $::live || @$l == 1 || !@$l2 and return $o->SUPER::selectInstallClass1($verif, $l, $def, $l2, $def2);

    my $w = my_gtk->new(_("Install Class"));
    my $focused;
    gtkadd($w->{window},
	   gtkpack($w->create_box_with_title(_("Please choose one of the following classes of installation:")),
		   (my @radios = gtkradio($def, @$l)),
		   gtkadd(create_vbox(),
			  map { my $v = $_; 
				my $b = new Gtk::Button(translate($_));
				$focused = $b if $_ eq $def2;
				gtksignal_connect($b, "clicked" => sub { $w->{retval} = $v; Gtk->main_quit });
			    } @$l2)
		  ));
    $focused->grab_focus if $focused;
    $w->main;

    mapn { $verif->($_[1]) if $_[0]->active } \@radios, $l;
    install_gtk::create_steps_window($o);

    $w->{retval};
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;
    my %old = %{$o->{mouse}};
    $o->SUPER::selectMouse($force) or return;
    my $mouse = $o->{mouse};
    $mouse->{type} eq 'none' ||
      $old{type}   eq $mouse->{type}   && 
      $old{name}   eq $mouse->{name}   &&
      $old{device} eq $mouse->{device} && !$force and return;

    local $my_gtk::grab = 1; #- unsure a crazy mouse don't go wild clicking everywhere

    while (1) {
	log::l("telling X server to use another mouse");
	eval { modules::load('serial') } if $mouse->{device} =~ /ttyS/;

	if (!$::testing) {
	    devices::make($mouse->{device});
	    symlinkf($mouse->{device}, "/dev/mouse");
	    c::setMouseLive($ENV{DISPLAY}, mouse::xmouse2xId($mouse->{XMOUSETYPE}), $mouse->{nbuttons} < 3);
	}
	mouse::test_mouse_install($mouse) and return;
	$o->SUPER::selectMouse(1);
	$mouse = $o->{mouse};
    } 
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $val) = @_;

    my $w = my_gtk->new('');
    my $tips = new Gtk::Tooltips;
    my $w_size = new Gtk::Label(&$size_to_display);

    my $entry = sub {
	my ($e) = @_;
	my $text = translate($o->{compssUsers}{$e}{label});
	my $help = translate($o->{compssUsers}{$e}{descr});

	my $check = Gtk::CheckButton->new($text);
	$check->set_active($val->{$e});
	$check->signal_connect(clicked => sub { 
	    $val->{$e} = $check->get_active;
	    $w_size->set(&$size_to_display);
	});
	gtkset_tip($tips, $check, $help);
	#gtkpack_(new Gtk::HBox(0,0), 0, gtkpng($file), 1, $check);
	$check;
    };
    my $entries_in_path = sub {
	my ($path) = @_;
	translate($path), map { $entry->($_) } grep { $o->{compssUsers}{$_}{path} eq $path } @{$o->{compssUsersSorted}};
    };
    gtkadd($w->{window},
	   gtkpack($w->create_box_with_title(_("Package Group Selection")),
		   gtkpack_(new Gtk::VBox(0,0),
			   1, gtkpack_(new Gtk::HBox(0,0),
			        $o->{meta_class} eq 'server' ? (
				   1, gtkpack(new Gtk::VBox(0,0), 
					   $entries_in_path->('Server'),
					  ),
				   1, gtkpack(new Gtk::VBox(0,0), 
					   $entries_in_path->('Graphical Environment'),
					   '',
					   $entries_in_path->('Development'),
					   '',
					   $entries_in_path->('Utilities'),
					  ),
				) : (
				   1, gtkpack(new Gtk::VBox(0,0), 
					   $entries_in_path->('Workstation'),
					   '',
					   $entry->('Development|Development'),
					   $entry->('Development|Documentation'),
					   $entry->('Development|LSB'),
					  ),
				   0, gtkpack(new Gtk::VBox(0,0), 
					   $entries_in_path->('Server'),
					   '',
					   $entries_in_path->('Graphical Environment'),
					  ),
				),
			   )),
		   '',
		   gtkadd(new Gtk::HBox(0,0),
			  $w_size,
			  if_($individual, do {
			      my $check = Gtk::CheckButton->new(_("Individual package selection"));
			      $check->set_active($$individual);
			      $check->signal_connect(clicked => sub { $$individual = $check->get_active });
			      $check;
			  }),
			  gtksignal_connect(new Gtk::Button(_("Ok")), clicked => sub { Gtk->main_quit }),
			 ),
		  ),
	  );
    $w->{rwindow}->set_default_size($::windowwidth * 0.8, $::windowheight * 0.8);
    $w->main;
    1;    
}


sub choosePackagesTree {
    my ($o, $packages, $limit_to_medium) = @_;

    my $available = install_any::getAvailableSpace($o);
    my $availableCorrected = pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);

    my $common; $common = { get_status => sub {
				my $size = pkgs::selectedSize($packages);
				_("Total size: %d / %d MB", pkgs::correctSize($size / sqr(1024)), $available / sqr(1024));
			    },
			    node_state => sub {
				my $p = pkgs::packageByName($packages,$_[0]) or return;
				pkgs::packageMedium($packages, $p)->{selected} or return;
				$p->flag_base                           and return 'base';
				$p->flag_installed && !$p->flag_upgrade and return 'installed';
				$p->flag_selected                       and return 'selected';
				return 'unselected';
			    },
			    build_tree => sub {
				my ($add_node, $flat) = @_;
				if ($flat) {
				    foreach (sort map { $_->name } grep { !$limit_to_medium || pkgs::packageMedium($packages, $_) }
					     @{$packages->{depslist}}) {
					$add_node->($_, undef);
				    }
				} else {
				    foreach my $root (@{$o->{compssUsersSorted}}) {
					my (%fl, @firstchoice, @others);
					#$fl{$_} = $o->{compssUsersChoice}{$_} foreach @{$o->{compssUsers}{$root}{flags}}; #- FEATURE:improve choce of packages...
					$fl{$_} = 1 foreach @{$o->{compssUsers}{$root}{flags}};
					foreach my $p (@{$packages->{depslist}}) {
					    !$limit_to_medium || pkgs::packageMedium($packages, $p) == $limit_to_medium or next;
					    my @flags = $p->rflags;
					    next if !($p->rate && grep { grep { !/^!/ && $fl{$_} } split('\|\|') } @flags);
					    $p->rate >= 3 ?
					      push(@firstchoice, $p->name) :
						push(@others,    $p->name);
					}
					my $root2 = join('|', map { translate($_) } split('\|', $root));
					$add_node->($_, $root2)                    foreach sort @firstchoice;
					$add_node->($_, $root2 . '|' . _("Other")) foreach sort @others;
				    }
				}
			    },
			    get_info => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return '';
				pkgs::extractHeaders($o->{prefix}, [$p], $packages->{mediums});

				my $imp = translate($pkgs::compssListDesc{$p->flag_base ? 5 : $p->rate});

				my $info = $@ ? _("Bad package") :
				  (_("Name: %s\n", $p->name) .
				   _("Version: %s\n", $p->version . '-' . $p->release) .
				   _("Size: %d KB\n", $p->size / 1024) .
				   ($imp && _("Importance: %s\n", $imp)) . "\n" .
				   formatLines($p->description));
				return $info;
			    },
			    toggle_nodes => sub {
				my $set_state = shift @_;
				my @n = map { pkgs::packageByName($packages, $_) } @_;
				my %l;
				my $isSelection = !$n[0]->flag_selected;
				foreach (@n) {
				    #pkgs::togglePackageSelection($packages, $_, my $l = {});
				    #@l{grep {$l->{$_}} keys %$l} = ();
				    pkgs::togglePackageSelection($packages, $_, \%l);
				}
				if (my @l = map { $packages->{depslist}[$_]->name } keys %l) {
				    #- check for size before trying to select.
				    my $size = pkgs::selectedSize($packages);
				    foreach (@l) {
					my $p = pkgs::packageByName($packages, $_);
					$p->flag_selected or $size += $p->size;
				    }
				    if (pkgs::correctSize($size / sqr(1024)) > $available / sqr(1024)) {
					return $o->ask_warn('', _("You can't select this package as there is not enough space left to install it"));
				    }

				    @l > @n && $common->{state}{auto_deps} and
				      $o->ask_okcancel('', [ $isSelection ? 
							     _("The following packages are going to be installed") :
							     _("The following packages are going to be removed"),
							     common::formatList(20, sort @l) ], 1) || return;
				    if ($isSelection) {
					pkgs::selectPackage($packages, $_) foreach @n;
				    } else {
					pkgs::unselectPackage($packages, $_) foreach @n;
				    }
				    foreach (@l) {
					my $p = pkgs::packageByName($packages, $_);
					$set_state->($_, $p->flag_selected ? 'selected' : 'unselected');
				    }
				} else {
				    $o->ask_warn('', _("You can't select/unselect this package"));
				}
			    },
			    grep_allowed_to_toggle => sub {
				grep { $_ ne _("Other") && !pkgs::packageByName($packages, $_)->flag_base } @_;
			    },
			    grep_unselected => sub {
				grep { !pkgs::packageByName($packages, $_)->flag_selected } @_;
			    },
			    check_interactive_to_toggle => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return;
				if ($p->flag_base) {
				    $o->ask_warn('', _("This is a mandatory package, it can't be unselected"));
				} elsif ($p->flag_installed && !$p->flag_upgrade) {
				    $o->ask_warn('', _("You can't unselect this package. It is already installed"));
				} elsif ($p->flag_selected && $p->flag_installed) {
				    if ($::expert) {
					$o->ask_yesorno('', _("This package must be upgraded.\nAre you sure you want to deselect it?")) or return;
					return 1;
				    } else {
					$o->ask_warn('', _("You can't unselect this package. It must be upgraded"));
				    }
				} else { return 1 }
				return;
			    },
			    auto_deps => _("Show automatically selected packages"),
			    ok => _("Install"),
			    cancel => $limit_to_medium && _("Cancel"),
			    icons => [ { icon         => 'floppy',
					 help         => _("Load/Save on floppy"),
					 wait_message => _("Updating package selection"),
					 code         => sub { $o->loadSavePackagesOnFloppy($packages); 1 },
				       }, 
				       if_(0, 
				       { icon         => 'feather',
					 help         => _("Minimal install"),
					 code         => sub {
					     
					     install_any::unselectMostPackages($o);
					     pkgs::setSelectedFromCompssList($packages, { SYSTEM => 1 }, 4, $availableCorrected);
					     1;
					 } }),
				     ],
			    state => {
				      auto_deps => 1,
				      flat      => $limit_to_medium,
				     },
			  };

    $o->set_help('choosePackagesTree');
    $o->ask_browse_tree_info('', _("Choose the packages you want to install"), $common);
}

#------------------------------------------------------------------------------
sub beforeInstallPackages {
    my ($o) = @_;    
    $o->SUPER::beforeInstallPackages;
    install_any::copy_advertising($o);
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;

    my ($current_total_size, $last_size, $nb, $total_size, $start_time, $last_dtime, $trans_progress_total);

    my $w = my_gtk->new(_("Installing"));
    $w->sync;
    my $text = new Gtk::Label;
    my ($advertising, $change_time, $i);
    my $show_advertising if 0;
    $show_advertising = to_bool(@install_any::advertising_images) if !defined $show_advertising;
    my ($msg, $msg_time_remaining, $msg_time_total) = map { new Gtk::Label($_) } '', (_("Estimating")) x 2;
    my ($progress, $progress_total) = map { new Gtk::ProgressBar } (1..2);
    $w->{rwindow}->set_policy(1, 1, 1);
    gtkadd($w->{window}, my $box = new Gtk::VBox(0,10));
    $box->pack_end(gtkshow(gtkpack(gtkset_usize(new Gtk::VBox(0,5), $::windowwidth * 0.6, 0),
			   $msg, $progress,
			   create_packtable({},
					    [_("Time remaining "), $msg_time_remaining],
#					    [_("Total time "), $msg_time_total],
					   ),
			   $text,
			   $progress_total,
			   gtkadd(create_hbox(),
				  my $cancel = new Gtk::Button(_("Cancel")),
				  my $details = new Gtk::Button(_("Details")),
				  ),
			  )), 0, 1, 0);
    $details->hide if !@install_any::advertising_images;
    $w->sync;
    $msg->set(_("Please wait, preparing installation..."));
    gtkset_mousecursor_normal($cancel->window);
    gtkset_mousecursor_normal($details->window);
    my $advertize = sub {
	@install_any::advertising_images or return;
	$show_advertising ? $_->hide : $_->show foreach $msg, $progress, $text;
	gtkdestroy($advertising) if $advertising;
	if ($show_advertising && $_[0]) {
	    $change_time = time();
	    my $f = $install_any::advertising_images[$i++ % @install_any::advertising_images];
	    log::l("advertising $f");
	    my $pl = $f; $pl =~ s/\.png$/\.pl/;
	    my $icon_name = $f; $icon_name =~ s/\.png$/_icon\.png/;
	    my ($draw_text, $width, $height, @data, $icon, $icon_dx, $icon_dy, $icon_px);
	    -e $pl and $draw_text = 1;
	    eval(cat_($pl)) if $draw_text;
	    my ($pix, undef) = gtkcreate_png($f);
	    if ($icon) {
		($icon_px, undef) = gtkcreate_png($icon_name);
	    }
	    my $dbl_area;
	    my $darea = new Gtk::DrawingArea;
	    gtkpack($box, $advertising = !$draw_text ?
		    gtkpng($f) :
		    gtksignal_connect(gtkset_usize($darea, $width, $height), expose_event => sub {
			       my ($dx, $dy) = ($darea->allocation->[2], $darea->allocation->[3]);
			       if (!defined($dbl_area)) {
				   $dbl_area = new Gtk::Gdk::Pixmap($darea->window, $dx, $dy);
				   $dbl_area->draw_rectangle($darea->style->bg_gc('active'), 1, 0, 0, $dx, $dy);
				   $dbl_area->draw_pixmap($darea->style->bg_gc('normal'),
							  $pix, 0, 0, ($dx-$width)/2, 0, $width, $height);
				   my $gc_text = new Gtk::Gdk::GC($darea->window);
				   $gc_text->set_foreground(gtkcolor(65535, 65535, 65535));
				   my $yicon = 0;
				   my $decy = 0;
				   my $first = 1;
				   foreach (@data) {
				       my ($text, $x, $y, $area_width, $area_height, $bold) = @$_;
				       my ($width, $height, $lines, $widths, $heights, $ascents, $descents) =
					 get_text_coord ($text, $darea, $area_width, $area_height, 1, 0, 1, 1);
				       if ($first && $icon) {
					   my $iconx = ($dx-$width)/2 + $x + ${$widths}[0] - $icon_dx;
					   my $icony = $y + ${$heights}[0] - $icon_dy/2;
					   $icony > 0 or $icony = 0;
					   $dbl_area->draw_pixmap($darea->style->bg_gc('normal'), $icon_px, 0, 0,
								  $iconx, $icony, $icon_dx, $icon_dy
								 );
					   $yicon = $icony + $icon_dy;
				       }
				       my $i = 0;
				       $yicon > $y + ${$heights}[0] and $decy = $yicon - ($y + ${$heights}[$i]);
				       foreach (@{$lines}) {
					   $dbl_area->draw_string($darea->style->font, $gc_text,
								  ($dx-$width)/2 + $x + ${$widths}[$i], ($first ? 0 : $decy) + $y + ${$heights}[$i], $_);
 					   $bold and $dbl_area->draw_string($darea->style->font, $gc_text,
									    ($dx-$width)/2 + $x + ${$widths}[$i] + 1, ($first ? 0 : $decy) + $y + ${$heights}[$i], $_);
					   $i++;
				       }
				       $first = 0;
				   }
			       }
			       $darea->window->draw_pixmap($darea->style->bg_gc('normal'),
							   $dbl_area, 0, 0, 0, 0, $dx, $dy);
			   }));
	} else {
	    $advertising = undef;
	}
    };

    $cancel->signal_connect(clicked => sub { $pkgs::cancel_install = 1 });
    $details->signal_connect(clicked => sub {
	invbool \$show_advertising;
	$advertize->(1);
    });
    $advertize->();

    my $oldInstallCallback = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my ($data, $type, $id, $subtype, $amount, $total) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    #- $amount and $total are used to return number of package and total size.
	    $nb = $amount;
	    $total_size = $total; $current_total_size = 0;
	    $start_time = time();
	    $msg->set(_("%d packages", $nb));
	    $w->flush;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    $progress->update(0);
	    my $p = $data->{depslist}[$id];
	    $msg->set(_("Installing package %s", $p->name));
	    $current_total_size += $last_size;
	    $last_size = $p->size;
	    $text->set((split /\n/, $p->summary)[0] || '');
	    $advertize->(1) if $show_advertising && $total_size > 20_000_000 && time() - $change_time > 20;
	    $w->flush;
	} elsif ($type eq 'inst' && $subtype eq 'progress') {
	    $progress->update($total ? $amount / $total : 0);

	    my $dtime = time() - $start_time;
	    my $ratio = 
	      $total_size == 0 ? 0 :
		pkgs::size2time($current_total_size + $amount, $total_size) / pkgs::size2time($total_size, $total_size);
	    $ratio >= 1 and $ratio = 1;
	    my $total_time = $ratio ? $dtime / $ratio : time();

	    $progress_total->update($ratio);
	    if ($dtime != $last_dtime && $current_total_size > 80_000_000) {
		$msg_time_total->set(formatTime(10 * round($total_time / 10) + 10));
#-		$msg_time_total->set(formatTimeRaw($total_time) . "  " . formatTimeRaw($dtime / $ratio2));
		$msg_time_remaining->set(formatTime(10 * round(max($total_time - $dtime, 0) / 10) + 10));
		$last_dtime = $dtime;
	    }
	    $w->flush;
	} else { goto $oldInstallCallback }
    };
    #- the modification is not local as the box should be living for other package installation.
    undef *install_any::changeMedium;
    *install_any::changeMedium = sub {
	my ($method, $medium) = @_;

	#- if not using a cdrom medium, always abort.
	if ($method eq 'cdrom' && !$::oem) {
	    local $my_gtk::grab = 1;
	    my $name = pkgs::mediumDescr($o->{packages}, $medium);
	    local $| = 1; print "\a";
	    my $time = time();
	    my $r = $name !~ /commercial/i || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX($install_steps_interactive::com_license), [ __("Accept"), __("Refuse") ], "Accept") eq "Accept");
            $r &&= $o->ask_okcancel('', _("Change your Cd-Rom!

Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you don't have it, press Cancel to avoid installation from this Cd-Rom.", $name), 1);
            #- add the elapsed time (otherwise the predicted time will be rubbish)
            $start_time += time() - $time;
            return $r;
	}
    };
    my $install_result;
    catch_cdie { $install_result = $o->install_steps::installPackages($packages) }
      sub {
	  if ($@ =~ /^error ordering package list: (.*)/) {
	      $o->ask_yesorno('', [
_("There was an error ordering packages:"), $1, _("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  } elsif ($@ =~ /^error installing package list: (.*)/) {
	      $o->ask_yesorno('', [
_("There was an error installing packages:"), $1, _("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  }
	  0;
      };
    if ($pkgs::cancel_install) {
	$pkgs::cancel_install = 0;
	die 'already displayed';
    }
    $w->destroy;
    $install_result;
}

sub set_help {
    my ($o, @l) = @_;

    my @l2 = map { 
	join("\n\n", map { s/\n/ /mg; $_ } split("\n\n", translate($help::steps{$_})))
    } @l;
    $o->{current_help} = join("\n\n\n", @l2);
    gtktext_insert($o->{help_window_text}, $o->{current_help});
    1;
}

1;
