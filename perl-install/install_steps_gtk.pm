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
use xf86misc::main;
use common;
use mygtk2;
use ugtk2 qw(:helpers :wrappers :create);
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

    $ENV{DISPLAY} ||= $o->{display} || ":0";
    my $wanted_DISPLAY = $::testing && -x '/usr/X11R6/bin/Xnest' ? ':9' : $ENV{DISPLAY};

    if (!$::local_install && 
	($::testing ? $ENV{DISPLAY} ne $wanted_DISPLAY : $ENV{DISPLAY} =~ /^:\d/)) { #- is the display local or distant?
	my $f = "/tmp/Xconf";
	if (!$::testing) {
	    devices::make("/dev/kbd");
	}
	my $launchX = sub {
	    my ($server, $Driver) = @_;

	    mkdir '/var/log' if !-d '/var/log';

	    my @options = $wanted_DISPLAY;
	    if ($server eq 'Xnest') {
		push @options, '-ac', '-geometry', $o->{vga} || ($o->{vga16} ? '640x480' : '800x600');
	    } elsif ($::globetrotter || !$::move) {
		install_gtk::createXconf($f, @{$o->{mouse}}{"XMOUSETYPE", "device"}, $o->{mouse}{wacom}[0], $Driver);

		push @options, if_(!$::globetrotter, '-kb'), '-allowMouseOpenFail', '-xf86config', $f if arch() !~ /^sparc/;
		push @options, 'tty7', '-dpms', '-s', '240';

		#- old weird servers: Xsun
		push @options, '-fp', '/usr/X11R6/lib/X11/fonts:unscaled' if $server =~ /Xsun/;
	    }

	    if (!fork()) {
		c::setsid();
		exec $server, @options or c::_exit(1);
	    }

	    #- wait for the server to start
	    foreach (1..5) {
		sleep 1;
		last if fuzzy_pidofs(qr/\b$server\b/);
		log::l("$server still not running, trying again");
	    }
	    my $nb;
	    foreach (1..60) {
		log::l("waiting for the server to start ($_ $nb)");
		log::l("Server died"), return 0 if !fuzzy_pidofs(qr/\b$server\b/);
		$nb++ if xf86misc::main::Xtest($wanted_DISPLAY);
		if ($nb > 2) { #- one succeeded test is not enough :-(
		    log::l("AFAIK X server is up");
		    return 1;
		}
		sleep 1;
	    }
	    log::l("Timeout!!");
	    0;
	};
	my @servers = qw(Driver:fbdev); #-)
	if ($::testing) {
	    @servers = 'Xnest';
	} elsif (arch() eq "alpha") {
	    require Xconfig::card;
	    my ($card) = Xconfig::card::probe();
	    Xconfig::card::add_to_card__using_Cards($card, $card->{type}) if $card && $card->{type};
	    @servers = $card->{server} || "TGA";
	    #-@servers = qw(SVGA 3DLabs TGA) 
	} elsif (arch() =~ /^sparc/) {
	    local $_ = cat_("/proc/fb");
	    if (/Mach64/) {
		@servers = qw(Mach64);
	    } elsif (/Permedia2/) {
		@servers = qw(3DLabs);
	    } else {
		@servers = qw(Xsun24);
	    }
	} elsif (arch() =~ /ia64/) {
	    require Xconfig::card;
	    my ($card) = Xconfig::card::probe();
	    @servers = map { if_($_, "Driver:$_") } $card && $card->{Driver}, 'fbdev';
        }

        if (($::move || $::globetrotter) && !$::testing) {
            require move;
            require run_program;
            move::automatic_xconf($o);
            run_program::run('/sbin/service', 'xfs', 'start');
            @servers = $::globetrotter ? qw(Driver:fbdev) : qw(X_move);
	}

	foreach (@servers) {
	    log::l("Trying with server $_");
	    my ($prog, $Driver) = /Driver:(.*)/ ? ('Xorg', $1) : /Xsun|Xnest|^X_move$/ ? $_ : "XF86_$_";
	    if (/FB/i) {
		!$o->{vga16} && $o->{allowFB} or next;

		$o->{allowFB} = &$launchX($prog, $Driver) #- keep in mind FB is used.
		  and goto OK;
	    } else {
		$o->{vga16} = 1 if /VGA16/;
		&$launchX($prog, $Driver) and goto OK;
	    }
            $::move and print("can not launch graphical mode :(\n"), c::_exit(1);
	}
	return undef;
    }
  OK:
    $ENV{DISPLAY} = $wanted_DISPLAY;
    require detect_devices;
    if (detect_devices::is_xbox()) {
        modules::load('xpad');
        run_program::run('xset', 'm', '1/8', '1');
    }
    install_gtk::init_gtk($o);
    install_gtk::init_sizes();
    install_gtk::install_theme($o);
    install_gtk::create_logo_window($o);
    install_gtk::create_steps_window($o);

    $ugtk2::grab = 1;

    $o = (bless {}, ref($type) || $type)->SUPER::new($o);
    $o->interactive::gtk::new;
    $o;
}

sub enteringStep {
    my ($o, $step) = @_;

    printf "Entering step `%s'\n", $o->{steps}{$step}{text};
    $o->SUPER::enteringStep($step);
    install_gtk::update_steps_position($o);
}
sub leavingStep {
    my ($o, $step) = @_;
    $o->SUPER::leavingStep($step);
}


sub charsetChanged {
    my ($o) = @_;
    Gtk2->set_locale;
    install_gtk::load_font($o);
    install_gtk::create_steps_window($o);
}

#-######################################################################################
#- Steps Functions
#-######################################################################################
sub selectLanguage {
    my ($o) = @_;
    $o->SUPER::selectLanguage;
  
    $o->ask_warn('',
formatAlaTeX(N("Your system is low on resources. You may have some problem installing
Mandriva Linux. If that occurs, you can try a text install instead. For this,
press `F1' when booting on CDROM, then enter `text'."))) if availableRamMB() < 70; # 70MB

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
      $old{device} eq $mouse->{device} and return;

    while (1) {
	my $x_protocol_changed = mouse::change_mouse_live($mouse, \%old);
	mouse::test_mouse_install($mouse, $x_protocol_changed) and return;

	%old = %$mouse;
	$o->SUPER::selectMouse;
	$mouse = $o->{mouse};
    } 
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $_compssUsers) = @_;

    my $w = ugtk2->new(N("Package Group Selection"));
    my $w_size = gtknew('Label', text => &$size_to_display);

    my $entry = sub {
	my ($e) = @_;

	gtknew('CheckButton', 
	       text => translate($e->{label}), 
	       tip => translate($e->{descr}),
	       active_ref => \$e->{selected},
	       toggled => sub { 
		   gtkset($w_size, text => &$size_to_display);
	       });
    };
    #- when restarting this step, it might be necessary to reload the compssUsers.pl (bug 11558). kludgy.
    if (!ref $o->{gtk_display_compssUsers}) { install_any::load_rate_files($o) }
    ugtk2::gtkadd($w->{window},
	   gtkpack_($w->create_box_with_title(N("Package Group Selection")),
		    1, $o->{gtk_display_compssUsers}->($entry),
		    1, '',
		    0, gtknew('HBox', children_loose => [
			  gtknew('Button', text => N("Help"), clicked => $o->interactive_help_sub_display_id('choosePackages')),
			  $w_size,
			  if_($individual,
			      gtknew('CheckButton', text => N("Individual package selection"), active_ref => $individual),
			  ),
			  gtknew('Button', text => N("Next"), clicked => sub { Gtk2->main_quit }),
			 ]),
		  ),
	  );
    $w->main;
    1;
}

sub choosePackagesTree {
    my ($o, $packages, $o_limit_medium) = @_;

    my $available = install_any::getAvailableSpace($o);
    my $availableCorrected = pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);

    my $common;
    $common = {             get_status => sub {
				my $size = pkgs::selectedSize($packages);
				N("Total size: %d / %d MB", pkgs::correctSize($size / sqr(1024)), $available / sqr(1024));
			    },
			    node_state => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return;
				pkgs::packageMedium($packages, $p)->selected or return;
				$p->arch eq 'src'                       and return;
				$p->flag_base                           and return 'base';
				$p->flag_installed && !$p->flag_upgrade and return 'installed';
				$p->flag_selected                       and return 'selected';
				return 'unselected';
			    },
			    build_tree => sub {
				my ($add_node, $flat) = @_;
				if ($flat) {
				    foreach (sort map { $_->name }
					     grep { !$o_limit_medium || pkgs::packageMedium($packages, $_) == $o_limit_medium }
					     grep { $_ && $_->arch ne 'src' }
					     @{$packages->{depslist}}) {
					$add_node->($_, undef);
				    }
				} else {
				    foreach my $root (@{$o->{compssUsers}}) {
					my (@firstchoice, @others);
					my %fl = map { ("CAT_$_" => 1) } @{$root->{flags}};
					foreach my $p (@{$packages->{depslist}}) {
					    !$o_limit_medium || pkgs::packageMedium($packages, $p) == $o_limit_medium or next;
					    my @flags = $p->rflags;
					    next if !($p->rate && any { any { !/^!/ && $fl{$_} } split('\|\|') } @flags);
					    $p->rate >= 3 ?
					      push(@firstchoice, $p->name) :
						push(@others,    $p->name);
					}
					my $root2 = translate($root->{path}) . '|' . translate($root->{label});
					$add_node->($_, $root2)                    foreach sort @firstchoice;
					$add_node->($_, $root2 . '|' . N("Other")) foreach sort @others;
				    }
				}
			    },
			    get_info => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return '';
				pkgs::extractHeaders([$p], $packages->{mediums});

				my $imp = translate($pkgs::compssListDesc{$p->flag_base ? 5 : $p->rate});

                                my $tag = { 'foreground' => 'royalblue3' };
				$@ ? N("Bad package") :
				  [ [ N("Name: "), $tag ], [ $p->name . "\n" ],
                                    [ N("Version: "), $tag ], [ $p->version . '-' . $p->release . "\n" ],
                                    [ N("Size: "), $tag ], [ N("%d KB\n", $p->size / 1024) ],
                                    if_($imp, [ N("Importance: "), $tag ], [ "$imp\n" ]),
                                    [ "\n" ], [ formatLines(c::from_utf8($p->description)) ] ];
			    },
			    toggle_nodes => sub {
				my $set_state = shift @_;
				my $isSelection = 0;
				my %l = map { my $p = pkgs::packageByName($packages, $_);
					      $isSelection ||= !$p->flag_selected;
					      $p->id => 1 } @_;
				my $state = $packages->{state} ||= {};
				my @l = $isSelection ? $packages->resolve_requested($packages->{rpmdb}, $state, \%l,
										    callback_choices => \&pkgs::packageCallbackChoices) :
						       $packages->disable_selected($packages->{rpmdb}, $state,
										   map { $packages->{depslist}[$_] } keys %l);
				my $size = pkgs::selectedSize($packages);
				my $error;

				if (!@l) {
				    #- no package can be selected or unselected.
				    my @ask_unselect = grep { $state->{rejected}{$_}{backtrack} &&
								exists $l{$packages->search($_, strict_fullname => 1)->id} }
				      keys %{$state->{rejected} || {}};
				    #- extend to closure (to given more detailed and not absurd reason).
				    my %ask_unselect;
				    while (@ask_unselect > keys %ask_unselect) {
					@ask_unselect{@ask_unselect} = ();
					foreach (keys %ask_unselect) {
					    foreach (keys %{$state->{rejected}{$_}{backtrack}{closure} || {}}) {
						next if exists $ask_unselect{$_};
						push @ask_unselect, $_;
					    }
					}
				    }
				    $error = [ N("You can not select/unselect this package"),
					       formatList(20, map { my $rb = $state->{rejected}{$_}{backtrack};
									    my @froms = keys %{$rb->{closure} || {}};
									    my @unsatisfied = @{$rb->{unsatisfied} || []};
									    my $s = join ", ", ((map { N("due to missing %s", $_) } @froms),
												(map { N("due to unsatisfied %s", $_) } @unsatisfied),
												$rb->{promote} && !$rb->{keep} ? N("trying to promote %s", join(", ", @{$rb->{promote}})) : @{[]},
												$rb->{keep} ? N("in order to keep %s", join(", ", @{$rb->{keep}})) : @{[]},
											       );
									    $_ . ($s ? " ($s)" : '');
									} sort @ask_unselect) ];
				} elsif (pkgs::correctSize($size / sqr(1024)) > $available / sqr(1024)) {
				    $error = N("You can not select this package as there is not enough space left to install it");
				} elsif (@l > @_ && $common->{state}{auto_deps}) {
				    $o->ask_okcancel('', [ $isSelection ? 
							   N("The following packages are going to be installed") :
							   N("The following packages are going to be removed"),
							       formatList(20, sort(map { $_->name } @l)) ], 1) or $error = ''; #- defined
				}
				if (defined $error) {
				    $o->ask_warn('', $error) if $error;
				    #- disable selection (or unselection).
				    $isSelection ? $packages->disable_selected($packages->{rpmdb}, $state, @l) :
				                   $packages->resolve_requested($packages->{rpmdb}, $state, { map { $_->id => 1 } @l });
				} else {
				    #- keep the changes, update visible state.
				    foreach (@l) {
					$set_state->($_->name, $_->flag_selected ? 'selected' : 'unselected');
				    }
				}
			    },
			    grep_allowed_to_toggle => sub {
				grep { my $p = pkgs::packageByName($packages, $_); $p && !$p->flag_base } @_;
			    },
			    grep_unselected => sub {
				grep { !pkgs::packageByName($packages, $_)->flag_selected } @_;
			    },
			    check_interactive_to_toggle => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return;
				if ($p->flag_base) {
				    $o->ask_warn('', N("This is a mandatory package, it can not be unselected"));
				} elsif ($p->flag_installed && !$p->flag_upgrade) {
				    $o->ask_warn('', N("You can not unselect this package. It is already installed"));
				} elsif ($p->flag_selected && $p->flag_installed) {
				    if ($::expert) {
					$o->ask_yesorno('', N("This package must be upgraded.\nAre you sure you want to deselect it?")) or return;
					return 1;
				    } else {
					$o->ask_warn('', N("You can not unselect this package. It must be upgraded"));
				    }
				} else { return 1 }
				return;
			    },
			    auto_deps => N("Show automatically selected packages"),
			    interactive_help_id => 'choosePackagesTree',
			    ok => N("Install"),
			    cancel => N("Previous"),
			    icons => [ { icon         => 'floppy',
					 help         => N("Load/Save selection"),
					 wait_message => N("Updating package selection"),
					 code         => sub { $o->loadSavePackagesOnFloppy($packages); 1 },
				       }, 
				       if_(0, 
				       { icon         => 'feather',
					 help         => N("Minimal install"),
					 code         => sub {
					     
					     install_any::unselectMostPackages($o);
					     pkgs::setSelectedFromCompssList($packages, { SYSTEM => 1 }, 4, $availableCorrected);
					     1;
					 } }),
				     ],
			    state => {
				      auto_deps => 1,
				      flat      => $o_limit_medium,
				     },
			  };

    $o->ask_browse_tree_info('', N("Choose the packages you want to install"), $common);
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

    my ($current_total_size, $last_size, $nb, $total_size, $start_time, $last_dtime, $_trans_progress_total);

    my $w = ugtk2->new(N("Installing"));
    $w->sync;
    my $text = gtknew('Label');
    my ($advertising, $change_time, $i);
    my $show_advertising if 0;
    $show_advertising = to_bool(@install_any::advertising_images) if !defined $show_advertising;

    my ($msg, $msg_time_remaining) = map { gtknew('Label', text => $_) } '', N("Estimating");
    my ($progress, $progress_total) = map { Gtk2::ProgressBar->new } (1..2);
    ugtk2::gtkadd($w->{window}, my $box = gtknew('VBox', spacing => 10));

    my $advertize = sub {
	my ($update) = @_;
	@install_any::advertising_images or return;
	foreach ($msg, $progress, $text) {
	    $show_advertising ? $_->hide : $_->show;
	}

	gtkdestroy($advertising) if $advertising;
	if ($show_advertising && $update) {
	    $change_time = time();
	    my $f = $install_any::advertising_images[$i++ % @install_any::advertising_images];
	    $f =~ s/\Q$::prefix// if ! -f $f;
	    log::l("advertising $f");
	    my $pl = $f; $pl =~ s/\.png$/.pl/;
	    my $icon_name = $f; $icon_name =~ s/\.png$/_icon.png/;
	    my ($draw_text, $width, $height, $border, $y_start, @text);
	    -e $pl and $draw_text = 1;
	    eval(cat_($pl)) if $draw_text;
	    my $pix = gtkcreate_pixbuf($f);
	    my $darea = gtknew('DrawingArea');
	    gtkpack($box, $advertising = !$draw_text ?
		    gtkcreate_img($f) :
		    gtkset($darea, width => $width, height => $height, expose_event => sub {
			       my (undef, undef, $dx, $dy) = $darea->allocation->values;
				   $darea->window->draw_rectangle($darea->style->bg_gc('active'), 1, 0, 0, $dx, $dy);
				   $pix->render_to_drawable($darea->window, $darea->style->bg_gc('normal'), 0, 0,
							    ($dx-$width)/2, 0, $width, $height, 'none', 0, 0);

                                   my @lines = wrap_paragraph([ @text ], $darea, $border, $width);
                                   foreach my $line (@lines) {
                                       my $layout = $darea->create_pango_layout($line->{text});
                                       my $draw_lay = sub {
                                           my ($gc, $decx) = @_;
                                           $darea->window->draw_layout($gc, $line->{'x'} + $decx, $y_start + $line->{'y'}, $layout);
                                       };
                                       $draw_lay->($darea->style->black_gc, 0);
                                       $line->{options}{bold} and $draw_lay->($darea->style->black_gc, 1);
                                   }
			   }));
	} else {
	    $advertising = undef;
	}
    };

    my $cancel = gtknew('Button', text => N("Cancel"), clicked => sub { $pkgs::cancel_install = 1 });
    my $details = gtknew('Button', text_ref => \$show_advertising, 
			 format => sub { $show_advertising ? N("Details") : N("No details") },
			 clicked => sub {
			     gtkval_modify(\$show_advertising, !$show_advertising);
			     $advertize->('update');
			 });

    $box->pack_end(gtkshow(gtknew('VBox', spacing => 5, children_loose => [
			   $msg, $progress,
			   gtknew('Table', children => [ [ N("Time remaining "), $msg_time_remaining ] ]),
			   $text,
			   $progress_total,
			   gtknew('HButtonBox', children_loose => [ $cancel, $details ]),
			  ])), 0, 1, 0);
    $details->hide if !@install_any::advertising_images;
    $w->sync;
    gtkset($msg, text => N("Please wait, preparing installation..."));
    foreach ($cancel, $details) {
	gtkset_mousecursor_normal($_->window);
    }

    $advertize->(0);

    my $oldInstallCallback = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my ($data, $type, $id, $subtype, $amount, $total) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    #- $amount and $total are used to return number of package and total size.
	    $nb = $amount;
	    $total_size = $total; $current_total_size = 0;
	    $start_time = time();
	    gtkset($msg, text => N("%d packages", $nb));
	    $w->flush;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    $progress->set_fraction(0);
	    my $p = $data->{depslist}[$id];
	    gtkset($msg, text => N("Installing package %s", $p->name));
	    $current_total_size += $last_size;
	    $last_size = $p->size;
	    gtkset($text, text => (split /\n/, c::from_utf8($p->summary))[0] || '');
	    $advertize->(1) if $show_advertising && $total_size > 20_000_000 && time() - $change_time > 20;
	    $w->flush;
	} elsif ($type eq 'inst' && $subtype eq 'progress') {
	    $progress->set_fraction($total ? $amount / $total : 0);

	    my $dtime = time() - $start_time;
	    my $ratio = 
	      $total_size == 0 ? 0 :
		pkgs::size2time($current_total_size + $amount, $total_size) / pkgs::size2time($total_size, $total_size);
	    $ratio >= 1 and $ratio = 1;
	    my $total_time = $ratio ? $dtime / $ratio : time();

	    $progress_total->set_fraction($ratio);
	    if ($dtime != $last_dtime && $current_total_size > 80_000_000) {
		gtkset($msg_time_remaining, text => formatTime(10 * round(max($total_time - $dtime, 0) / 10) + 10));
		$last_dtime = $dtime;
	    }
	    $w->flush;
	} else { goto $oldInstallCallback }
    };
    #- the modification is not local as the box should be living for other package installation.
    undef *install_any::changeMedium;
    *install_any::changeMedium = sub {
	my ($method, $medium) = @_;

	#- if not using a cdrom medium or an iso image, always abort.
	return if !install_any::method_allows_medium_change($method);

	my $name = install_medium::by_id($medium, $o->{packages})->{descr};
	local $| = 1; print "\a";
	my $time = time();
	my $r = $name !~ /commercial/i || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX(install_messages::com_license()), [ N_("Accept"), N_("Refuse") ], "Accept") eq "Accept");
	if ($method =~ /-iso$/) {
	    $r = install_any::changeIso($name);
	} else {
	    $r &&= $o->ask_okcancel('', N("Change your Cd-Rom!
Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you do not have it, press Cancel to avoid installation from this Cd-Rom.", $name), 1);
	}
	#- add the elapsed time (otherwise the predicted time will be rubbish)
	$start_time += time() - $time;
	return $r;
    };
    my $install_result;
    catch_cdie { $install_result = $o->install_steps::installPackages($packages) }
      sub {
	  log::l("catch_cdie: $@");
          my $time = time();
	  if ($@ =~ /^error ordering package list: (.*)/) {
	      $o->ask_yesorno('', [
N("There was an error ordering packages:"), $1, N("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  } elsif ($@ =~ /^error installing package list: (.*)/) {
	      $o->ask_yesorno('', [
N("There was an error installing packages:"), $1, N("Go on anyway?") ], 1) and return 1;
	      ${$_[0]} = "already displayed";
	  }
	  $w->destroy;
          #- add the elapsed time (otherwise the predicted time will be rubbish)
          $start_time += time() - $time;
	  0;
      };
    if ($pkgs::cancel_install) {
	$pkgs::cancel_install = 0;
	die 'already displayed';
    }
    $w->destroy;
    $install_result;
}

sub summary_prompt {
    my ($o, $l, $check_complete) = @_;

    my $w = ugtk2->new(N("Summary"));

    my $set_entry_labels;
    my @table;
    my $group;
    foreach my $e (@$l) {
	if ($group ne $e->{group}) {
	    $group = $e->{group};
	    push @table, [ gtknew('HBox', children_tight => [ $group ]), '' ];
	}
	$e->{widget} = gtknew('WrappedLabel', width => $::real_windowwidth * 0.72);

	push @table, [], [ gtknew('HBox', spacing => 30, children_tight => [ '', $e->{widget} ]),
			   gtknew('Button', text => N("Configure"), clicked => sub { 
						 $w->{rwindow}->hide;
						 $e->{clicked}(); 
						 $w->{rwindow}->show;
						 $set_entry_labels->();
					     }) ];
    }

    $set_entry_labels = sub {
	foreach (@$l) {
	    my $t = $_->{val}() || '<span foreground="red">' . N("not configured") . '</span>';
	    $t =~ s/&/&amp;/g;
	    gtkset($_->{widget}, text_markup => $_->{label} . ' - ' . $t);
	}
    };
    $set_entry_labels->();

    my $help_sub = $o->interactive_help_sub_display_id('summary');

    ugtk2::gtkadd($w->{window},
	   gtknew('VBox', spacing => 5, children => [
		    1, gtknew('ScrolledWindow', child => gtknew('Table', mcc => 1, children => \@table)),
		    0, $w->create_okcancel(undef, '', '', if_($help_sub, [ N("Help"), $help_sub, 1 ]))
		  ]));

    $w->main($check_complete);
}

sub deselectFoundMedia {
    #- group by CD
    my ($o, $hdlists, $mediumsize) = @_;
    my %cdlist;
    my @hdlist2;
    my @corresp;
    my $i = 0;
    my $totalsize = 0;
    foreach (@$hdlists) {
	my $cd = install_medium->new(descr => $_->[3])->get_cd_number;
	if (!$cd || !@{$cdlist{$cd} || []}) {
	    push @hdlist2, $_;
	    $corresp[$i] = [ $i ];
	} else {
	    $corresp[$i] = [];
	    push @{$corresp[$cdlist{$cd}[0]]}, $i;
	}
	if ($cd) {
	    $cdlist{$cd} ||= [];
	    push @{$cdlist{$cd}}, $i;
	}
	$totalsize >= 0 and $totalsize += $mediumsize->{$_->[0]};
	++$i;
    }
    $totalsize ||= -1; #- don't check size, total medium size unknown
    my @selection = (1) x @hdlist2;
    my $copy_rpms_on_disk = 0;
    my $ask_copy_rpms_on_disk = $o->{method} !~ /iso/i;
    #- check available size for copying rpms from infos in hdlists file
    if ($ask_copy_rpms_on_disk && $totalsize >= 0) {
	my $availvar = install_any::getAvailableSpace_mounted("$::prefix/var");
	$availvar /= 1024 * 1024; #- Mo
	log::l("totalsize=$totalsize, avail on $::prefix/var=$availvar");
	$ask_copy_rpms_on_disk = $totalsize < $availvar * 0.6;
    }
    if ($ask_copy_rpms_on_disk) {
	#- don't be afraid, cleanup old RPMs if upgrade
	eval { rm_rf("$::prefix/var/ftp/pub/Mandrivalinux", "$::prefix/var/ftp/pub/Mandrivalinux") if $o->{isUpgrade} };
	my $w = ugtk2->new("");
	$i = -1;
	$w->sync;
	ugtk2::gtkadd(
	    $w->{window},
	    gtkpack(
		Gtk2::VBox->new(0, 5),
		Gtk2::WrappedLabel->new(N("The following installation media have been found.
If you want to skip some of them, you can unselect them now.")),
		(map {
			++$i;
			my $b = gtknew('CheckButton', text => $_->[3], active_ref => \$selection[$i]);
			$b->set_sensitive(0) unless $i;
			$b;
		    } @hdlist2),
		gtknew('HSeparator'),
		Gtk2::WrappedLabel->new(N("You have the option to copy the contents of the CDs onto the hard drive before installation.
It will then continue from the hard drive and the packages will remain available once the system is fully installed.")),
		gtknew('CheckButton', text => N("Copy whole CDs"), active_ref => \$copy_rpms_on_disk),
		gtknew('HSeparator'),
		gtknew('HBox', children_tight => [
		    gtknew('Button', text => N("Next"), clicked => sub { Gtk2->main_quit }),
		]),
	    ),
	);
	$w->main;
    }
    $i = -1;
    my $l = [ grep { $selection[++$i] } @hdlist2 ];
    my @l2; $i = 0;
    foreach my $c (@$l) {
	++$i while $hdlists->[$i][3] ne $c->[3];
	push @l2, $hdlists->[$_] foreach @{$corresp[$i]};
    }
    log::l("keeping media " . join ',', map { $_->[1] } @l2);
    $o->{mediumsize} = $totalsize;
    (\@l2, $copy_rpms_on_disk);
}

1;
