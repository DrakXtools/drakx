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
	    install_gtk::createXconf($f, @{$o->{mouse}}{"XMOUSETYPE", "device"}, $o->{wacom}[0]);
	    devices::make("/dev/kbd");

	    local (*T1, *T2);
	    open T1, ">/dev/tty5";
	    open T2, ">/dev/tty6";

	    my $launchX = sub {
		my $ok = 1;
		my $xpmac_opts = cat_("/proc/cmdline");
		unless (-d "/var/log" ) { mkdir("/var/log"); }
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
	    } elsif (arch() =~ /ia64/) {
		@servers= 'XFree86';
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
    install_gtk::default_theme($o);
    install_gtk::create_logo_window($o);

    $my_gtk::force_center = [ $::rootwidth - $::windowwidth, $::logoheight, $::windowwidth, $::windowheight ];

    $o = (bless {}, ref $type || $type)->SUPER::new($o);
    $o->interactive_gtk::new;
    $o;
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
_("Your system is low on resource. You may have some problem installing
Mandrake Linux. If that occurs, you can try a text install instead. For this,
press `F1' when booting on CDROM, then enter `text'.")) if $first_time && availableRamMB() < 60; # 60MB

}

#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;
    $::live || @$l == 1 and return $o->SUPER::selectInstallClass1($verif, $l, $def, $l2, $def2);

    my $w = my_gtk->new(_("Install Class"));
    my $focused;
    gtkadd($w->{window},
	   gtkpack($w->create_box_with_title(_("Please, choose one of the following classes of installation:")),
		   (my @radios = gtkradio($def, @$l)),
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

#------------------------------------------------------------------------------
sub chooseSizeToInstall {
    my ($o, $packages, $min_size, $def_size, $max_size_, $availableC, $individual) = @_;
    my $max_size = min($max_size_, $availableC);
    my $enough = $max_size == $max_size_;
    my $percentage = int 100 * $max_size / $max_size_;

    #- don't ask anything if the difference between min and max is too small
    log::l("chooseSizeToInstall: min_size=$min_size, def_size=$def_size, max_size=$max_size_, available=$availableC");
    return $max_size if $min_size && $max_size / $min_size < 1.05;

    log::l("choosing size to install between $min_size and $max_size");
    my $w = my_gtk->new('');
    my $adj = create_adjustment(int(100 * $def_size / $max_size_), $min_size * 100 / $max_size_, $percentage);
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
    $w->main and $val + 1; #- add a single byte (hack?) to make selection of 0 bytes ok.
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

	my $file = do {
	    my $f = "$ENV{SHARE_PATH}/icons/" . ($o->{compssUsers}{$e}{icons} || 'default');
	    -e "$f.png" or $f .= "_section";
	    -e "$f.png" or $f = "$ENV{SHARE_PATH}/icons/default_section";
	    "$f.png";
	};
	my $check = Gtk::CheckButton->new($text);
	$check->set_active($val->{$e});
	$check->signal_connect(clicked => sub { 
	    $val->{$e} = $check->get_active;
	    $w_size->set(&$size_to_display);
	});
	gtkset_tip($tips, $check, $help);
	gtkpack_(new Gtk::HBox(0,0), 0, gtkpng($file), 1, $check);
	#$check;
    };
    my $entries_in_path = sub {
	my ($path) = @_;
	translate($path), map { $entry->($_) } grep { !/Utilities/ && $o->{compssUsers}{$_}{path} eq $path } @{$o->{compssUsersSorted}};
    };
    gtkadd($w->{window},
	   gtkpack($w->create_box_with_title(_("Package Group Selection")),
		   gtkpack_(new Gtk::VBox(0,0),
			   1, gtkpack_(new Gtk::HBox(0,0),
				   1, gtkpack(new Gtk::VBox(0,0), 
					   $entries_in_path->('Workstation'),
					   '',
					   $entry->('Development|Development'),
					   $entry->('Development|Documentation'),
					  ),
				   0, gtkpack(new Gtk::VBox(0,0), 
					   $entries_in_path->('Server'),
					   '',
					   $entries_in_path->('Graphical Environment'),
					  ),
				     ),
			   ),
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
    my ($o, $packages) = @_;

    my $available = install_any::getAvailableSpace($o);
    my $availableCorrected = pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);

    my $common; $common = { get_status => sub {
				my $size = pkgs::selectedSize($packages);
				_("Total size: %d / %d MB", pkgs::correctSize($size / sqr(1024)), $available / sqr(1024));
			    },
			    node_state => sub {
				my $p = pkgs::packageByName($packages,$_[0]) or return;
				pkgs::packageMedium($p)->{selected} or return;
				pkgs::packageFlagBase($p) and return 'base';
				pkgs::packageFlagInstalled($p) and return 'installed';
				pkgs::packageFlagSelected($p) and return 'selected';
				return 'unselected';
			    },
			    build_tree => sub {
				my ($add_node, $flat) = @_;
				if ($flat) {
				    foreach (sort keys %{$packages->{names}}) {
					$add_node->($_, undef);
				    }
				} else {
				    foreach my $root (@{$o->{compssUsersSorted}}) {
					my (%fl, @firstchoice, @others);
					#$fl{$_} = $o->{compssUsersChoice}{$_} foreach @{$o->{compssUsers}{$root}{flags}}; #- FEATURE:improve choce of packages...
					$fl{$_} = 1 foreach @{$o->{compssUsers}{$root}{flags}};
					foreach my $p (values %{$packages->{names}}) {
					    my ($rate, @flags) = pkgs::packageRateRFlags($p);
					    next if !($rate && grep { grep { !/^!/ && $fl{$_} } split('\|\|') } @flags);
					    $rate >= 3 ?
					      push(@firstchoice, pkgs::packageName($p)) :
						push(@others,      pkgs::packageName($p));
					}
					my $root2 = join('|', map { translate($_) } split('\|', $root));
					$add_node->($_, $root2                   ) foreach sort @firstchoice;
					$add_node->($_, $root2 . '|' . _("Other")) foreach sort @others;
				    }
				}
			    },
			    get_info => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return '';
				pkgs::extractHeaders($o->{prefix}, [$p], pkgs::packageMedium($p));
				pkgs::packageHeader($p) or die;

				my $imp = translate($pkgs::compssListDesc{pkgs::packageFlagBase($p) ?
									  5 : pkgs::packageRate($p)});

				my $info = $@ ? _("Bad package") :
				  (_("Name: %s\n", pkgs::packageName($p)) .
				   _("Version: %s\n", pkgs::packageVersion($p) . '-' . pkgs::packageRelease($p)) .
				   _("Size: %d KB\n", pkgs::packageSize($p) / 1024) .
				   ($imp && _("Importance: %s\n", $imp)) . "\n" .
				   formatLines(c::headerGetEntry(pkgs::packageHeader($p), 'description')));
				pkgs::packageFreeHeader($p);
				return $info;
			    },
			    toggle_nodes => sub {
				my $set_state = shift @_;
				my @n = map { pkgs::packageByName($packages, $_) } @_;
				my %l;
				my $isSelection = !pkgs::packageFlagSelected($n[0]);
				foreach (@n) {
				    pkgs::togglePackageSelection($packages, $_, my $l = {});
				    @l{grep {$l->{$_}} keys %$l} = ();
				}
				if (my @l = keys %l) {
				    #- check for size before trying to select.
				    my $size = pkgs::selectedSize($packages);
				    foreach (@l) {
					my $p = $packages->{names}{$_};
					pkgs::packageFlagSelected($p) or $size += pkgs::packageSize($p);
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
					$set_state->($_, pkgs::packageFlagSelected($p) ? 'selected' : 'unselected');
				    }
				} else {
				    $o->ask_warn('', _("You can't select/unselect this package"));
				}
			    },
			    grep_allowed_to_toggle => sub {
				grep { $_ ne _("Other") && !pkgs::packageFlagBase(pkgs::packageByName($packages, $_)) } @_;
			    },
			    grep_unselected => sub {
				grep { !pkgs::packageFlagSelected(pkgs::packageByName($packages, $_)) } @_;
			    },
			    check_interactive_to_toggle => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return;
				if (pkgs::packageFlagBase($p)) {
				    $o->ask_warn('', _("This is a mandatory package, it can't be unselected"));
				} elsif (pkgs::packageFlagInstalled($p)) {
				    $o->ask_warn('', _("You can't unselect this package. It is already installed"));
				} elsif (pkgs::packageFlagUpgrade($p)) {
				    if ($::expert) {
					if (pkgs::packageFlagSelected($p)) {
					    $o->ask_yesorno('', _("This package must be upgraded\nAre you sure you want to deselect it?")) or return;
					}
					return 1;
				    } else {
					$o->ask_warn('', _("You can't unselect this package. It must be upgraded"));
				    }
				} else { return 1; }
				return;
			    },
			    auto_deps => _("Show automatically selected packages"),
			    ok => _("Install"),
			    cancel => undef,
			    icons => [ { icon         => 'floppy',
					 help         => _("Load/Save on floppy"),
					 wait_message => _("Updating package selection"),
					 code         => sub { $o->loadSavePackagesOnFloppy($packages); 1; },
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
				      flat      => 0,
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
    $box->pack_end(gtkshow(gtkpack(gtkset_usize(new Gtk::VBox(0,5), $::windowwidth * 0.8, 0),
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
    $msg->set(_("Please wait, preparing installation"));
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
	    eval { gtkpack($box, $advertising = gtkpng($f)) };
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
	    my $p = pkgs::packageByName($o->{packages}, $name);
	    $last_size = c::headerGetEntry(pkgs::packageHeader($p), 'size');
	    $text->set((split /\n/, c::headerGetEntry(pkgs::packageHeader($p), 'summary'))[0] || '');
	    $advertize->(1) if $show_advertising && $total_size > 20_000_000 && time() - $change_time > 20;
	    $w->flush;
	} elsif ($m =~ /^Progressing installing package/) {
	    $progress->update($_[2] ? $_[1] / $_[2] : 0);

	    my $dtime = time() - $start_time;
	    my $ratio = 
	      $total_size == 0 ? 0 :
		pkgs::size2time($current_total_size + $_[1], $total_size) / pkgs::size2time($total_size, $total_size);
	    $ratio >= 1 and $ratio = 1;
	    my $total_time = $ratio ? $dtime / $ratio : time();

#-	    my $ratio2 = $total_size == 0 ? 0 : ($current_total_size + $_[1]) / $total_size;
#-	    log::l(sprintf("XXXX advance %d %d %s", $current_total_size + $_[1], $dtime, formatTimeRaw($total_time)));

	    $progress_total->update($ratio);
	    if ($dtime != $last_dtime && $current_total_size > 80_000_000) {
		$msg_time_total->set(formatTime(10 * round($total_time / 10) + 10));
#-		$msg_time_total->set(formatTimeRaw($total_time) . "  " . formatTimeRaw($dtime / $ratio2));
		$msg_time_remaining->set(formatTime(10 * round(max($total_time - $dtime, 0) / 10) + 10));
		$last_dtime = $dtime;
	    }
	    $w->flush;
	} else { unshift @_, $m; goto $oldInstallCallback }
    };
    #- the modification is not local as the box should be living for other package installation.
    undef *install_any::changeMedium;
    *install_any::changeMedium = sub {
	my ($method, $medium) = @_;

	#- if not using a cdrom medium, always abort.
	$method eq 'cdrom' and do {
	    local $my_gtk::grab = 1;
	    my $name = pkgs::mediumDescr($o->{packages}, $medium);
	    local $| = 1; print "\a";
	    my $time = time();
	    my $r = $name !~ /Application/ || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX(_("
Warning

Please read carefully the terms below. If you disagree with any
portion, you are not allowed to install the next CD media. Press 'Refuse' 
to continue the installation without using these media.


Some components contained in the next CD media are not governed
by the GPL License or similar agreements. Each such component is then
governed by the terms and conditions of its own specific license. 
Please read carefully and comply with such specific licenses before 
you use or redistribute the said components. 
Such licenses will in general prevent the transfer,  duplication 
(except for backup purposes), redistribution, reverse engineering, 
de-assembly, de-compilation or modification of the component. 
Any breach of agreement will immediately terminate your rights under 
the specific license. Unless the specific license terms grant you such
rights, you usually cannot install the programs on more than one
system, or adapt it to be used on a network. In doubt, please contact 
directly the distributor or editor of the component. 
Transfer to third parties or copying of such components including the 
documentation is usually forbidden.


All rights to the components of the next CD media belong to their 
respective authors and are protected by intellectual property and 
copyright laws applicable to software programs.
")), [ __("Accept"), __("Refuse") ], "Accept") eq "Accept");
            $r &&= $o->ask_okcancel('', _("Change your Cd-Rom!

Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you don't have it, press Cancel to avoid installation from this Cd-Rom.", $name), 1);
            #- add the elapsed time (otherwise the predicted time will be rubbish)
            $start_time += time() - $time;
            $r;
	};
    };
    my $install_result;
    catch_cdie { $install_result = $o->install_steps::installPackages($packages); }
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

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
