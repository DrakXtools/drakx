package install::steps_gtk; # $Id$

use diagnostics;
use strict;
use feature 'state';
use vars qw(@ISA);

@ISA = qw(install::steps_interactive interactive::gtk);

#-######################################################################################
#- misc imports
#-######################################################################################
use install::pkgs;
use install::steps_interactive;
use interactive::gtk;
use xf86misc::main;
use common;
use mygtk2;
use ugtk2 qw(:helpers :wrappers :create);
use devices;
use modules;
use install::gtk;
use install::any;
use mouse;
use install::help::help;
use log;

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    $ENV{DISPLAY} ||= $o->{display} || ":0";
    my $wanted_DISPLAY = $::testing && -x '/usr/bin/Xnest' ? ':9' : $ENV{DISPLAY};

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
	    } else {
		install::gtk::createXconf($f, @{$o->{mouse}}{'Protocol', 'device'}, $o->{mouse}{wacom}[0], $Driver);

		push @options, '-allowMouseOpenFail', '-xf86config', $f if arch() !~ /^sparc/;
		push @options, 'tty7', '-s', '240';
		push @options, '-nolisten', 'tcp';

		#- old weird servers: Xsun
		push @options, '-fp', '/usr/share/fonts:unscaled' if $server =~ /Xsun/;
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
	    my $start_time = time();
	    foreach (1..60) {
		log::l("waiting for the server to start ($_ $nb)");
		log::l("Server died"), return 0 if !fuzzy_pidofs(qr/\b$server\b/);
		$nb++ if xf86misc::main::Xtest($wanted_DISPLAY);
		if ($nb > 2) { #- one succeeded test is not enough :-(
		    log::l("AFAIK X server is up");
		    return 1;
		}
		time() - $start_time < 60 or last;
		time() - $start_time > 8 and print N("Xorg server is slow to start. Please wait..."), "\n";
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
    install::gtk::init_gtk($o);
    install::gtk::init_sizes($o);
    install::gtk::install_theme($o);
    install::gtk::create_logo_window($o);
    install::gtk::create_steps_window($o);

    $ugtk2::grab = 1;

    $o = (bless {}, ref($type) || $type)->SUPER::new($o);
    $o->interactive::gtk::new;
    $o;
}

sub enteringStep {
    my ($o, $step) = @_;

    printf "Entering step `%s'\n", common::remove_translate_context($o->{steps}{$step}{text});
    if (my @banner_elts = ($o->{steps}{$step}{banner_icon}, translate($o->{steps}{$step}{banner_title}))) {
        set_default_step_items(@banner_elts);
    }
    $o->SUPER::enteringStep($step);
    install::gtk::update_steps_position($o);
}
sub leavingStep {
    my ($o, $step) = @_;
    $o->SUPER::leavingStep($step);
}


sub charsetChanged {
    my ($o) = @_;
    Gtk2->set_locale;
    install::gtk::load_font($o);
    install::gtk::create_steps_window($o);
}


sub interactive_help_has_id {
    my ($_o, $id) = @_;
    exists $install::help::help::{$id};
}

sub interactive_help_get_id {
    my ($_o, @l) = @_;
    @l = map { 
	join("\n\n", map { s/\n/ /mg; $_ } split("\n\n", translate($install::help::help::{$_}->())));
    } grep { exists $install::help::help::{$_} } @l;
    join("\n\n\n", @l);
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

sub reallyChooseDesktop {
    my ($o, $title, $message, $choices) = @_;

    my $w = ugtk2->new($title);

    my $sizegrp = Gtk2::SizeGroup->new('horizontal');
    my $choice = $choices->[0];
    my $prev;
    my @l = map {
	my $val = $_;
	$prev = gtknew('RadioButton', child =>
                      gtknew('HBox', border_width => 15, spacing => 10, children => [ 
                          0, gtknew('Image', file => "desktop-$val->[0]", size_group => $sizegrp),
                          1, gtknew('Label', text => $val->[1]),
                      ]),
		       toggled => sub { $choice = $val if $_[0]->get_active },
		       $prev ? (group => $prev->get_group) : ());
	$prev->signal_connect(key_press_event => sub {
				  my (undef, $event) = @_;
				  if (!$event || ($event->keyval & 0x7f) == 0xd) {
				      Gtk2->main_quit;
				  }
			      });
	$prev
    } @$choices;

    ugtk2::gtkadd($w->{window},
	   gtknew('VBox', children => [
		    0, gtknew('WrappedLabel', text => $message),
		    (map { (1, $_) } @l),
		    0, $w->create_okcancel(N("Next"), undef),
		]));
    $w->main;
    
    $choice;
}

sub reallyChooseGroups {
    my ($o, $size_to_display, $individual, $_compssUsers) = @_;

    my $w = ugtk2->new(N("Package Group Selection"), icon => 'banner-sys');
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
    if (!ref $o->{gtk_display_compssUsers}) { install::any::load_rate_files($o) }
    ugtk2::gtkadd($w->{window},
	   gtknew('VBox', children => [
		    1, $o->{gtk_display_compssUsers}->($entry),
		    1, '',
		    0, if_($individual,
			      gtknew('CheckButton', text => N("Individual package selection"), active_ref => $individual),
			  ),
		    0, gtknew('HBox', children_loose => [
			  gtknew('Button', text => N("Help"), clicked => $o->interactive_help_sub_display_id('choosePackages')),
			  $w_size,
			  gtknew('Button', text => N("Next"), clicked => sub { Gtk2->main_quit }),
			 ]),
		  ]),
	  );
    $w->main;
    1;
}

sub choosePackagesTree {
    my ($o, $packages, $o_limit_medium) = @_;

    my $available = install::any::getAvailableSpace($o);
    my $availableCorrected = install::pkgs::invCorrectSize($available / sqr(1024)) * sqr(1024);

    my $common;
    $common = {             get_status => sub {
				my $size = install::pkgs::selectedSize($packages);
				N("Total size: %d / %d MB", install::pkgs::correctSize($size / sqr(1024)), $available / sqr(1024));
			    },
			    node_state => sub {
				my $p = install::pkgs::packageByName($packages, $_[0]) or return;
				install::pkgs::packageMedium($packages, $p)->{selected} or return;
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
					     grep { !$o_limit_medium || install::pkgs::packageMedium($packages, $_) == $o_limit_medium }
					     grep { $_ && $_->arch ne 'src' }
					     @{$packages->{depslist}}) {
					$add_node->($_, undef);
				    }
				} else {
				    foreach my $root (@{$o->{compssUsers}}) {
					my (@firstchoice, @others);
					my %fl = map { ("CAT_$_" => 1) } @{$root->{flags}};
					foreach my $p (@{$packages->{depslist}}) {
					    !$o_limit_medium || install::pkgs::packageMedium($packages, $p) == $o_limit_medium or next;
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
				my $p = install::pkgs::packageByName($packages, $_[0]) or return '';
				install::pkgs::extractHeaders([$p], $packages->{media});

				my $imp = translate($install::pkgs::compssListDesc{$p->flag_base ? 5 : $p->rate});

                                my $tag = { 'foreground' => 'royalblue3' };
				$@ ? N("Bad package") :
				  [ [ N("Name: "), $tag ], [ $p->name . "\n" ],
                                    [ N("Version: "), $tag ], [ $p->version . '-' . $p->release . "\n" ],
                                    [ N("Size: "), $tag ], [ N("%d KB\n", $p->size / 1024) ],
                                    if_($imp, [ N("Importance: "), $tag ], [ "$imp\n" ]),
                                    [ "\n" ], [ formatLines($p->description) ] ];
			    },
			    toggle_nodes => sub {
				my $set_state = shift @_;
				my $isSelection = 0;
				my %l = map { my $p = install::pkgs::packageByName($packages, $_);
					      $isSelection ||= !$p->flag_selected;
					      $p->id => 1 } @_;
				my $state = $packages->{state} ||= {};
				$packages->{rpmdb} ||= install::pkgs::rpmDbOpen(); #- WORKAROUND
				my @l = $isSelection ? $packages->resolve_requested($packages->{rpmdb}, $state, \%l,
										    callback_choices => \&install::pkgs::packageCallbackChoices) :
						       $packages->disable_selected($packages->{rpmdb}, $state,
										   map { $packages->{depslist}[$_] } keys %l);
				my $size = install::pkgs::selectedSize($packages);
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
				} elsif (install::pkgs::correctSize($size / sqr(1024)) > $available / sqr(1024)) {
				    $error = N("You can not select this package as there is not enough space left to install it");
				} elsif (@l > @_ && $common->{state}{auto_deps}) {
				    $o->ask_okcancel(N("Confirmation"), [ $isSelection ? 
							   N("The following packages are going to be installed") :
							   N("The following packages are going to be removed"),
							       formatList(20, sort(map { $_->name } @l)) ], 1) or $error = ''; #- defined
				}
				if (defined $error) {
				    $o->ask_warn('', $error) if $error;
				    #- disable selection (or unselection).
				    $packages->{rpmdb} ||= install::pkgs::rpmDbOpen(); #- WORKAROUND
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
				grep { my $p = install::pkgs::packageByName($packages, $_); $p && !$p->flag_base } @_;
			    },
			    grep_unselected => sub {
				grep { !install::pkgs::packageByName($packages, $_)->flag_selected } @_;
			    },
			    check_interactive_to_toggle => sub {
				my $p = install::pkgs::packageByName($packages, $_[0]) or return;
				if ($p->flag_base) {
				    $o->ask_warn('', N("This is a mandatory package, it can not be unselected"));
				} elsif ($p->flag_installed && !$p->flag_upgrade) {
				    $o->ask_warn('', N("You can not unselect this package. It is already installed"));
				} elsif ($p->flag_selected && $p->flag_installed) {
				    $o->ask_warn('', N("You can not unselect this package. It must be upgraded"));
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
					     
					     install::any::unselectMostPackages($o);
					     install::pkgs::setSelectedFromCompssList($packages, { SYSTEM => 1 }, 4, $availableCorrected);
					     1;
					 } }),
				     ],
			    state => {
				      auto_deps => 1,
				      flat      => $o_limit_medium,
				     },
			  };

    $o->ask_browse_tree_info(N("Software Management"), N("Choose the packages you want to install"), $common);
}

#------------------------------------------------------------------------------
sub beforeInstallPackages {
    my ($o) = @_;    
    $o->SUPER::beforeInstallPackages;
    install::any::copy_advertising($o);
}

#------------------------------------------------------------------------------
sub installPackages {
    my ($o, $packages) = @_;

    my ($current_total_size, $last_size, $nb, $total_size, $last_dtime, $_trans_progress_total);

    local $::noborderWhenEmbedded = 1;
    my $w = ugtk2->new(N("Installing"), icon => 'banner-sys');
    state $show_advertising;

    my $pkg_log_widget = gtknew('TextView', editable => 0);
    my ($advertising_image, $change_time, $i);
    my $advertize = sub {
	my ($update) = @_;

	@install::any::advertising_images && $show_advertising && $update or return;
	
	$change_time = time();
	my $f = $install::any::advertising_images[$i++ % @install::any::advertising_images];
	log::l("advertising $f");
	gtkval_modify(\$advertising_image, $f);

	if (my $banner = $w->{window}{banner}) {
	    my ($title);
	    my $pl = $f; $pl =~ s/\.png$/.pl/;
	    eval(cat_($pl)) if -e $pl;    
	    $banner->{text} = $title;
	    Gtk2::Banner::set_pixmap($banner);
	}
    };

    my $cancel = gtknew('Button', text => N("Cancel"), clicked => sub { $install::pkgs::cancel_install = 1 });
    my $details = gtknew('Button', text_ref => \$show_advertising, 
			 format => sub { $show_advertising ? N("Details") : N("No details") },
			 clicked => sub {
			     gtkval_modify(\$show_advertising, !$show_advertising);
			     $pkg_log_widget->{to_bottom}->('force');
			 });

    ugtk2::gtkadd($w->{window}, my $box = gtknew('VBox', children_tight => [ 
	gtknew('Image_using_pixmap', file_ref => \$advertising_image, show_ref => \$show_advertising),
    ]));

    $box->pack_end(gtkshow(gtknew('VBox', border_width => 7, spacing => 3, children_loose => [
	gtknew('ScrolledWindow', child => $pkg_log_widget, 
	       hide_ref => \$show_advertising, height => 250, to_bottom => 1),
	gtknew('ProgressBar', fraction_ref => \ (my $pkg_progress), hide_ref => \$show_advertising),
	gtknew('Table', children => [ [ 
	    N("Time remaining "), 
	    gtknew('Label', text_ref => \ (my $msg_time_remaining = N("(estimating...)"))),
	] ]),
	gtknew('HBox', children => [
	    1, gtknew('VBox', children_centered => [ gtknew('ProgressBar', fraction_ref => \ (my $progress_total), height => 25) ]),
	    0, gtknew('HButtonBox', children_loose => [ $cancel, $details ]),
	]),
    ])), 0, 1, 0);
    
    #- for the hide_ref & show_ref to work, we must set $show_advertising after packing
    gtkval_modify(\$show_advertising, 
		  defined $show_advertising ? $show_advertising : to_bool(@install::any::advertising_images));

    $details->hide if !@install::any::advertising_images;
    $w->sync;
    foreach ($cancel, $details) {
	gtkset_mousecursor_normal($_->window);
    }

    $advertize->(0);

    local *install::steps::installCallback = sub {
	my ($packages, $type, $id, $subtype, $amount, $total) = @_;
	if ($type eq 'user' && $subtype eq 'install') {
	    #- $amount and $total are used to return number of package and total size.
	    $nb = $amount;
	    $total_size = $total; $current_total_size = 0;
	    $o->{install_start_time} = time();
	    mygtk2::gtkadd($pkg_log_widget, text => P("%d package", "%d packages", $nb, $nb));
	    $w->flush;
	} elsif ($type eq 'open') {
	    gtkval_modify(\$pkg_progress, 0);
	    my $p = $packages->{depslist}[$id];
	    mygtk2::gtkadd($pkg_log_widget, text => sprintf("\n%s: %s", $p->name, translate($p->summary)));
	    $current_total_size += $last_size;
	    $last_size = $p->size;
	    $advertize->(1) if $show_advertising && $total_size > 20_000_000 && time() - $change_time > 20;
	    $w->flush;
	} elsif ($type eq 'inst' && $subtype eq 'progress') {
	    gtkval_modify(\$pkg_progress, $total ? $amount / $total : 0);

	    my $dtime = time() - $o->{install_start_time};
	    my $ratio = 
	      $total_size == 0 ? 0 :
		install::pkgs::size2time($current_total_size + $amount, $total_size) / install::pkgs::size2time($total_size, $total_size);
	    $ratio >= 1 and $ratio = 1;
	    my $total_time = $ratio ? $dtime / $ratio : time();

	    gtkval_modify(\$progress_total, $ratio);
	    if ($dtime != $last_dtime && $current_total_size > 80_000_000) {
		gtkval_modify(\$msg_time_remaining, formatTime(10 * round(max($total_time - $dtime, 0) / 10) + 10));
		$last_dtime = $dtime;
	    }
	    $w->flush;
	}
    };
    my $install_result;
    catch_cdie { $install_result = $o->install::steps::installPackages($packages) }
      sub { 
	  my $rc = install::steps_interactive::installPackages__handle_error($o, $_[0]);
	  $rc or $w->destroy;
	  $rc;
      };
    if ($install::pkgs::cancel_install) {
	$install::pkgs::cancel_install = 0;
	die 'already displayed';
    }
    $w->destroy;
    $install_result;
}

sub summary_prompt {
    my ($o, $l, $check_complete) = @_;

    my $w = ugtk2->new(N("Summary"), icon => 'banner-summary');

    my $set_entry_labels;
    my (@table, @widget_list);
    my ($group, $count);
    foreach my $e (@$l) {
	if ($group ne $e->{group}) {
	    push @widget_list, [ @table ] if @table;
	    @table = ();
	    push @widget_list, gtknew('HSeparator', height => 8) if $count;
	    $count++;
	    $group = $e->{group};
	    push @table, [ gtknew('HBox', children_tight => [ gtknew('Title1', label => escape_text_for_TextView_markup_format($group)) ]), '' ];
	}
	$e->{widget} = gtknew('WrappedLabel', width => $::real_windowwidth * 0.72);

	push @table, [], [ gtknew('HBox', spacing => 30, children_tight => [ '', $e->{widget} ]),
			   gtknew('Button', text => N("Configure"), clicked => sub { 
						 $w->{rwindow}->hide;
						 my ($old_icon, $old_title) = get_default_step_items();
						 set_default_step_items($e->{banner_icon} || $old_icon, $e->{banner_title} || $old_title);
						 $e->{clicked}(); 
						 set_default_step_items($old_icon, $old_title);
						 $w->{rwindow}->show;
						 $set_entry_labels->();
					     }) ];
    }
    # add latest group:
    push @widget_list, [ @table ] if @table;

    $set_entry_labels = sub {
	foreach (@$l) {
	    my $t;
	    if ($_->{val}) {
		$t = $_->{val}() || '<span foreground="red">' . N("not configured") . '</span>';
		$t =~ s/&/&amp;/g;
	    }
	    gtkset($_->{widget}, text_markup => $_->{label} . ($t ? " - $t" : ''));
	}
    };
    $set_entry_labels->();

    my $help_sub = $o->interactive_help_sub_display_id('summary');

    ugtk2::gtkadd($w->{window},
	   gtknew('VBox', spacing => 5, children => [
		    1, gtknew('ScrolledWindow',
                        child => gtknew('VBox', children_tight => [ map {
                            ref($_) eq 'ARRAY' ? gtknew('Table', mcc => 1, row_spacings => 2, children => $_) : $_;
                        } @widget_list ])),
		    0, $w->create_okcancel(undef, '', '', if_($help_sub, [ N("Help"), $help_sub, 1 ]))
		  ]));

    $w->main($check_complete);
}

#- group by CD
sub ask_deselect_media__copy_on_disk {
    my ($_o, $hdlists, $o_copy_rpms_on_disk) = @_;

    my @names = uniq(map { $_->{name} } @$hdlists);
    my %selection = map { $_ => 1 } @names;

    if (@names > 1 || $o_copy_rpms_on_disk) {
	my $w = ugtk2->new("");
	$w->sync;
	ugtk2::gtkadd(
	    $w->{window},
	    gtkpack(
		Gtk2::VBox->new(0, 5),
		Gtk2::WrappedLabel->new(formatAlaTeX(N("The following installation media have been found.
If you want to skip some of them, you can unselect them now."))),
		(map {
			my $b = gtknew('CheckButton', text => $_, active_ref => \$selection{$_});
			$b->set_sensitive(0) if $_ eq $names[0];
			$b;
		    } @names),
		gtknew('HSeparator'),
		if_($o_copy_rpms_on_disk,
		    Gtk2::WrappedLabel->new(formatAlaTeX(N("You have the option to copy the contents of the CDs onto the hard drive before installation.
It will then continue from the hard drive and the packages will remain available once the system is fully installed."))),
		    gtknew('CheckButton', text => N("Copy whole CDs"), active_ref => $o_copy_rpms_on_disk),
		    gtknew('HSeparator'),
		),
		gtknew('HBox', children_tight => [
		    gtknew('Button', text => N("Next"), clicked => sub { Gtk2->main_quit }),
		]),
	    ),
	);
	$w->main;
    }
    $_->{selected} = $selection{$_->{name}} foreach @$hdlists;
    log::l("keeping media " . join ',', map { $_->{rpmsdir} } grep { $_->{selected} } @$hdlists);
}

1;
