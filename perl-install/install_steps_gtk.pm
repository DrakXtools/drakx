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
use install_steps;
use install_steps_interactive;
use interactive_gtk;
use install_any;
use diskdrake;
use log;
use help;
use lang;

#-#####################################################################################
#-INTERN CONSTANT
#-#####################################################################################
my $w_help;
my $itemsNB = 1;
my (@background1, @background2);

my @themes_vga16 = qw(blue blackwhite savane);
my @themes = qw(DarkMarble marble3d blueHeart);

my @circle_head = (
    "19 17 4 1"
);

my @circle_body = (
" c None",
"+ c #FFFFFF",
"        =====      ",
"      =========    ",
"     =+++=======   ",
"    =++==========  ",
"   ==+============ ",
"   +++============ ",
"  ================o",
"  ================o",
"  ================o",
"  ===============oo",
"  ===============oo",
"   =============oo ",
"   ============ooo ",
"    o=========ooo  ",
"     oo=====oooo   ",
"      ooooooooo    ",
"        ooooo      ",
);

#-my @questionmark_head = (
#-"39 97 6 1",
#-" 	c None",
#-".	c #000000",
#-"+	c #FFFFFF",
#-"o	c #AAAAAA",
#-);
#-my @questionmark_body = (
#-("OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO") x 10,
#-"OOOOOOOOOOOOO.......OOOOOOOOOOOOOOOOOOO",
#-"OOOOOOOOOOOO..OOOOOOO.OOOOOOOOOOOOOOOOO",
#-"OOOOOOOOOO..OOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOOOOOOOO..OOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOOOOOO..OOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOOOOOO..OOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOOOOO..OOOOOOOOOOOOOOOOOOXOOOOOOOOOOO",
#-"OOOOOOO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOOOO.OOOOOOOOOOOOOOOOOOOOOXOOOOOOOOOO",
#-"OOOOO..OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOOO.OOOOOOOOOOOOOOOOOOOOOOOXOOOOOOOOO",
#-"OOOO..OOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOOO",
#-"OOOO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOOO.OOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOO",
#-"OOO..OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO",
#-"OOO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOO",
#-"OO..OOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOO",
#-"OOO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOO",
#-"OO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOO",
#-"OO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOO",
#-"O..OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOO",
#-"OO.OOOOOOOOOOOoo+++++ooOOOOOOOOOOXOOOOO",
#-"O.OOOOOOOOOOo+++o+++++++oOOOOOOOOOXOOOO",
#-"O.OOOOOOOOO+++OOOOo+++++++OOOOOOOOXOOOO",
#-"O.OOOOOOOOo++oOOOOOo++++++oOOOOOOOXOOOO",
#-"O.OOOOOOOo+++oOOOOOO+++++++OOOOOOOXOOOO",
#-"..OOOOOOOo++++OOOOOOo++++++oOOOOOOXOOOO",
#-"O.OOOOOOO+++++oOOOOOo+++++++OOOOOOXOOOO",
#-".OOOOOOOO++++++OOOOOo+++++++OOOOOOOXOOO",
#-".OOOOOOOO++++++OOOOOo+++++++OOOOOOXOOOO",
#-".OOOOOOOOo++++oOOOOOo++++++oOOOOOOOXOOO",
#-".OOOOOOOOOo++oOOOOOOo++++++oOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOOO+++++++OOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOOO++++++OOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOOo+++++oOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOO+++++OOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOo+++oOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOO+++oOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOo++OOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOO++OOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOO+oOOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOO+OOOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOO+OOOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOoOOOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOO",
#-"O.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOO",
#-"OOOOOOOOOOOOOOOOoooOOOOOOOOOOOOOOOOXOOO",
#-".OOOOOOOOOOOOOO+++++OOOOOOOOOOOOOOXOOOO",
#-"O.OOOOOOOOOOOO++++++oOOOOOOOOOOOOOXXOOO",
#-"O.OOOOOOOOOOOo+++++++OOOOOOOOOOOOOXOOOO",
#-"O.OOOOOOOOOOOo+++++++OOOOOOOOOOOOOXOOOO",
#-"O.OOOOOOOOOOOo+++++++OOOOOOOOOOOOOXOOOO",
#-"OOOOOOOOOOOOOO++++++oOOOOOOOOOOOOOXOOOO",
#-"O.OOOOOOOOOOOOO+++++OOOOOOOOOOOOOXXOOOO",
#-"OO.OOOOOOOOOOOOOoooOOOOOOOOOOOOOOOXOOOO",
#-"OO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOO",
#-"OO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOXXOOOOO",
#-"OOO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOO",
#-"OOO.OOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOO",
#-"OOOO.OOOOOOOOOOOOOOOOOOOOOOOOOOXXOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOO",
#-"OOOOO.OOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXXOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOOO",
#-"OOOOOO.OOOOOOOOOOOOOOOOOOOOOOXXOOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOOXXOOOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOXXOOOOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOXXXOOOOOOOOOOO",
#-"OOOOOOOOOOOOOOOOOOOOOOOOOXOOOOOOOOOOOOO",
#-"OOOOOOOOOOOOXOOOOOOOOOOXXXOOOOOOOOOOOOO",
#-"OOOOOOOOOOOOOOXOOOOOOXXXOOOOOOOOOOOOOOO",
#-"OOOOOOOOOOOOOOOXXXXXXXOOOOOOOOOOOOOOOOO",
#-("OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO") x 10);

my    @red_circle = (@circle_head, "= c #FF0000", "o c #AA5500", @circle_body);
my @orange_circle = (@circle_head, "= c #FFAA00", "o c #AA5500", @circle_body);
my  @green_circle = (@circle_head, "= c #00FF00", "o c #00AA00", @circle_body);

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    my $old = $SIG{__DIE__};
    $SIG{__DIE__} = sub { $_[0] !~ /my_gtk\.pm/ and goto $old };

    $ENV{DISPLAY} = $o->{display} || ":0";
    unless ($::testing) {
	$my_gtk::force_focus = $ENV{DISPLAY} eq ":0";

	my $f = "/tmp/Xconf";
	createXconf($f, @{$o->{mouse}}{"XMOUSETYPE", "device"}, $o->{wacom});

	if ($ENV{DISPLAY} eq ":0") {
	    my $launchX = sub {
		my $ok = 1;
		local $SIG{CHLD} = sub { $ok = 0 if waitpid(-1, c::WNOHANG()) > 0 };
		unless (fork) {
		    exec $_[0], (arch() =~ /^sparc/ ? () : ("-kb")), "-dpms","-s" ,"240",
		      ($_[0] =~ /Xsun/ ? ("-fp", "/usr/X11R6/lib/X11/fonts:unscaled") :
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
		add2hash($card, Xconfigurator::cardName2card($card->{type})) if $card && $card->{type};
		@servers = $card->{server} || "TGA";
		#-@servers = qw(SVGA 3DLabs TGA) 
	    } elsif (arch() =~ /^sparc/) {
		local $_ = cat_("/proc/fb");
		if (/Mach64/) { @servers = qw(Mach64) }
		else { @servers = qw(Xsun24) }
	    }
	    @servers = qw(PPCDummy) if arch() eq "ppc";

	    foreach (@servers) {
		log::l("Trying with server $_");
		my $dir = "/usr/X11R6/bin";
		my $prog = /Xsun/ ? $_ : "XF86_$_";
		unless (-x "$dir/XF86_$_") {
		    unlink $_ foreach glob_("$dir/X*");
		    local *F; open F, ">$dir/$prog" or die "failed to write server: $!";
		    local $/ = \ (16 * 1024);
		    my $f = install_any::getFile("$dir/$prog") or next;
		    syswrite F, $_ foreach <$f>;
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

    print _("Entering step `%s'\n", $o->{steps}{$step}{text});
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
    my ($o) = @_;
    $o->SUPER::selectLanguage;
    Gtk->set_locale;
    install_theme($o);
}

#------------------------------------------------------------------------------
sub selectInstallClass1 {
    my ($o, $verif, $l, $def, $l2, $def2) = @_;

    my $w = my_gtk->new('');
    my ($radio, $focused);
    gtkadd($w->{window},
	   gtkpack($o->create_box_with_title(_("Which installation class do you want?")),
		   (my @radios = map { $radio = new Gtk::RadioButton($_, $radio ? $radio : ()); 
			 $radio->set_active($_ eq $def); $radio } @$l),
		   gtkadd(create_hbox(),
			  map { my $v = $_; 
				my $b = new Gtk::Button($_);
				$focused = $b if $_ eq $def2;
				gtksignal_connect($b, "clicked" => sub { $w->{retval} = $v; Gtk->main_quit });
			    } @$l2)
		  ));
    $focused->grab_focus if $focused;
    $w->main;

    mapn { $verif->($_[1]) if $_[0]->active } \@radios, $l;
    $w->{retval};
}

#------------------------------------------------------------------------------
sub selectMouse {
    my ($o, $force) = @_;
    my $old_dev = $o->{mouse}{device};
    $o->SUPER::selectMouse($force);

    my $dev = $o->{mouse}{device};
    if ($old_dev ne $dev && $dev =~ /ttyS/) {
	log::l("telling X server to use another mouse");
	eval { commands::modprobe("serial") };
	symlinkf($dev, "/dev/mouse");
	c::setMouseMicrosoft($ENV{DISPLAY});
    }
}

#------------------------------------------------------------------------------
sub doPartitionDisks($$) {
    my ($o, $hds, $raid) = @_;

    if ($::beginner && fsedit::is_one_big_fat($hds)) {
	#- wizard
	my $min_linux = 600 << 11;
	my $max_linux = 1500 << 11;
	my $min_freewin = 300 << 11;

	my ($part) = fsedit::get_fstab(@{$o->{hds}});
	my $w = $o->wait_message(_("Resizing"), _("Computing fat filesystem bounds"));
	my $resize_fat = eval { resize_fat::main->new($part->{device}, devices::make($part->{device})) };
	$@ and goto diskdrake;
	my $min_win = $resize_fat->min_size;
	if (!$@ && $part->{size} > $min_linux + $min_freewin + $min_win && $o->ask_okcancel('',
_("WARNING!

DrakX now needs to resize your Windows partition. Be careful: this operation is
dangerous. If you have not already done so, you should first exit the
installation, run scandisk under Windows (and optionally run defrag), then
restart the installation. You should also backup your data.
When sure, press Ok."))) {
	    my $hd = $hds->[0];
	    my $oldsize = $part->{size};
	    $hd->{isDirty} = $hd->{needKernelReread} = 1;
	    $part->{size} -= min($max_linux, $part->{size} - $min_win);
	    $hd->adjustEnd($part);
	    partition_table::adjust_local_extended($hd, $part);
	    partition_table::adjust_main_extended($hd);

	    local *log::l = sub { $w->set(join(' ', @_)) };
	    eval { $resize_fat->resize($part->{size}) };
	    if ($@) {
		$part->{size} = $oldsize;
		$o->ask_warn('', _("Automatic resizing failed"));
	    } else {
		$part->{isFormatted} = 1;
		eval { fsedit::auto_allocate($hds, $o->{partitions}) };
		if (!$@) {
		    partition_table::write($hd) unless $::testing;
		    return;
		}
	    }
	}
    }

  diskdrake:
    while (1) {
	diskdrake::main($hds, $raid, interactive_gtk->new, $o->{partitions});
	if (!grep { isSwap($_) } fsedit::get_fstab(@{$o->{hds}})) {
	    if ($::beginner) {
		$o->ask_warn('', _("You must have a swap partition"));
	    } elsif (!$::expert) {
		$o->ask_okcancel('', _("You don't have a swap partition\n\nContinue anyway?")) and last;
	    } else { last }
	} else { last }
    }
}

#------------------------------------------------------------------------------
sub chooseSizeToInstall {
    my ($o, $packages, $min_size, $max_size) = @_;
    my ($min, $max) = map { pkgs::correctSize($_ / sqr(1024)) } $min_size, $max_size;
    log::l("choosing size to install between $min and $max (really between $min_size and $max_size)");
    my $w = my_gtk->new('');
    my $adj = create_adjustment($max, $min, $max);
    my $spin = gtkset_usize(new Gtk::SpinButton($adj, 0, 0), 100, 0);

    gtkadd($w->{window},
	  gtkpack(new Gtk::VBox(0,20),
_("Now that you've selected desired groups, please choose 
how many packages you want, ranging from minimal to full 
installation of each selected groups.") .
		  ($::expert ? "\n" . _("You will be able to choose more precisely in next step") : ''),
		 create_packtable({ col_spacings => 10 },
				  [ _("Choose the size you want to install"), $spin, _("MB"), ],
				  [ undef, new Gtk::HScrollbar($adj) ],
			       ),
		 create_okcancel($w)
		)
	 );
    $spin->signal_connect(activate => sub { $w->{retval} = 1; Gtk->main_quit });
    $spin->grab_focus();
    $w->main and pkgs::invCorrectSize($spin->get_value_as_int) * sqr(1024);
}
sub choosePackagesTree {
    my ($o, $packages, $compss) = @_;

    my ($curr, $info_widget, $w_size, $go, $idle, $flat, $auto_deps);
    my (%wtree, %ptree);

    my $w = my_gtk->new('');
    my $details = new Gtk::VBox(0,0);
    my $tree = Gtk::CTree->new(3, 0);
    $tree->set_selection_mode('browse');
    $tree->set_column_auto_resize($_, 1) foreach 0..2;

    gtkadd($w->{window}, 
	   gtkpack_(new Gtk::VBox(0,5),
		    0, _("Choose the packages you want to install"),
		    1, gtkpack(new Gtk::HBox(0,0),
			       createScrolledWindow($tree),
			       gtkadd(gtkset_usize(new Gtk::Frame(_("Info")), 150, 0),
				      createScrolledWindow($info_widget = new Gtk::Text),
				     )),
		    0, my $l = new Gtk::HBox(0,0),
		    0, gtkpack(new Gtk::HBox(0,10),
			       $go = gtksignal_connect(new Gtk::Button(_("Install")), "clicked" => sub { $w->{retval} = 1; Gtk->main_quit }),
			      )
    ));
    gtkpack__($l, $w_size = new Gtk::Label(''));
    $l->pack_end(my $toolbar = new Gtk::Toolbar('horizontal', 'icons'), 0, 1, 0);
    $l->pack_end(gtksignal_connect(new Gtk::CheckButton(_("Automatic dependencies")), clicked => sub { invbool \$auto_deps }), 0, 1, 0);

    $w->{window}->set_usize(map { $_ - 2 * $my_gtk::border - 4 } $::windowwidth, $::windowheight);
    $go->grab_focus;
    $w->{rwindow}->show_all;

    my $pix_base     = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-base.xpm") ];
    my $pix_selected = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-selected.xpm") ];
    my $pix_unselect = [ gtkcreate_xpm($w->{window}, "$ENV{SHARE_PATH}/rpm-unselected.xpm") ];

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
	my $pix = pkgs::packageFlagBase($p) ? $pix_base : pkgs::packageFlagSelected($p) ? $pix_selected : $pix_unselect;
	$tree->node_set_pixmap($node, 1, $pix->[0], $pix->[1]);
	push @{$ptree{$leaf}}, $node;
    };
    my $add_nodes = sub {
	%ptree = %wtree = ();

	$tree->freeze;
	while (1) { $tree->remove_node($tree->node_nth(0) || last) }

	my ($root, $leaf);
	if ($flat = $_[0]) {
	    $add_node->($_, undef) foreach sort keys %{$packages->[0]};
	} else {
	    foreach (sort @$compss) {
		($root, $leaf) = m|(.*)/(.+)|o or ($root, $leaf) = ('', $_);
		$add_node->($leaf, $root);
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

	my $ind = $o->{compssListLevels}{$o->{install_class}};
	my $imp = translate($pkgs::compssListDesc{pkgs::packageFlagBase($p) ? 100 : round_down($p->{values}[$ind], 10)});

	gtktext_insert($info_widget, $@ ? _("Bad package") :
		       _("Version: %s\n", pkgs::packageVersion($p) . '-' . pkgs::packageRelease($p)) .
		       _("Size: %d KB\n", pkgs::packageSize($p) / 1024) .
		       ($imp && _("Importance: %s\n", $imp)) . "\n" .
		       formatLines(c::headerGetEntry($p->{header}, 'description')));
	c::headerFree(delete $p->{header});
	0;
    };

    my $update_size = sub {
	my $size = 0;
	foreach (values %{$packages->[0]}) {
	    $size += pkgs::packageSize($_) - ($_->{installedCumulSize} || 0) if pkgs::packageFlagSelected($_); #- on upgrade, installed packages will be removed.
	}
	$w_size->set(_("Total size: %d / %d MB", 
		       pkgs::correctSize($size / sqr(1024)),
		       install_any::getAvailableSpace($o) / sqr(1024)));

    };
    my $toggle = sub {
	if (ref $curr) {
	    $tree->toggle_expansion($curr);
	} else {
	    my $p = $packages->[0]{$curr} or return;
	    pkgs::togglePackageSelection($packages, $p, my $l = {});
	    if (my @l = grep { $l->{$_} } keys %$l) {
		@l > 1 && !$auto_deps and $o->ask_okcancel('', [ _("The following packages are going to be install/removed"), join(", ", sort @l) ], 1) || return;
		pkgs::togglePackageSelection($packages, $p);
		foreach (@l) {
		    my $p = $packages->[0]{$_};
		    my $pix = pkgs::packageFlagSelected($p) ? $pix_selected : $pix_unselect;
		    $tree->node_set_pixmap($_, 1, $pix->[0], $pix->[1]) foreach @{$ptree{$_}};
		}
		&$update_size;
	    } else {
		$o->ask_warn('', _("This is a mandatory package, it can't be unselected"));
	    }
	}
    };
    $tree->signal_connect(button_press_event => sub { &$toggle if $_[1]{type} =~ /^2/ });
    $tree->signal_connect(key_press_event => sub {
        my ($w, $e) = @_;
	my $c = chr $e->{keyval};
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
    $w->{window}->set_usize($::windowwidth * 0.8, 280);
    my $text = new Gtk::Label;
    my ($msg, $msg_time_remaining, $msg_time_total) = map { new Gtk::Label($_) } '', (_("Estimating")) x 2;
    my ($progress, $progress_total) = map { new Gtk::ProgressBar } (1..2);
    gtkadd($w->{window}, gtkadd(new Gtk::EventBox,
				gtkpack(new Gtk::VBox(0,10),
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
			      )));
    $msg->set(_("Preparing installation"));
    $w->sync;

    my $oldInstallCallback = \&pkgs::installCallback;
    local *pkgs::installCallback = sub {
	my $m = shift;
	if ($m =~ /^Starting installation/) {
	    $nb = $_[0];
	    $total_size = $_[1]; $current_total_size = 0;
	    $start_time = time();
	    $msg->set(_("%d packages", $nb) . _(", %U MB", pkgs::correctSize($total_size / sqr(1024))));
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
	my %medium_msg = ();
	$medium_msg{$medium} or $medium_msg{$medium} = _("Installation CD Nr %s", ($medium || 1));
	my %method_msg = (
			  cdrom =>
_("Change your Cd-Rom!

Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.
If you don't have it press Cancel to avoid installation from this Cd-Rom.", $medium_msg{$medium}),
			 );
	$method_msg{$method} or $method_msg{$method} =
_("Update installation image!

Ask your system administrator or reboot to update your installation image to include
the Cd-Rom image labelled \"%s\". Press Ok if image has been updated or press Cancel
to avoid installation from this Cd-Rom image.", $medium_msg{$medium});

	$o->ask_okcancel('', $method_msg{$method});
    };
    catch_cdie { $o->install_steps::installPackages($packages); }
      sub {
	  if ($@ =~ /^error ordering package list: (.*)/) {
	      $o->ask_yesorno('', [
_("There was an error ordering packages:"), $1, _("Go on anyway?") ], 1) and return 1;
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
		@background1 = map { $_ * 256 * 256 } split ',', $1 if /NORMAL.*\{(.*)\}/;
		@background2 = map { $_ * 256 * 256 } split ',', $1 if /PRELIGHT.*\{(.*)\}/;
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
style "steps"
{
   fontset = "$font2"
}
widget "*" style "default-font"
widget "*Steps*" style "steps"

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
    gtkadd($w->{window},
	   gtkpack_(new Gtk::HBox(0,-2),
#-		    0, $b,
#-		    1, createScrolledWindow($w_help = new Gtk::XmHTML)));
		    1, createScrolledWindow($w_help = new Gtk::Text)));
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

    $o->{steps_window}->destroy if $o->{steps_window};
    my %reachableSteps if 0;
    %reachableSteps = ();

    my $w = bless {}, 'my_gtk';
    $w->{rwindow} = $w->{window} = new Gtk::Window;
    $w->{rwindow}->set_uposition(0, 0);
    $w->{rwindow}->set_usize($::stepswidth, $::stepsheight);
    $w->{rwindow}->set_name("Steps");
    $w->{rwindow}->set_events('button_press_mask');
    $w->{rwindow}->signal_connect(button_press_event => sub {
	$::setstep or return;
        my $Y = $_[1]{'y'};
	map_each {
	    my (undef, $y, undef, $height) = @{$::b->allocation};
	    $y <= $Y && $Y < $y + $height and die "setstep $::a\n";
	} %reachableSteps;
    });
    $w->show;

    gtkadd($w->{window},
	   gtkpack_(new Gtk::VBox(0,0),
		    (map {; 1, $_ } map {
			my $step = $o->{steps}{$_};
			my $circle =
			  $step->{done}    && \@green_circle  ||
			  $step->{entered} && \@orange_circle ||
			  \@red_circle;
			my @pixmap = Gtk::Gdk::Pixmap->create_from_xpm_d($w->{window}->window, undef, @$circle);

			my $w = new Gtk::Label(translate($step->{text}));

			$w->set_name("Steps" . ($step->{reachable} && "Reachable"));
			my $b = new Gtk::HBox(0,5);
			gtkpack_($b, 0, new Gtk::Pixmap(@pixmap), 0, $w);

			$reachableSteps{$_} = $b if $step->{reachable};
			$b;
		    } grep {
			local $_ = $o->{steps}{$_}{hidden};
			/^$/ or $o->{installClass} and !/!expert/ || $::expert
			                           and !/beginner/ || !$::beginner 
			                           and !/!corporate/ || $::corporate;
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
    ($::rootheight,  $::rootwidth)    = (480, 640);
    ($::rootheight,  $::rootwidth)    = my_gtk::gtkroot()->get_size;
    ($::rootheight,  $::rootwidth)    = (min(600, $::rootheight), min(800, $::rootwidth));
    ($::stepswidth,  $::stepsheight)  = (140, $::rootheight);
    ($::logowidth,   $::logoheight)   = ($::rootwidth - $::stepswidth, 40);                                 
    ($::helpwidth,   $::helpheight)   = ($::rootwidth - $::stepswidth, 100);                                
    ($::windowwidth, $::windowheight) = ($::rootwidth - $::stepswidth, $::rootheight - $::helpheight - $::logoheight);
}

#------------------------------------------------------------------------------
sub createXconf($$$) {
    my ($file, $mouse_type, $mouse_dev, $wacom_dev) = @_;

    devices::make("/dev/kdb") if arch() =~ /^sparc/; #- used by Xsun style server.
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
   Emulate3Buttons
   Emulate3Timeout    50
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
