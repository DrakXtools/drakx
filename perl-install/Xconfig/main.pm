package Xconfig::main; # $Id$

use diagnostics;
use strict;

use Xconfig::monitor;
use Xconfig::card;
use Xconfig::resolution_and_depth;
use Xconfig::various;
use Xconfig::screen;
use Xconfig::test;
use common;
use any;


sub configure_monitor {
    my ($in, $raw_X) = @_;

    my $before = $raw_X->prepare_write;
    Xconfig::monitor::configure($in, $raw_X) or return;
    if ($raw_X->prepare_write ne $before) {
	$raw_X->write;
	'config_changed';
    } else {
	'';
    }
}

sub configure_resolution {
    my ($in, $raw_X) = @_;

    my $card = Xconfig::card::from_raw_X($raw_X);
    my $monitor = Xconfig::monitor::from_raw_X($raw_X);
    my $before = $raw_X->prepare_write;
    Xconfig::resolution_and_depth::configure($in, $raw_X, $card, $monitor) or return;
    if ($raw_X->prepare_write ne $before) {
	$raw_X->write;
	'config_changed';
    } else {
	'';
    }
}


sub configure_everything_auto_install {
    my ($raw_X, $do_pkgs, $old_X, $options) = @_;
    my $X = {};
    $X->{monitor} = Xconfig::monitor::configure_auto_install($raw_X, $old_X) or return;
    $options->{VideoRam_probed} = $X->{monitor}{VideoRam_probed};
    $X->{card} = Xconfig::card::configure_auto_install($raw_X, $do_pkgs, $old_X, $options) or return;
    Xconfig::screen::configure($raw_X) or return;
    $X->{resolution} = Xconfig::resolution_and_depth::configure_auto_install($raw_X, $X->{card}, $X->{monitor}, $old_X);

    &write($raw_X, $X);

    Xconfig::various::runlevel(exists $old_X->{xdm} && !$old_X->{xdm} ? 3 : 5);
    'config_changed';
}

sub configure_everything {
    my ($in, $raw_X, $do_pkgs, $auto, $options) = @_;
    my $X = {};
    my $ok = 1;
    $ok &&= $X->{monitor} = Xconfig::monitor::configure($in, $raw_X, $auto);
    $options->{VideoRam_probed} = $X->{monitor}{VideoRam_probed};
    $ok &&= $X->{card} = Xconfig::card::configure($in, $raw_X, $do_pkgs, $auto, $options);
    $ok &&= Xconfig::screen::configure($raw_X);
    $ok &&= $X->{resolution} = Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitor}, $auto);
    $ok &&= Xconfig::test::test($in, $raw_X, $X->{card}, '', 'skip_badcard') if !$auto;

    if (!$ok) {
	return if $auto;
	($ok) = configure_chooser_raw($in, $raw_X, $do_pkgs, $options, $X, 1);
    }
    $X->{various} ||= Xconfig::various::various($in, $X->{card}, $options, $auto);

    $ok = may_write($in, $raw_X, $X, $ok);
    
    $ok && 'config_changed';
}

sub configure_chooser_raw {
    my ($in, $raw_X, $do_pkgs, $options, $X, $b_modified) = @_;

    my %texts;

    my $update_texts = sub {
	$texts{card} = $X->{card} && $X->{card}{BoardName} || N("Custom");
	$texts{monitor} = $X->{monitor} && $X->{monitor}{ModelName} || N("Custom");
	$texts{resolution} = Xconfig::resolution_and_depth::to_string($X->{resolution});

	$texts{$_} =~ s/(.{20}).*/$1.../ foreach keys %texts; #- ensure not too long
    };
    $update_texts->();

    my $may_set = sub {
	my ($field, $val) = @_;
	if ($val) {
	    $X->{$field} = $val;
	    $X->{"modified_$field"} = 1;
	    $b_modified = 1;
	    $update_texts->();

	    if (member($field, 'card', 'monitor')) {
		Xconfig::screen::configure($raw_X);
		$raw_X->set_resolution($X->{resolution}) if $X->{resolution};
	    }
	}
    };

    my $ok;
    $in->ask_from_({ interactive_help_id => 'configureX_chooser',
		     if_($::isStandalone, ok => N("Quit")) }, 
		   [
		    { label => N("Graphic Card"), val => \$texts{card}, clicked => sub { 
			  $may_set->('card', Xconfig::card::configure($in, $raw_X, $do_pkgs, 0, $options));
		      } },
		    { label => N("Monitor"), val => \$texts{monitor}, clicked => sub { 
			  $may_set->('monitor', Xconfig::monitor::configure($in, $raw_X));
		      } },
		    { label => N("Resolution"), val => \$texts{resolution}, disabled => sub { !$X->{card} || !$X->{monitor} },
		      clicked => sub {
			  $may_set->('resolution', Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitor}));
		      } },
		        if_(Xconfig::card::check_bad_card($X->{card}) || $::isStandalone,
		     { val => N("Test"), disabled => sub { !$X->{card} || !$X->{monitor} },
		       clicked => sub { 
			  $ok = Xconfig::test::test($in, $raw_X, $X->{card}, 'auto', 0);
		      } },
			),
		    { val => N("Options"), clicked => sub {
			  Xconfig::various::various($in, $X->{card}, $options);
			  $X->{various} = 'done';
		      } },
		   ]);
    $ok, $b_modified;
}

sub configure_chooser {
    my ($in, $raw_X, $do_pkgs, $options) = @_;

    my $X = {
	card => scalar eval { Xconfig::card::from_raw_X($raw_X) },
	monitor => $raw_X->get_monitors && Xconfig::monitor::from_raw_X($raw_X),
	resolution => scalar eval { $raw_X->get_resolution },
    };
    my $before = $raw_X->prepare_write;
    my ($ok) = configure_chooser_raw($in, $raw_X, $do_pkgs, $options, $X);

    if ($raw_X->prepare_write ne $before) {
	may_write($in, $raw_X, $X, $ok) or return;
	'config_changed';
    } else {
	'';
    }
}

sub configure_everything_or_configure_chooser {
    my ($in, $options, $auto, $o_keyboard, $o_mouse) = @_;
    my $raw_X = Xconfig::xfree->read;

    if (is_empty_array_ref($raw_X)) {
	$raw_X = Xconfig::default::configure($o_keyboard, $o_mouse);
	Xconfig::main::configure_everything($in, $raw_X, $in->do_pkgs, $auto, $options) or return;
    } else {
	Xconfig::main::configure_chooser($in, $raw_X, $in->do_pkgs, $options) or return if !$auto;
    }
    $raw_X;
}


sub may_write {
    my ($in, $raw_X, $X, $ok) = @_;

    $ok ||= $in->ask_yesorno('', N("Keep the changes?
The current configuration is:

%s", Xconfig::various::info($raw_X, $X->{card})), 1);

    &write($raw_X, $X) if $ok;
    $ok;
}

sub write {
    my ($raw_X, $X) = @_;
    export_to_install_X($X);
    $raw_X->write;
    Xconfig::various::check_XF86Config_symlink();
    symlinkf "../../usr/X11R6/bin/XFree86", "$::prefix/etc/X11/X";
}


sub export_to_install_X {
    my ($X) = @_;

    $::isInstall or return;

    $::o->{X}{resolution_wanted} = $X->{resolution}{X};
    $::o->{X}{default_depth} = $X->{resolution}{Depth};
    $::o->{X}{bios_vga_mode} = $X->{resolution}{bios};
    $::o->{X}{monitor} = $X->{monitor} if $X->{monitor}{manually_chosen} && $X->{monitor}{vendor} ne "Plug'n Play";
    $::o->{X}{card} = $X->{monitor} if $X->{card}{manually_chosen};
    $::o->{X}{Xinerama} = 1 if $X->{card}{Xinerama};
}


#- most usefull XFree86-4.0.1 server options. Default values is the first ones.
our @options_serverflags = (
			'DontZap'                 => [ "Off", "On" ],
			'DontZoom'                => [ "Off", "On" ],
			'DisableVidModeExtension' => [ "Off", "On" ],
			'AllowNonLocalXvidtune'   => [ "Off", "On" ],
			'DisableModInDev'         => [ "Off", "On" ],
			'AllowNonLocalModInDev'   => [ "Off", "On" ],
			'AllowMouseOpenFail'      => [ "False", "True" ],
			'VTSysReq'                => [ "Off", "On" ],
			'BlankTime'               => [ "10", "5", "3", "15", "30" ],
			'StandByTime'             => [ "20", "10", "6", "30", "60" ],
			'SuspendTime'             => [ "30", "15", "9", "45", "90" ],
			'OffTime'                 => [ "40", "20", "12", "60", "120" ],
			'Pixmap'                  => [ "32", "24" ],
			'PC98'                    => [ "auto-detected", "False", "True" ],
			'NoPM'                    => [ "False", "True" ],
);

1;
