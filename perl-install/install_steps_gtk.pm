package install_steps_gtk; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(install_steps_interactive interactive_gtk);

#-######################################################################################
#- misc imports
#-######################################################################################
use install_steps_interactive;
use interactive_gtk;
use common qw(:common :file :functional :system);
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
	$my_gtk::force_focus = $ENV{DISPLAY} eq ":0";

	my $f = "/tmp/Xconf";
	install_gtk::createXconf($f, @{$o->{mouse}}{"XMOUSETYPE", "device"}, $o->{wacom});
	devices::make("/dev/kbd");

	if ($ENV{DISPLAY} eq ":0") {
	    local (*T1, *T2);
	    open T1, ">/dev/tty5";
	    open T2, ">/dev/tty6";

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
		my $dir = "/usr/X11R6/bin";
		my $prog = /Xsun|Xpmac/ ? $_ : "XF86_$_";
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
  OK:
    install_gtk::init_sizes();
    install_gtk::default_theme($o);
    install_gtk::create_logo_window($o);

    $my_gtk::force_center = [ $::rootwidth - $::windowwidth, $::logoheight, $::windowwidth, $::windowheight ];

    (bless {}, ref $type || $type)->SUPER::new($o);
}

sub enteringStep {
    my ($o, $step) = @_;

    printf "Entering step `%s'\n", $o->{steps}{$step}{text};
    $o->SUPER::enteringStep($step);
    install_gtk::create_steps_window($o);
    install_gtk::create_help_window($o);
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
    install_gtk::install_theme($o);
    
    $o->ask_warn('',
_("Your system is low on resource. You may have some problem installing
Linux-Mandrake. If that occurs, you can try a text install instead. For this,
press `F1' when booting on CDROM, then enter `text'.")) if $first_time && availableRamMB() < 60; # 60MB

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
    install_gtk::create_steps_window($o);

    $w->{retval};
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;

    my $set = sub {
	my ($mouse) = @_;
	symlinkf($mouse->{device}, "/dev/mouse");
	c::setMouseLive($ENV{DISPLAY}, mouse::xmouse2xId($mouse->{XMOUSETYPE}));
    };

    my %old = %{$o->{mouse}};
    $o->SUPER::selectMouse($force);
    $old{type} eq $o->{mouse}{type} && $old{name} eq $o->{mouse}{name} && !$force and return;

    local $my_gtk::grab = 1; #- unsure a crazy mouse don't go wild clicking everywhere

    while (1) {
	log::l("telling X server to use another mouse");
	eval { modules::load('serial') } if $o->{mouse}{device} =~ /ttyS/;

	if (!$::testing) {
	    symlinkf($o->{mouse}{device}, "/dev/mouse");
	    c::setMouseLive($ENV{DISPLAY}, mouse::xmouse2xId($o->{mouse}{XMOUSETYPE}));
	}
	install_gtk::test_mouse($o->{mouse}) and return;
	$o->SUPER::selectMouse(1);
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

    require pkgs;
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

    my ($curr, $parent, $info_widget, $w_size, $go, $idle, $flat, $auto_deps);
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
    my $pix_semisele = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-semiselected.xpm") ];
    my $pix_installed= [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-installed.xpm") ];

    my $add_parent; $add_parent = sub {
	$_[0] or return undef;
	if (my $w = $wtree{$_[0]}) { return $w }
	my $s; foreach (split '/', $_[0]) {
	    my $s2 = $s ? "$s/$_" : $_;
	    $wtree{$s2} ||= do {	     
		my $n = $tree->insert_node($s ? $add_parent->($s) : undef, undef, [$_, '', ''], 5, (undef) x 4, 0, 0);
		$n;
	    };
	    $s = $s2;
	}
	$tree->node_set_pixmap($wtree{$s}, 1, $pix_semisele->[0], $pix_semisele->[1]);
	$wtree{$s};
    };
    my $add_node = sub {
	my ($leaf, $root) = @_;
	my $p = $packages->[0]{$leaf} or return;
	$p->{medium}{selected} or return;
	my $node = $tree->insert_node($add_parent->($root), 
				      undef, [$leaf, '', ''], 5, (undef) x 4, 1, 0);
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
    my $select = sub {
	my %l;
	my $isSelection = !pkgs::packageFlagSelected($_[0]);
	foreach (@_) {
	    pkgs::togglePackageSelection($packages, $_, my $l = {});
	    @l{grep {$l->{$_}} keys %$l} = ();
	}
	if (my @l = keys %l) {
	    #- check for size before trying to select.
	    my $size = pkgs::selectedSize($packages);
	    foreach (@l) {
		my $p = $packages->[0]{$_};
		pkgs::packageFlagSelected($p) or $size += pkgs::packageSize($p);
	    }
	    if (pkgs::correctSize($size / sqr(1024)) > install_any::getAvailableSpace($o) / sqr(1024)) {
		return $o->ask_warn('', _("You can't select this package as there is not enough space left to install it"));
	    }

	    @l > @_ && !$auto_deps and $o->ask_okcancel('', [ $isSelection ? 
							      _("The following packages are going to be installed") :
							      _("The following packages are going to be removed"),
							      join(", ", sort @l) ], 1) || return;
	    $isSelection ? pkgs::selectPackage($packages, $_) : pkgs::unselectPackage($packages, $_) foreach @_;
	    foreach (@l) {
		my $p = $packages->[0]{$_};
		my $pix = pkgs::packageFlagSelected($p) ? $pix_selected : $pix_unselect;
		$tree->node_set_pixmap($_, 1, $pix->[0], $pix->[1]) foreach @{$ptree{$_}};
	    }
	    &$update_size;
	} else {
	    $o->ask_warn('', _("You can't select/unselect this package"));
	}
    };
    my $children = sub { map { $packages->[0]{($tree->node_get_pixtext($_, 0))[0]} } gtkctree_children($_[0]) };
    my $toggle = sub {
	if (ref $curr && ! $_[0]) {
	    $tree->toggle_expansion($curr);
	} else {
	    if (ref $curr) {
		my @l = grep { !pkgs::packageFlagBase($_) } $children->($curr) or return;
		my @unsel = grep { !pkgs::packageFlagSelected($_) } @l;
		my @p = @unsel ?
		  @unsel : # not all is selected, select all
		    @l;
		$select->(@p);
		$parent = $curr;
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
		$select->($p);
	    }
	    if (my @l = $children->($parent)) {
		my $nb = grep { pkgs::packageFlagSelected($_) } @l;
		my $pix = $nb==0 ? $pix_unselect : $nb<@l ? $pix_semisele : $pix_selected;
		$tree->node_set_pixmap($parent, 1, $pix->[0], $pix->[1]);
	    }
	}
    };

    $tree->signal_connect(key_press_event => sub {
        my ($w, $e) = @_;
	my $c = chr($e->{keyval} & 0xff);
	$toggle->(0) if $e->{keyval} >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ';
	1;
    });
    $tree->signal_connect(tree_select_row => sub {
	Gtk->timeout_remove($idle) if $idle;

	if ($_[1]->row->is_leaf) {
	    ($curr) = $tree->node_get_pixtext($_[1], 0);
	    $parent = $_[1]->row->parent;
	    $idle = Gtk->timeout_add(100, $display_info);
	} else {
	    $curr = $_[1];
	}
	$toggle->(1) if $_[2] == 1;
    });
    &$update_size;
    $w->main;
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;

    my ($current_total_size, $last_size, $nb, $total_size, $start_time, $last_dtime, $trans_progress_total);

    my $w = my_gtk->new(_("Installing"));
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
				      my $cancel = new Gtk::Button(_("Cancel"))),
			      ));
    $w->sync;
    $msg->set(_("Preparing installation"));
    gtkset_mousecursor_normal($cancel->window);
    $cancel->signal_connect(clicked => sub { $pkgs::cancel_install = 1 });

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
	    if ($dtime != $last_dtime && $current_total_size > 10 * 1024 * 1024) {
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

sub set_help {
    my ($o, @l) = @_;

    $::live and return 1;
    $o->{current_help} = formatAlaTeX(join "\n", map { _ deref($help::steps{$_}) } @l);
    gtktext_insert($o->{help_window_text}, $o->{current_help});
    1;
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
