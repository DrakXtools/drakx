package install_steps_gtk;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive_gtk);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :functional :system);
use partition_table qw(:types);
use my_gtk qw(:helpers :wrappers);
use Gtk;
#-use Gtk::XmHTML;
use devices;
use fsedit;
use commands;
use modules;
use pkgs;
use partition_table qw(:types);
use partition_table_raw;
use install_steps;
use install_steps_interactive;
use interactive_gtk;
use install_any;
use diskdrake;
use log;
use mouse;
use help;
use lang;

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################
my $w_help;
my $itemsNB = 1;
my (@background1, @background2);

my @themes_vga16 = qw(blue blackwhite savane);
my @themes = qw(mdk DarkMarble marble3d blueHeart);


#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    my $old = $SIG{__DIE__};
    $SIG{__DIE__} = sub { $_[0] !~ /my_gtk\.pm/ and goto $old };

    $ENV{DISPLAY} ||= $o->{display} || ":0";
    unless ($::testing) {
	$my_gtk::force_focus = $ENV{DISPLAY} eq ":0";

	my $f = "/tmp/Xconf";
	createXconf($f, @{$o->{mouse}}{"XMOUSETYPE", "device"}, $o->{wacom});
	devices::make("/dev/kbd");

	if ($ENV{DISPLAY} eq ":0") {
	    my $launchX = sub {
		my $ok = 1;
		local $SIG{CHLD} = sub { $ok = 0 if waitpid(-1, c::WNOHANG()) > 0 };
		unless (fork) {
		    exec $_[0], (arch() =~ /^sparc/ || arch() eq "ppc" ? () : ("-kb")), "-dpms","-s" ,"240",
		      ($_[0] =~ /Xsun/ || $_[0] =~ /Xpmac/ ? ("-fp", "/usr/X11R6/lib/X11/fonts:unscaled") :
		       ("-allowMouseOpenFail", "-xf86config", $f)) or exit 1;
		}
		foreach (1..60) {
		    sleep 1;
		    log::l("Server died"), return 0 if !$ok;
		    return 1 if c::Xtest($ENV{DISPLAY});
		}
		log::l("Timeout!!");
		0;
	    };
	    my @servers = qw(FBDev VGA16); #-)
	    if (arch() eq "alpha") {
		require Xconfigurator;
		my $card = Xconfigurator::cardConfigurationAuto();
		Xconfigurator::updateCardAccordingName($card, $card->{type}) if $card && $card->{type};
		@servers = $card->{server} || "TGA";
		#-@servers = qw(SVGA 3DLabs TGA) 
	    } elsif (arch() =~ /^sparc/) {
		local $_ = cat_("/proc/fb");
		if (/Mach64/) { @servers = qw(Mach64) }
		elsif (/Permedia2/) { @servers = qw(3DLabs) }
		else { @servers = qw(Xsun24) }
	    } elsif (arch() eq "ppc") {
	    	@servers = qw(Xpmac);
            }

	    foreach (@servers) {
		log::l("Trying with server $_");
		sleep 3;
		my $dir = "/usr/X11R6/bin";
		my $prog = /Xsun/ || /Xpmac/ ? $_ : "XF86_$_";
		unless (-x "$dir/$prog") {
		    unlink $_ foreach glob_("$dir/X*");
		    install_any::getAndSaveFile("$dir/$prog", "$dir/$prog") or die "failed to get server $prog: $!";
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
  OK: @themes = @themes_vga16 if $o->{simple_themes} || $o->{vga16};

    init_sizes();
    install_theme($o);
    create_logo_window($o);

    $my_gtk::force_center = [ $::rootwidth - $::windowwidth, $::logoheight, $::windowwidth, $::windowheight ];

    (bless {}, ref $type || $type)->SUPER::new($o);
}

sub enteringStep {
    my ($o, $step) = @_;

    print _("Entering step `%s'\n", translate($o->{steps}{$step}{text}));
    $o->SUPER::enteringStep($step);
    create_steps_window($o);
    create_help_window($o);
}
sub leavingStep {
    my ($o, $step) = @_;
    $o->SUPER::leavingStep($step);
}



#-######################################################################################
#- Steps Functions
#-######################################################################################
sub selectLanguage {
    my ($o, $first_time) = @_;
    $o->SUPER::selectLanguage;
    Gtk->set_locale;
    install_theme($o);
    
    $o->ask_warn('',
_("Your system is low on resource. You may have some problem installing
Linux-Mandrake. If that occurs, you can try a text install instead. For this,
press `F1' when booting on CDROM, then enter `text'.")) if $first_time && availableRam < 60 * 1024; # 60MB

}

#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;

    my $w = my_gtk->new('');
    my ($radio, $focused);
    gtkadd($w->{window},
	   gtkpack($o->create_box_with_title(_("Please, choose one of the following classes of installation:")),
		   (my @radios = map { $radio = new Gtk::RadioButton($_, $radio ? $radio : ()); 
			 $radio->set_active($_ eq $def); $radio } @$l),
		   gtkadd(create_hbox(),
			  map { my $v = $_; 
				my $b = new Gtk::Button(translate($_));
				$focused = $b if $_ eq $def2;
				gtksignal_connect($b, "clicked" => sub { $w->{retval} = $v; Gtk->main_quit });
			    } @$l2)
		  ));
    $focused->grab_focus if $focused;
    $w->main;

    mapn { $verif->($_[1]) if $_[0]->active } \@radios, $l;
    create_steps_window($o);

    $w->{retval};
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;
    my $old = $o->{mouse}{XMOUSETYPE};
    $o->SUPER::selectMouse($force);

    if ($old ne $o->{mouse}{XMOUSETYPE} && !$::testing) {
	log::l("telling X server to use another mouse");
	eval { commands::modprobe("serial") } if $o->{mouse}{device} =~ /ttyS/;
	symlinkf($o->{mouse}{device}, "/dev/mouse");
	my $id = mouse::xmouse2xId($o->{mouse}{XMOUSETYPE});
	log::l("XMOUSETYPE: $o->{mouse}{XMOUSETYPE} = $id");
	c::setMouseLive($ENV{DISPLAY}, $id);
    }
}

#------------------------------------------------------------------------------
sub chooseSizeToInstall {
    my ($o, $packages, $min_size, $max_size_, $availableC, $individual) = @_;
    my $max_size = min($max_size_, $availableC);
    my $enough = $max_size == $max_size_;
    my $percentage = int 100 * $max_size / $max_size_;

    #- don't ask anything if the difference between min and max is too small
    return $max_size if $min_size && $max_size / $min_size < 1.05;

    log::l("choosing size to install between $min_size and $max_size");
    my $w = my_gtk->new('');
    my $adj = create_adjustment($percentage, $min_size * 100 / $max_size_, $percentage);
    my $spin = gtkset_usize(new Gtk::SpinButton($adj, 0, 0), 20, 0);
    my $val;

    gtkadd($w->{window},
	  gtkpack(new Gtk::VBox(0,20),
		  _("The total size for the groups you have selected is approximately %d MB.\n", pkgs::correctSize($max_size_ / sqr(1024))) .
		  ($enough ?
_("If you wish to install less than this size,
select the percentage of packages that you want to install.

A low percentage will install only the most important packages;
a percentage of 100%% will install all selected packages.") : 
_("You have space on your disk for only %d%% of these packages.

If you wish to install less than this,
select the percentage of packages that you want to install.
A low percentage will install only the most important packages;
a percentage of %d%% will install as many packages as possible.", $percentage, $percentage))
. ($individual ? "\n\n" . _("You will be able to choose them more specifically in the next step.") : ''),
		 create_packtable({},
				  [ _("Percentage of packages to install") . '  ', $spin, "%", my $mb = new Gtk::Label ],
				  [ undef, new Gtk::HScrollbar($adj) ],
			       ),
		 create_okcancel($w)
		)
	 );
    $spin->signal_connect(changed => my $changed = sub { 
	$val = $spin->get_value_as_int / 100 * $max_size_;
	$mb->set(sprintf("(%dMB)", pkgs::correctSize($val / sqr(1024)))); 
    }); &$changed();
    $spin->signal_connect(activate => sub { $w->{retval} = 1; Gtk->main_quit });
    $spin->grab_focus();
    $w->main and $val;
}
sub choosePackagesTree {
    my ($o, $packages, $compss) = @_;

    my ($curr, $info_widget, $w_size, $go, $idle, $flat, $auto_deps);
    my (%wtree, %ptree);

    my $w = my_gtk->new('');
    my $details = new Gtk::VBox(0,0);
    my $tree = Gtk::CTree->new(3, 0);
    $tree->set_selection_mode('browse');
    $tree->set_column_width(0, 200);
    $tree->set_column_auto_resize($_, 1) foreach 1..2;

    gtkadd($w->{window}, 
	   gtkpack_(new Gtk::VBox(0,5),
		    0, _("Choose the packages you want to install"),
		    1, gtkpack(new Gtk::HBox(0,0),
			       createScrolledWindow($tree),
			       gtkadd(gtkset_usize(new Gtk::Frame(_("Info")), $::windowwidth - 490, 0),
				      createScrolledWindow($info_widget = new Gtk::Text),
				     )),
		    0, my $l = new Gtk::HBox(0,15),
		    0, gtkpack(new Gtk::HBox(0,10),
			       $go = gtksignal_connect(new Gtk::Button(_("Install")), "clicked" => sub { $w->{retval} = 1; Gtk->main_quit }),
			      )
    ));
    gtkpack__($l, my $toolbar = new Gtk::Toolbar('horizontal', 'icons'));
    gtkpack__($l, gtksignal_connect(new Gtk::CheckButton(_("Automatic dependencies")), clicked => sub { invbool \$auto_deps }));
    $l->pack_end($w_size = new Gtk::Label(''), 0, 1, 20);

    $w->{window}->set_usize(map { $_ - 2 * $my_gtk::border - 4 } $::windowwidth, $::windowheight);
    $go->grab_focus;
    $w->{rwindow}->show_all;

    my $pix_base     = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-base.xpm") ];
    my $pix_selected = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-selected.xpm") ];
    my $pix_unselect = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-unselected.xpm") ];
    my $pix_installed= [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-installed.xpm") ];

    my $parent; $parent = sub {
	if (my $w = $wtree{$_[0]}) { return $w }
	my $s; foreach (split '/', $_[0]) {
	    $wtree{"$s/$_"} ||= 
	      $tree->insert_node($s ? $parent->($s) : undef, undef, [$_, '', ''], 5, (undef) x 4, 0, 0);
	    $s = "$s/$_";
	}
	$wtree{$s};
    };
    my $add_node = sub {
	my ($leaf, $root) = @_;
	my $node = $tree->insert_node($parent->($root), undef, [$leaf, '', ''], 5, (undef) x 4, 1, 0);
	my $p = $packages->[0]{$leaf} or return;
	$p->{medium}{selected} or return;
	my $pix = pkgs::packageFlagBase($p) ? $pix_base : pkgs::packageFlagSelected($p) ? $pix_selected : pkgs::packageFlagInstalled($p) ? $pix_installed : $pix_unselect;
	$tree->node_set_pixmap($node, 1, $pix->[0], $pix->[1]);
	push @{$ptree{$leaf}}, $node;
    };
    my $add_nodes = sub {
	%ptree = %wtree = ();

	$tree->freeze;
	while (1) { $tree->remove_node($tree->node_nth(0) || last) }

	my ($root, $leaf);
	if ($flat = $_[0]) {
	    $add_node->($_, undef) foreach sort grep { my $pkg = pkgs::packageByName($packages, $_);
						       $pkg->{medium}{selected} } keys %{$packages->[0]};
	} else {
	    foreach (sort @$compss) {
		($root, $leaf) = m|(.*)/(.+)|o or ($root, $leaf) = ('', $_);
		my $pkg = pkgs::packageByName($packages, $leaf);
		$add_node->($leaf, $root) if $pkg->{medium}{selected};
	    }
	}
	$tree->thaw;
    };
    $add_nodes->($flat);

    my %toolbar = my @toolbar = 
      (
       ftout =>  [ _("Expand Tree") , sub { $tree->expand_recursive(undef) } ],
       ftin  =>  [ _("Collapse Tree") , sub { $tree->collapse_recursive(undef) } ],
       reload=>  [ _("Toggle between flat and group sorted"), sub { $add_nodes->(!$flat) } ],
      );
    $toolbar->set_button_relief("none");
    foreach (grep_index { $::i % 2 == 0 } @toolbar) {
	gtksignal_connect($toolbar->append_item(undef, $toolbar{$_}[0], undef, gtkxpm($tree, "$ENV{SHARE_PATH}/$_.xpm")),
			  clicked => $toolbar{$_}[1]);
    }
    $toolbar->set_style("icons");


    my $display_info = sub {
	my $p = $packages->[0]{$curr} or return gtktext_insert($info_widget, '');
	pkgs::extractHeaders($o->{prefix}, [$p], $p->{medium});
	$p->{header} or die;

	my $ind = $o->{compssListLevels}{$o->{installClass}};
	my $imp = translate($pkgs::compssListDesc{pkgs::packageFlagBase($p) ? 100 : round_down($p->{values}[$ind], 10)});

	gtktext_insert($info_widget, $@ ? _("Bad package") :
		       _("Name: %s\n", pkgs::packageName($p)) .
		       _("Version: %s\n", pkgs::packageVersion($p) . '-' . pkgs::packageRelease($p)) .
		       _("Size: %d KB\n", pkgs::packageSize($p) / 1024) .
		       ($imp && _("Importance: %s\n", $imp)) . "\n" .
		       formatLines(c::headerGetEntry($p->{header}, 'description')));
	c::headerFree(delete $p->{header});
	0;
    };

    my $update_size = sub {
	my $size = pkgs::selectedSize($packages);
	$w_size->set(_("Total size: %d / %d MB", 
		       pkgs::correctSize($size / sqr(1024)),
		       install_any::getAvailableSpace($o) / sqr(1024)));
    };
    my $toggle = sub {
	if (ref $curr) {
	    $tree->toggle_expansion($curr);
	} else {
	    my $p = $packages->[0]{$curr} or return;
	    if (pkgs::packageFlagBase($p)) {
		return $o->ask_warn('', _("This is a mandatory package, it can't be unselected"));
	    } elsif (pkgs::packageFlagInstalled($p)) {
		return $o->ask_warn('', _("You can't unselect this package. It is already installed"));
	    } elsif (pkgs::packageFlagUpgrade($p)) {
		if ($::expert) {
		    if (pkgs::packageFlagSelected($p)) {
			$o->ask_yesorno('', _("This package must be upgraded\nAre you sure you want to deselect it?")) or return;
		    }
		} else {
		    return $o->ask_warn('', _("You can't unselect this package. It must be upgraded"));
		}
	    }

	    pkgs::togglePackageSelection($packages, $p, my $l = {});
	    if (my @l = grep { $l->{$_} } keys %$l) {
		#- check for size before trying to select.
		my $size = pkgs::selectedSize($packages);
		foreach (@l) {
		    my $p = $packages->[0]{$_};
		    pkgs::packageFlagSelected($p) or $size += pkgs::packageSize($p);
		}
		if (pkgs::correctSize($size / sqr(1024)) > install_any::getAvailableSpace($o) / sqr(1024)) {
		    return $o->ask_warn('', _("You can't select this package as there is not enough space left to install it"));
		}

		@l > 1 && !$auto_deps and $o->ask_okcancel('', [ _("The following packages are going to be installed/removed"), join(", ", sort @l) ], 1) || return;
		pkgs::togglePackageSelection($packages, $p);
		foreach (@l) {
		    my $p = $packages->[0]{$_};
		    my $pix = pkgs::packageFlagSelected($p) ? $pix_selected : $pix_unselect;
		    $tree->node_set_pixmap($_, 1, $pix->[0], $pix->[1]) foreach @{$ptree{$_}};
		}
		&$update_size;
	    } else {
		$o->ask_warn('', _("You can't select/unselect this package"));
	    }
	}
    };
    $tree->signal_connect(button_press_event => sub { &$toggle if $_[1]{type} =~ /^2/ });
    $tree->signal_connect(key_press_event => sub {
        my ($w, $e) = @_;
	my $c = chr($e->{keyval} & 0xff);
	&$toggle if $e->{keyval} >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ';
	1;
    });
    $tree->signal_connect(tree_select_row => sub {
	Gtk->timeout_remove($idle) if $idle;

	if ($_[1]->row->is_leaf) {
	    ($curr) = $tree->node_get_pixtext($_[1], 0);
	    $idle = Gtk->timeout_add(100, $display_info);
	} else {
	    $curr = $_[1];
	}
	&$toggle if $_[2] == 1;
    });
    &$update_size;
    $w->main;
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;

    my ($current_total_size, $last_size, $nb, $total_size, $start_time, $last_dtime, $trans_progress_total);

    my $w = my_gtk->new(_("Installing"), grab => 1);
    $w->{window}->set_usize($::windowwidth * 0.8, 260);
    my $text = new Gtk::Label;
    my ($msg, $msg_time_remaining, $msg_time_total) = map { new Gtk::Label($_) } '', (_("Estimating")) x 2;
    my ($progress, $progress_total) = map { new Gtk::ProgressBar } (1..2);
    gtkadd($w->{window}, gtkpack(new Gtk::VBox(0,10),
			       _("Please wait, "), $msg, $progress,
			       create_packtable({},
						[_("Time remaining "), $msg_time_remaining],
						[_("Total time "), $msg_time_total],
						),
			       $text,
			       $progress_total,
			       '',
			       gtkadd(create_hbox(),
				      gtksignal_connect(new Gtk::Button(_("Cancel")), 
							clicked => sub { $pkgs::cancel_install = 1 })),
			      ));
    $msg->set(_("Preparing installation"));
    $w->sync;

    my $oldInstallCallback = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my $m = shift;
	if ($m =~ /^Starting installation/) {
	    $nb = $_[0];
	    $total_size = $_[1]; $current_total_size = 0;
	    $start_time = time();
	    $msg->set(_("%d packages", $nb));
	    $w->flush;
	} elsif ($m =~ /^Starting installing package/) {
	    $progress->update(0);
	    my $name = $_[0];
	    $msg->set(_("Installing package %s", $name));
	    $current_total_size += $last_size;
	    $last_size = c::headerGetEntry($o->{packages}[0]{$name}{header}, 'size');
	    $text->set((split /\n/, c::headerGetEntry($o->{packages}[0]{$name}{header}, 'summary'))[0] || '');
	    $w->flush;
	} elsif ($m =~ /^Progressing installing package/) {
	    $progress->update($_[2] ? $_[1] / $_[2] : 0);

	    my $dtime = time() - $start_time;
	    my $ratio = $total_size ? ($_[1] + $current_total_size) / $total_size : 0;
	    my $total_time = $ratio ? $dtime / $ratio : time();

	    $progress_total->update($ratio);
	    if ($dtime != $last_dtime && $current_total_size > 2 * 1024 * 1024) {
		$msg_time_total->set(formatTime(10 * round($total_time / 10)));
		$msg_time_remaining->set(formatTime(10 * round(max($total_time - $dtime, 0) / 10)));
		$last_dtime = $dtime;
	    }
	    $w->flush;
	} else { unshift @_, $m; goto $oldInstallCallback }
    };
    #- the modification is not local as the box should be living for other package installation.
    undef *install_any::changeMedium;
    *install_any::changeMedium = sub {
	my ($method, $medium) = @_;
	my $msg =
_("Change your Cd-Rom!

Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you don't have it, press Cancel to avoid installation from this Cd-Rom.", pkgs::mediumDescr($o->{packages}, $medium));

	#- if not using a cdrom medium, always abort.
	$method eq 'cdrom' and do {
	    local $my_gtk::grab = 1;
	    $o->ask_okcancel('', $msg);
	};
    };
    catch_cdie { $o->install_steps::installPackages($packages); }
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
	die "setstep choosePackages\n";
    }
    $w->destroy;
}

#------------------------------------------------------------------------------
sub load_rc($) {
    if (my ($f) = grep { -r $_ } map { "$_/$_[0].rc" } ("share", $ENV{SHARE_PATH}, dirname(__FILE__))) {
	Gtk::Rc->parse($f);
	foreach (cat_($f)) {
	    if (/style\s+"background"/ .. /^\s*$/) {
		@background1 = map { $_ * 256 * 257 } split ',', $1 if /NORMAL.*\{(.*)\}/;
		@background2 = map { $_ * 256 * 257 } split ',', $1 if /PRELIGHT.*\{(.*)\}/;
	    }
	}
    }
}

sub install_theme {
    my ($o, $theme) = @_;    
    $o->{theme} = $theme || $o->{theme} || $themes[0];

    gtkset_mousecursor(68);

    load_rc($_) foreach "themes-$o->{theme}", "install", "themes";

    if (my ($font, $font2) = lang::get_x_fontset($o->{lang})) {
	$font2 ||= $font;
	Gtk::Rc->parse_string(qq(
style "default-font" 
{
   fontset = "$font"
}
style "small-font"
{
   fontset = "$font2"
}
widget "*" style "default-font"
widget "*Steps*" style "small-font"

));
   }
    gtkset_background(@background1);# unless $::testing;

    create_logo_window($o);
    create_help_window($o);
}

#------------------------------------------------------------------------------
sub create_big_help {
    my $w = my_gtk->new('', grab => 1, force_position => [ $::stepswidth, $::logoheight ]);
    $w->{rwindow}->set_usize($::logowidth, $::rootheight - $::logoheight);
    gtkadd($w->{window},
	   gtkpack_(new Gtk::VBox(0,0),
		    1, createScrolledWindow(gtktext_insert(new Gtk::Text, 
							   formatAlaTeX(translate($help::steps{$::o->{step}})))),
		    0, gtksignal_connect(new Gtk::Button(_("Ok")), "clicked" => sub { Gtk->main_quit }),
		   ));
    $w->main;
}

#------------------------------------------------------------------------------
sub create_help_window {
    my ($o) = @_;

#    $o->{help_window}->destroy if $o->{help_window};

    my $w;
    if ($w = $o->{help_window}) {
	$_->destroy foreach $w->{window}->children;
    } else {
	$w = bless {}, 'my_gtk';
	$w->{rwindow} = $w->{window} = new Gtk::Window;
	$w->{rwindow}->set_uposition($::rootwidth - $::helpwidth, $::rootheight - $::helpheight);
	$w->{rwindow}->set_usize($::helpwidth, $::helpheight);
	$w->sync;
    }

#-    my $b = new Gtk::Button;
#-    $b->signal_connect(clicked => sub {
#-	  my $w = my_gtk->new('', grab => 1, force_position => [ $stepswidth, $logoheight ]);
#-	  $w->{rwindow}->set_usize($logowidth, $height - $logoheight);
#-	  gtkadd($w->{window},
#-		 gtkpack_(new Gtk::VBox(0,0),
#-			  1, createScrolledWindow(gtktext_insert(new Gtk::Text, 
#-								 formatAlaTeX(translate($help::steps_long{$o->{step}})))),
#-			  0, gtksignal_connect(new Gtk::Button(_("Ok")), "clicked" => sub { Gtk->main_quit }),
#-			  ));
#-	  $w->main;
#-    });
#-    my @l = (@questionmark_head,
#-	       join('', "X c #", map { sprintf "%02X", $_ / 256 } @background1),
#-	       join('', "O c #", map { sprintf "%02X", $_ / 256 } @background2),
#-	       @questionmark_body);
#-    my @pixmap = Gtk::Gdk::Pixmap->create_from_xpm_d($w->{window}->window, undef, @l);
#-    gtkadd($b, new Gtk::Pixmap(@pixmap));

#    Gtk::XmHTML->init;
    my $pixmap = new Gtk::Pixmap( gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/help.xpm"));
    gtkadd($w->{window},
	   gtkpack_(new Gtk::HBox(0,-2),
#-		    0, $b,
#-		    1, createScrolledWindow($w_help = new Gtk::XmHTML)));
		    0, $pixmap,
		    1, createScrolledWindow($w_help = new Gtk::Text)
		   ));

#-    $w_help->source($o->{step} ? translate($o->{steps}{$o->{step}}{help}) : '');
    gtktext_insert($w_help, $o->{step} ? formatAlaTeX(translate($help::steps{$o->{step}})) : '');

    $w->show;
    $o->{help_window} = $w;
}

sub set_help { 
    shift;
    gtktext_insert($w_help, 
		   formatAlaTeX(join "\n", 
				map { translate($help::steps{$_}) } @_));
    1;
}

#------------------------------------------------------------------------------
sub create_steps_window {
    my ($o) = @_;

    my $PIX_H = my $PIX_W = 21;

    $o->{steps_window}->destroy if $o->{steps_window};

    my $w = bless {}, 'my_gtk';
    $w->{rwindow} = $w->{window} = new Gtk::Window;
    $w->{rwindow}->set_uposition(0, 0);
    $w->{rwindow}->set_usize($::stepswidth, $::stepsheight);
    $w->{rwindow}->set_name('Steps');
    $w->{rwindow}->set_events('button_press_mask');
    $w->show;

    gtkadd($w->{window},
	   gtkpack_(new Gtk::VBox(0,0),
		    (map {; 1, $_ } map {
			my $step_name = $_;
			my $step = $o->{steps}{$_};
			my $darea = new Gtk::DrawingArea;
			my $in_button;
			my $draw_pix = sub {
			    my $pixmap = Gtk::Gdk::Pixmap->create_from_xpm($darea->window,
									   $darea->style->bg('normal'),
									   $_[0]) or die;
			    $darea->window->draw_pixmap ($darea->style->bg_gc('normal'),
							 $pixmap, 0, 0,
							 ($darea->allocation->[2]-$PIX_W)/2,
							 ($darea->allocation->[3]-$PIX_H)/2,
							 $PIX_W , $PIX_H );
			};

			my $f = sub { 
			    my ($type) = @_;
			    my $color = $step->{done} ? 'green' : $step->{entered} ? 'orange' : 'red';
			    "$ENV{SHARE_PATH}/step-$color$type.xpm";
			};
			$darea->set_usize($PIX_W,$PIX_H);
			$darea->set_events(['exposure_mask', 'enter_notify_mask', 'leave_notify_mask', 'button_press_mask', 'button_release_mask' ]);
			$darea->signal_connect(expose_event => sub { $draw_pix->($f->('')) });
			if ($step->{reachable}) {
			    $darea->signal_connect(enter_notify_event => sub { $in_button=1; $draw_pix->($f->('-on')); });
			    $darea->signal_connect(leave_notify_event => sub { undef $in_button; $draw_pix->($f->('')); });
			    $darea->signal_connect(button_press_event => sub { $draw_pix->($f->('-click')); });
			    $darea->signal_connect(button_release_event => sub { $in_button && die "setstep $step_name\n" });
			}
			gtkpack_(new Gtk::HBox(0,5), 0, $darea, 0, new Gtk::Label(translate($step->{text})));
		    } grep {
			!eval $o->{steps}{$_}{hidden};
		    } @{$o->{orderedSteps}}),
		    0, gtkpack(new Gtk::HBox(0,0), map {
			my $t = $_;
			my $w = new Gtk::Button('');
			$w->set_name($t);
			$w->set_usize(0, 7);
			gtksignal_connect($w, clicked => sub {
			    $::setstep or return; #- just as setstep s
			    install_theme($o, $t); die "theme_changed\n" 
			});
		    } @themes)));
    $w->show;
    $o->{steps_window} = $w;
}

#------------------------------------------------------------------------------
sub create_logo_window() {
    my ($o) = @_;
    gtkdestroy($o->{logo_window});
    my $w = bless {}, 'my_gtk';
    $w->{rwindow} = $w->{window} = new Gtk::Window;
    $w->{rwindow}->set_uposition($::stepswidth, 0);
    $w->{rwindow}->set_usize($::logowidth, $::logoheight);
    $w->{rwindow}->set_name("logo");
    $w->show;
    my $file = "logo-mandrake.xpm";
    -r $file or $file = "$ENV{SHARE_PATH}/$file";
    if (-r $file) {
	my $ww = $w->{window};
	my @logo = Gtk::Gdk::Pixmap->create_from_xpm($ww->window, $ww->style->bg('normal'), $file);
	gtkadd($ww, new Gtk::Pixmap(@logo));
    }
    $o->{logo_window} = $w;
}

sub init_sizes() {
#    my $maxheight = arch() eq "ppc" ? 1024 : 600;
#    my $maxwidth = arch() eq "ppc" ? 1280 : 800;
    ($::rootheight,  $::rootwidth)    = (480, 640);
    ($::rootheight,  $::rootwidth)    = my_gtk::gtkroot()->get_size;
    #- ($::rootheight,  $::rootwidth)    = (min(768, $::rootheight), min(1024, $::rootwidth));
    ($::stepswidth,  $::stepsheight)  = (145, $::rootheight);
    ($::logowidth,   $::logoheight)   = ($::rootwidth - $::stepswidth, 40);                                 
    ($::helpwidth,   $::helpheight)   = ($::rootwidth - $::stepswidth, 100);                                
    ($::windowwidth, $::windowheight) = ($::rootwidth - $::stepswidth, $::rootheight - $::helpheight - $::logoheight);
}

#------------------------------------------------------------------------------
sub createXconf {
    my ($file, $mouse_type, $mouse_dev, $wacom_dev) = @_;

    devices::make("/dev/kbd") if arch() =~ /^sparc/; #- used by Xsun style server.
    symlinkf($mouse_dev, "/dev/mouse");

    #- needed for imlib to start on 8-bit depth visual.
    symlink("/tmp/stage2/etc/imrc", "/etc/imrc");
    symlink("/tmp/stage2/etc/im_palette.pal", "etc/im_palette.pal");

    my $wacom;
    if ($wacom_dev) {
	$wacom_dev = devices::make($wacom_dev);
	$wacom = <<END;
Section "Module"
   Load "xf86Wacom.so"
EndSection

Section "XInput"
    SubSection "WacomStylus"
        Port "$wacom_dev"
        AlwaysCore
    EndSubSection
    SubSection "WacomCursor"
        Port "$wacom_dev"
        AlwaysCore
    EndSubSection
    SubSection "WacomEraser"
        Port "$wacom_dev"
        AlwaysCore
    EndSubSection
EndSection
END
    }

    local *F;
    open F, ">$file" or die "can't create X configuration file $file";
    print F <<END;
Section "Files"
   FontPath   "/usr/X11R6/lib/X11/fonts:unscaled"
EndSection

Section "Keyboard"
   Protocol    "Standard"
   AutoRepeat  0 0

   LeftAlt         Meta
   RightAlt        Meta
   ScrollLock      Compose
   RightCtl        Control
END

    if (arch() =~ /^sparc/) {
	print F <<END;
   XkbRules    "sun"
   XkbModel    "sun"
   XkbLayout   "us"
   XkbCompat   "compat/complete"
   XkbTypes    "types/complete"
   XkbKeycodes "sun(type5)"
   XkbGeometry "sun(type5)"
   XkbSymbols  "sun/us(sun5)"
END
    } else {
	print F "    XkbDisable\n";
    }

    print F <<END;
EndSection

Section "Pointer"
   Protocol    "$mouse_type"
   Device      "/dev/mouse"
   ZAxisMapping 4 5
EndSection

$wacom

Section "Monitor"
   Identifier  "My Monitor"
   VendorName  "Unknown"
   ModelName   "Unknown"
   HorizSync   31.5-35.5
   VertRefresh 50-70
   Modeline "640x480"     25.175 640  664  760  800   480  491  493  525
   Modeline "640x480"     28.3   640  664  760  800   480  491  493  525
   ModeLine "800x600"     36     800  824  896 1024   600  601  603  625
EndSection


Section "Device"
   Identifier "Generic VGA"
   VendorName "Unknown"
   BoardName "Unknown"
   Chipset "generic"
EndSection

Section "Device"
   Identifier "svga"
   VendorName "Unknown"
   BoardName "Unknown"
EndSection

Section "Screen"
    Driver      "vga16"
    Device      "Generic VGA"
    Monitor     "My Monitor"
    Subsection "Display"
        Modes       "640x480"
        ViewPort    0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "fbdev"
    Device      "Generic VGA"
    Monitor     "My Monitor"
    Subsection "Display"
        Depth       16
        Modes       "default"
        ViewPort    0 0
    EndSubsection
EndSection

Section "Screen"
    Driver "svga"
    Device      "svga"
    Monitor     "My Monitor"
    Subsection "Display"
        Depth       16
        Modes       "800x600" "640x480"
        ViewPort    0 0
    EndSubsection
EndSection

Section "Screen"
    Driver      "accel"
    Device      "svga"
    Monitor     "My Monitor"
    Subsection "Display"
        Depth       16
        Modes       "800x600" "640x480"
        ViewPort    0 0
    EndSubsection
EndSection
END
}
#-   ModeLine "640x480"     28     640  672  768  800   480  490  492  525
#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
