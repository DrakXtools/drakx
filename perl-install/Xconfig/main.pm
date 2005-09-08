package Xconfig::main; # $Id$

use diagnostics;
use strict;

use Xconfig::monitor;
use Xconfig::card;
use Xconfig::resolution_and_depth;
use Xconfig::various;
use Xconfig::screen;
use Xconfig::test;
use Xconfig::xfree;
use common;


sub configure_monitor {
    my ($in) = @_;

    my ($raw_X, $before) = Xconfig::xfree->read_and_prepare_write;
    Xconfig::monitor::configure($in, $raw_X, int($raw_X->get_devices)) or return;
    if ($raw_X->prepare_write ne $before) {
	$raw_X->write;
	'need_restart';
    } else {
	'';
    }
}

sub configure_resolution {
    my ($in) = @_;

    my ($raw_X, $before) = Xconfig::xfree->read_and_prepare_write;
    my $X = { 
	card => Xconfig::card::from_raw_X($raw_X),
	monitors => [ $raw_X->get_monitors ],
    };
    $X->{resolution} = Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitors}) or return;
    if ($raw_X->prepare_write ne $before) {
	&write($raw_X, $X);
    } else {
	'';
    }
}


sub configure_everything_auto_install {
    my ($raw_X, $do_pkgs, $old_X, $options) = @_;
    my $X = {};
    $X->{monitors} = Xconfig::monitor::configure_auto_install($raw_X, $old_X) or return;
    $options->{VideoRam_probed} = $X->{monitors}[0]{VideoRam_probed};
    $X->{card} = Xconfig::card::configure_auto_install($raw_X, $do_pkgs, $old_X, $options) or return;
    Xconfig::screen::configure($raw_X) or return;
    $X->{resolution} = Xconfig::resolution_and_depth::configure_auto_install($raw_X, $X->{card}, $X->{monitors}, $old_X);

    my $action = &write($raw_X, $X);

    Xconfig::various::runlevel(exists $old_X->{xdm} && !$old_X->{xdm} ? 3 : 5);

    $action;
}

sub configure_everything {
    my ($in, $raw_X, $do_pkgs, $auto, $options) = @_;
    my $X = {};
    my $ok = 1;

    my $probed_info = Xconfig::monitor::probe($raw_X->get_Driver);
    $options->{VideoRam_probed} = $probed_info->{VideoRam_probed};
    $ok &&= $X->{card} = Xconfig::card::configure($in, $raw_X, $do_pkgs, $auto, $options);
    $ok &&= $X->{monitors} = Xconfig::monitor::configure($in, $raw_X, int($raw_X->get_devices), $probed_info, $auto);
    $ok &&= Xconfig::screen::configure($raw_X);
    $ok &&= $X->{resolution} = Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitors}, $auto);
    $ok &&= Xconfig::test::test($in, $raw_X, $X->{card}, '', 'skip_badcard') if !$auto;

    if (!$ok) {
	return if $auto;
	($ok) = configure_chooser_raw($in, $raw_X, $do_pkgs, $options, $X, 1);
    }
    $X->{various} ||= Xconfig::various::various($in, $X->{card}, $options, $auto);

    may_write($in, $raw_X, $X, $ok);
}

sub configure_chooser_raw {
    my ($in, $raw_X, $do_pkgs, $options, $X, $b_modified) = @_;

    my %texts;

    my $update_texts = sub {
	$texts{card} = $X->{card} && $X->{card}{BoardName} || N("Custom");
	$texts{monitors} = $X->{monitors} && $X->{monitors}[0]{ModelName} || N("Custom");
	$texts{resolution} = Xconfig::resolution_and_depth::to_string($X->{resolution});

	$texts{$_} =~ s/(.{20}).*/$1.../ foreach keys %texts; #- ensure not too long
    };
    $update_texts->();

    my $may_set; 
    my $prompt_for_resolution = sub {
	$may_set->('resolution', Xconfig::resolution_and_depth::configure($in, $raw_X, $X->{card}, $X->{monitors}));
    };
    $may_set = sub {
	my ($field, $val) = @_;
	if ($val) {
	    $X->{$field} = $val;
	    $X->{"modified_$field"} = 1;
	    $b_modified = 1;
	    $update_texts->();

	    if (member($field, 'card', 'monitors')) {
		my ($default_resolution) = Xconfig::resolution_and_depth::choices($raw_X, $X->{resolution}, $X->{card}, $X->{monitors});
		if (find { $default_resolution->{$_} ne $X->{resolution}{$_} } 'X', 'Y', 'Depth') {
		    $prompt_for_resolution->();
		} else {
		    if ($default_resolution->{bios} && !$X->{resolution}{bios}) {
			$may_set->('resolution', $default_resolution);
		    }
		    Xconfig::screen::configure($raw_X);
		    $raw_X->set_resolution($X->{resolution}) if $X->{resolution};
		}
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
		    { label => N("Monitor"), val => \$texts{monitors}, clicked => sub { 
			  $may_set->('monitors', Xconfig::monitor::configure($in, $raw_X, int($raw_X->get_devices)));
		      } },
		    { label => N("Resolution"), val => \$texts{resolution}, disabled => sub { !$X->{card} || !$X->{monitors} },
		      clicked => $prompt_for_resolution },
		        if_(Xconfig::card::check_bad_card($X->{card}) || $::isStandalone,
		     { val => N("Test"), disabled => sub { !$X->{card} || !$X->{monitors} },
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
	monitors => [ $raw_X->get_monitors ],
	resolution => scalar eval { $raw_X->get_resolution },
    };
    my $before = $raw_X->prepare_write;
    my ($ok) = configure_chooser_raw($in, $raw_X, $do_pkgs, $options, $X);

    if ($raw_X->prepare_write ne $before) {
	may_write($in, $raw_X, $X, $ok);
    } else {
	'';
    }
}

sub configure_everything_or_configure_chooser {
    my ($in, $options, $auto, $o_keyboard, $o_mouse) = @_;

    my $raw_X = eval { Xconfig::xfree->read };
    my $err = $@ && formatError($@);
    $err ||= check_valid($raw_X) if $raw_X && @$raw_X; #- that's ok if config is empty
    if ($err) {
	log::l("ERROR: bad X config file (error: $err)");
	$in->ask_okcancel('',
			  N("Your Xorg configuration file is broken, we will ignore it.")) or return;
	$raw_X = [];
    }

    my $rc = 'ok';
    if (is_empty_array_ref($raw_X)) {
	$raw_X = Xconfig::default::configure($in->do_pkgs, $o_keyboard, $o_mouse);
	$rc = configure_everything($in, $raw_X, $in->do_pkgs, $auto, $options);
    } elsif (!$auto) {
	$rc = configure_chooser($in, $raw_X, $in->do_pkgs, $options);
    }
    $rc && $raw_X, $rc;
}


sub may_write {
    my ($in, $raw_X, $X, $ok) = @_;

    $ok ||= $in->ask_yesorno('', N("Keep the changes?
The current configuration is:

%s", Xconfig::various::info($raw_X, $X->{card})), 1);

    $ok && &write($raw_X, $X);
}

sub write {
    my ($raw_X, $X) = @_;
    export_to_install_X($X) if $::isInstall;
    $raw_X->write;
    Xconfig::various::check_XF86Config_symlink();
    symlinkf "../../usr/X11R6/bin/Xorg", "$::prefix/etc/X11/X";
    if ($X->{resolution}{bios}) {
	Xconfig::various::setupFB($X->{resolution}{bios});
	'need_reboot';
    } else {
	'need_restart';
    }
}


sub export_to_install_X {
    my ($X) = @_;

    $::o->{X}{resolution_wanted} = $X->{resolution}{X};
    $::o->{X}{default_depth} = $X->{resolution}{Depth};
    $::o->{X}{bios_vga_mode} = $X->{resolution}{bios};
    $::o->{X}{monitors} = $X->{monitors} if $X->{monitors}[0]{manually_chosen} && $X->{monitors}[0]{vendor} ne "Plug'n Play";
    $::o->{X}{card} = $X->{card} if $X->{card}{manually_chosen};
    $::o->{X}{Xinerama} = 1 if $X->{card}{Xinerama};
}

sub check_valid {
    my ($raw_X) = @_;

    my %sections = map { 
	my @l = $raw_X->get_Sections($_) or return "missing section $_";
	$_ => \@l;
    } qw(Files InputDevice Monitor Device Screen ServerLayout);

    $sections{Files}[0]{FontPath} or return "missing FontPath";

    '';
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
