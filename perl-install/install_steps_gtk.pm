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

    if ($ENV{DISPLAY} =~ /^:\d/ && !$::testing || $ENV{DISPLAY} ne $wanted_DISPLAY) { #- is the display local or distant?
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

		push @options, if_(!$::globetrotter, '-kb'), '-allowMouseOpenFail', '-xf86config', $f if arch() !~ /^sparc/ && arch() ne 'ppc';
		push @options, 'tty7', '-dpms', '-s', '240';

		#- old weird servers: Xpmac and Xsun
		push @options, cat_('/proc/cmdline') !~ /ofonly/ ? ('-mode', '17', '-depth', '32') : '-mach64' if $server =~ /Xpmac/;
		push @options, '-fp', '/usr/X11R6/lib/X11/fonts:unscaled' if $server =~ /Xsun|Xpmac/;
	    }

	    if (!fork()) {
		c::setsid();
		exec $server, @options or c::_exit(1);
	    }
	    my $nb;
	    foreach (1..60) {
		sleep 1;
		log::l("Server died"), return 0 if !fuzzy_pidofs(qr/\b$server\b/);
		$nb++ if xf86misc::main::Xtest($wanted_DISPLAY);
		if ($nb > 2) { #- one succeeded test is not enough :-(
		    $ugtk2::force_focus = 1;
		    log::l("AFAIK X server is up");
		    return 1;
		}
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
	} elsif (arch() =~ /ia64|x86_64/) {
	    require Xconfig::card;
	    my ($card) = Xconfig::card::probe();
	    @servers = map { if_($_, "Driver:$_") } $card && $card->{Driver}, 'fbdev';
	} elsif (arch() eq "ppc") {
	    @servers = qw(Xpmac);
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
	    my $dir = "/usr/X11R6/bin";
	    my ($prog, $Driver) = /Driver:(.*)/ ? ('Xorg', $1) : /Xsun|Xpmac|Xnest|^X_move$/ ? $_ : "XF86_$_";
	    unless (-x "$dir/$prog") {
		unlink $_ foreach glob_("$dir/X*");
		install_any::getAndSaveFile("Mandrake/mdkinst$dir/$prog", "$dir/$prog") or die "failed to get server $prog: $!";
		chmod 0755, "$dir/$prog";
	    }
	    if (/FB/i) {
		!$o->{vga16} && $o->{allowFB} or next;

		$o->{allowFB} = &$launchX($prog, $Driver) #- keep in mind FB is used.
		  and goto OK;
	    } else {
		$o->{vga16} = 1 if /VGA16/;
		&$launchX($prog, $Driver) and goto OK;
	    }
            $::move and print("can't launch graphical mode :(\n"), c::_exit(1);
	}
	return undef;
    }
  OK:
    $ENV{DISPLAY} = $wanted_DISPLAY;
    install_gtk::init_gtk($o);
    install_gtk::init_sizes();
    install_gtk::install_theme($o);
    install_gtk::create_logo_window($o);
    install_gtk::create_steps_window($o);

    $ugtk2::grab = 1;
    $ugtk2::force_center_at_pos = [ $::rootwidth - $::windowwidth, $::logoheight, $::windowwidth, $::windowheight ];

    $o = (bless {}, ref($type) || $type)->SUPER::new($o);
    $o->interactive::gtk::new;
    $o;
}

sub enteringStep {
    my ($o, $step) = @_;

    printf "Entering step `%s'\n", $o->{steps}{$step}{text};
    $o->SUPER::enteringStep($step);
    install_gtk::update_steps_position($o);
#    install_gtk::create_help_window($o); #- HACK: without this it doesn't work (reaches step doPartitionDisks then fail)
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
    my ($o, $first_time) = @_;
    $o->SUPER::selectLanguage;
  
    $o->ask_warn('',
formatAlaTeX(N("Your system is low on resources. You may have some problem installing
Mandrakelinux. If that occurs, you can try a text install instead. For this,
press `F1' when booting on CDROM, then enter `text'."))) if $first_time && availableRamMB() < 70; # 70MB

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

    while (1) {
	my $x_protocol_changed = mouse::change_mouse_live($mouse, \%old);
	mouse::test_mouse_install($mouse, $x_protocol_changed) and return;

	%old = %$mouse;
	$o->SUPER::selectMouse(1);
	$mouse = $o->{mouse};
    } 
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $val) = @_;

    my $w = ugtk2->new('');
    my $tips = Gtk2::Tooltips->new;
    my $w_size = Gtk2::Label->new(&$size_to_display);

    my $entry = sub {
	my ($e) = @_;
	my $text = translate($o->{compssUsers}{$e}{label});
	my $help = translate($o->{compssUsers}{$e}{descr});

	my $check = Gtk2::CheckButton->new($text);
	$check->set_active($val->{$e});
	$check->signal_connect(clicked => sub { 
	    $val->{$e} = $check->get_active;
	    $w_size->set_label(&$size_to_display);
	});
	gtkset_tip($tips, $check, $help);
	#gtkpack_(Gtk2::HBox->new(0, 0), 0, gtkpng($file), 1, $check);
	$check;
    };
    my $entries_in_path = sub {
	my ($path) = @_;
	translate($path), map { $entry->($_) } grep { $o->{compssUsers}{$_}{path} eq $path } @{$o->{compssUsersSorted}};
    };
    gtkadd($w->{window},
	   gtkpack_($w->create_box_with_title(N("Package Group Selection")),
		    1, gtkpack_(Gtk2::VBox->new(0, 0),
			   1, gtkpack_(Gtk2::HBox->new(0, 0),
			        $o->{meta_class} eq 'server' ? (
				   1, gtkpack(Gtk2::VBox->new(0, 0), 
					   $entries_in_path->('Workstation'),
					   '',
					   $entries_in_path->('Server'),
					  ),
				   1, gtkpack(Gtk2::VBox->new(0, 0), 
					   $entries_in_path->('Graphical Environment'),
					   '',
					   $entries_in_path->('Development'),
					   '',
					   $entries_in_path->('Utilities'),
					  ),
				) : $o->{meta_class} eq 'desktop' ? (
				   1, gtkpack(Gtk2::VBox->new(0, 0), 
					   $entries_in_path->('Workstation'),
					  ),
				) : (
				   1, gtkpack(Gtk2::VBox->new(0, 0), 
					   $entries_in_path->('Workstation'),
					   '',
					   $entry->('Development|Development'),
					   $entry->('Development|Documentation'),
					   $entry->('Development|LSB'),
					  ),
				   0, gtkpack(Gtk2::VBox->new(0, 0), 
					   $entries_in_path->('Server'),
					   '',
					   $entries_in_path->('Graphical Environment'),
					  ),
				),
			   )),
		   1, '',
		   0, gtkadd(Gtk2::HBox->new(0, 0),
			  gtksignal_connect(Gtk2::Button->new(N("Help")), clicked => $o->interactive_help_sub_display_id('choosePackages')),
			  $w_size,
			  if_($individual, do {
			      my $check = Gtk2::CheckButton->new(N("Individual package selection"));
			      $check->set_active($$individual);
			      $check->signal_connect(clicked => sub { $$individual = $check->get_active });
			      $check;
			  }),
			  gtksignal_connect(Gtk2::Button->new(N("Next")), clicked => sub { Gtk2->main_quit }),
			 ),
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
				pkgs::packageMedium($packages, $p)->{selected} or return;
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
				    foreach my $root (@{$o->{compssUsersSorted}}) {
					my (%fl, @firstchoice, @others);
					#$fl{$_} = $o->{compssUsersChoice}{$_} foreach @{$o->{compssUsers}{$root}{flags}}; #- FEATURE:improve choce of packages...
					$fl{$_} = 1 foreach @{$o->{compssUsers}{$root}{flags}};
					foreach my $p (@{$packages->{depslist}}) {
					    !$o_limit_medium || pkgs::packageMedium($packages, $p) == $o_limit_medium or next;
					    my @flags = $p->rflags;
					    next if !($p->rate && any { any { !/^!/ && $fl{$_} } split('\|\|') } @flags);
					    $p->rate >= 3 ?
					      push(@firstchoice, $p->name) :
						push(@others,    $p->name);
					}
					my $root2 = join('|', map { translate($_) } split('\|', $root));
					$add_node->($_, $root2)                    foreach sort @firstchoice;
					$add_node->($_, $root2 . '|' . N("Other")) foreach sort @others;
				    }
				}
			    },
			    get_info => sub {
				my $p = pkgs::packageByName($packages, $_[0]) or return '';
				pkgs::extractHeaders($o->{prefix}, [$p], $packages->{mediums});

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
				    $error = [ N("You can't select/unselect this package"),
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
				    $error = N("You can't select this package as there is not enough space left to install it");
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
				    $o->ask_warn('', N("This is a mandatory package, it can't be unselected"));
				} elsif ($p->flag_installed && !$p->flag_upgrade) {
				    $o->ask_warn('', N("You can't unselect this package. It is already installed"));
				} elsif ($p->flag_selected && $p->flag_installed) {
				    if ($::expert) {
					$o->ask_yesorno('', N("This package must be upgraded.\nAre you sure you want to deselect it?")) or return;
					return 1;
				    } else {
					$o->ask_warn('', N("You can't unselect this package. It must be upgraded"));
				    }
				} else { return 1 }
				return;
			    },
			    auto_deps => N("Show automatically selected packages"),
			    interactive_help_id => 'choosePackagesTree',
			    ok => N("Install"),
			    cancel => N("Previous"),
			    icons => [ { icon         => 'floppy',
					 help         => N("Load/Save on floppy"),
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
    my $text = Gtk2::Label->new;
    my ($advertising, $change_time, $i);
    my $show_advertising if 0;
    $show_advertising = to_bool(@install_any::advertising_images) if !defined $show_advertising;
    my $detail_or_not = sub { $show_advertising ? N("Details") : N("No details") };
    my ($msg, $msg_time_remaining, $msg_time_total) = map { Gtk2::Label->new($_) } '', (N("Estimating")) x 2;
    my ($progress, $progress_total) = map { Gtk2::ProgressBar->new } (1..2);
    gtkadd($w->{window}, my $box = Gtk2::VBox->new(0,10));
    $box->pack_end(gtkshow(gtkpack(Gtk2::VBox->new(0,5),
			   $msg, $progress,
			   create_packtable({},
					    [N("Time remaining "), $msg_time_remaining],
#					    [N("Total time "), $msg_time_total],
					   ),
			   $text,
			   $progress_total,
			   gtkadd(create_hbox(),
				  my $cancel = Gtk2::Button->new(N("Cancel")),
				  my $details = Gtk2::Button->new($detail_or_not->()),
				  ),
			  )), 0, 1, 0);
    $details->hide if !@install_any::advertising_images;
    $w->sync;
    $msg->set_label(N("Please wait, preparing installation..."));
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
	    my $pl = $f; $pl =~ s/\.png$/.pl/;
	    my $icon_name = $f; $icon_name =~ s/\.png$/_icon.png/;
	    my ($draw_text, $width, $height, $border, $y_start, @text);
	    -e $pl and $draw_text = 1;
	    eval(cat_($pl)) if $draw_text;
	    my $pix = gtkcreate_pixbuf($f);
	    my $dbl_area;
	    my $darea = Gtk2::DrawingArea->new;
	    gtkpack($box, $advertising = !$draw_text ?
		    gtkcreate_img($f) :
		    gtksignal_connect(gtkset_size_request($darea, $width, $height), expose_event => sub {
			       my (undef, undef, $dx, $dy) = $darea->allocation->values;
			       if (!defined($dbl_area)) {
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
			       }
			   }));
	} else {
	    $advertising = undef;
	}
    };

    $cancel->signal_connect(clicked => sub { $pkgs::cancel_install = 1 });
    $details->signal_connect(clicked => sub {
	invbool \$show_advertising;
	$details->set_label($detail_or_not->());
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
	    $msg->set_label(N("%d packages", $nb));
	    $w->flush;
	} elsif ($type eq 'inst' && $subtype eq 'start') {
	    $progress->set_fraction(0);
	    my $p = $data->{depslist}[$id];
	    $msg->set_label(N("Installing package %s", $p->name));
	    $current_total_size += $last_size;
	    $last_size = $p->size;
	    $text->set_label((split /\n/, c::from_utf8($p->summary))[0] || '');
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
		$msg_time_total->set_label(formatTime(10 * round($total_time / 10) + 10));
#-		$msg_time_total->set_label(formatTimeRaw($total_time) . "  " . formatTimeRaw($dtime / $ratio2));
		$msg_time_remaining->set_label(formatTime(10 * round(max($total_time - $dtime, 0) / 10) + 10));
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
	return unless method_allows_medium_change($method) && !$::oem;

	my $name = pkgs::mediumDescr($o->{packages}, $medium);
	local $| = 1; print "\a";
	my $time = time();
	my $r = $name !~ /commercial/i || ($o->{useless_thing_accepted2} ||= $o->ask_from_list_('', formatAlaTeX(install_messages::com_license()), [ N_("Accept"), N_("Refuse") ], "Accept") eq "Accept");
	if ($method =~ /-iso$/) {
	    $r = install_any::changeIso($name);
	} else {
	    $r &&= $o->ask_okcancel('', N("Change your Cd-Rom!
Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you don't have it, press Cancel to avoid installation from this Cd-Rom.", $name), 1);
	}
	#- add the elapsed time (otherwise the predicted time will be rubbish)
	$start_time += time() - $time;
	return $r;
    };
    my $install_result;
    catch_cdie { $install_result = $o->install_steps::installPackages($packages) }
      sub {
	  log::l("catch_cdie: $@");
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

    my $w = ugtk2->new('');

    my $set_entry_labels;
    my @table;
    my %group;
    foreach my $e (@$l) {
	$group{$e->{group}} ||= do {
	    push @table, [ gtkpack__(Gtk2::HBox->new(0, 0), $e->{group}), '' ];
	};
	$e->{widget} = Gtk2::Label->new;
	$e->{widget}->set_property(wrap => 1);
	$e->{widget}->set_size_request($::real_windowwidth * 0.72, -1);
	push @table, [], [ gtkpack__(Gtk2::HBox->new(0, 30), '', $e->{widget}),
			   gtksignal_connect(Gtk2::Button->new(N("Configure")), clicked => sub { 
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
	    $_->{widget}->set_markup($_->{label} . ' - ' . $t);
	}
    };
    $set_entry_labels->();

    my $help_sub = $o->interactive_help_sub_display_id('summary');

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    1, create_scrolled_window(create_packtable({ mcc => 1 }, @table)),
		    0, $w->create_okcancel(undef, '', '', if_($help_sub, [ N("Help"), $help_sub, 1 ]))
		  ));

    $w->main($check_complete);
}

1;
