package Xconfig::test; # $Id$

use diagnostics;
use strict;

use Xconfig::card;
use run_program;
use common;
use log;


my $tmpconfig = "/tmp/Xconfig";


sub xtest {
    my ($display) = @_;
    $::isStandalone ? 
      system("DISPLAY=$display /usr/X11R6/bin/xtest") == 0 : 
      c::Xtest($display);    
}

sub test {
    my ($in, $raw_X, $card, $auto, $skip_badcard) = @_;

    my $bad_card = !Xconfig::card::check_bad_card($card);
    return 1 if $skip_badcard && $bad_card;

    if ($bad_card || !$auto) {
	$in->ask_yesorno(N("Test of the configuration"), 
			 N("Do you want to test the configuration?") . ($bad_card ? "\n" . N("Warning: testing this graphic card may freeze your computer") : ''),
			 !$bad_card) or return 1;
    }

    unlink "$::prefix/tmp/.X9-lock";

    #- create a link from the non-prefixed /tmp/.X11-unix/X9 to the prefixed one
    #- that way, you can talk to :9 without doing a chroot
    #- but take care of non X11 install :-)
    if (-d "/tmp/.X11-unix") {
	symlinkf "$::prefix/tmp/.X11-unix/X9", "/tmp/.X11-unix/X9" if $::prefix;
    } else {
	symlinkf "$::prefix/tmp/.X11-unix", "/tmp/.X11-unix" if $::prefix;
    }

    #- ensure xfs is running
    fuzzy_pidofs(qr/\bxfs\b/) or do { run_program::rooted($::prefix, "/etc/rc.d/init.d/xfs", $_) foreach 'stop', 'start' };
    fuzzy_pidofs(qr/\bxfs\b/) or die "xfs is not running";

    my $f = $::testing ? $tmpconfig : "/etc/X11/XF86Config.test";
    $raw_X->{Xconfig::card::using_xf4($card) ? 'xfree4' : 'xfree3'}->write("$::prefix/$f");

    $ENV{HOME} || $::isInstall or die q($HOME is unset, so I don't know where to put my temporary files);
    my $f_err = "$::prefix$ENV{HOME}/tmp/.drakx.Xoutput";
    my $pid;
    unless ($pid = fork()) {
	system("xauth add :9 . `mcookie`");
	open STDERR, ">$f_err";
	chroot $::prefix if $::prefix;
	exec $card->{prog}, 
	  if_($card->{prog} !~ /Xsun/, "-xf86config", $f),
	  ":9" or c::_exit(0);
    }

    do { sleep 1 } until xtest(":9") || waitpid($pid, c::WNOHANG());

    my $_b = before_leaving { unlink $f_err };

    my $warn_error = sub {
	my ($error_msg) = @_;
	$in->ask_warn('', [ N("An error occurred:\n%s\nTry to change some parameters", $error_msg) ]);
    };

    if (!xtest(":9")) {
	open(my $F, $f_err);

	local $_;
      i: while (<$F>) {
	    if (Xconfig::card::using_xf4($card)) {
		if (/^\(EE\)/ && !/Disabling/ || /^Fatal\b/) {
		    my @msg = !/error/ && $_;
		    local $_;
		    while (<$F>) {
			/reporting a problem/ and last;
			$warn_error->(join(@msg, $_));
			return 0;
		    }
		}
	    } else {
		if (/\b(error|not supported)\b/i) {
		    my @msg = !/error/ && $_;
		    local $_;
		    while (<$F>) {
			/not fatal/ and last i;
			/^$/ and last;
			push @msg, $_;
		    }
		    $warn_error->(join(@msg));
		    return 0;
		}
	    }
	}
    }

    $::noShadow = 1;
    open(my $F, "|perl 2>/dev/null");
    print $F "use lib qw(", join(' ', @INC), ");\n";
    print $F q(
        BEGIN { $::no_ugtk_init = 1 }
        require lang;
        
        ugtk2->import(qw(:wrappers)); #- help perl_checker
	use interactive::gtk;
        use run_program;
        use common;

        $::prefix = ") . $::prefix . q(";
        $::isStandalone = 1;

        lang::bindtextdomain();

	$ENV{DISPLAY} = ":9";

        gtkset_background(200 * 257, 210 * 257, 210 * 257);
        my ($h, $w) = gtkroot()->get_size;
        $ugtk2::force_position = [ $w / 3, $h / 2.4 ];
	$ugtk2::force_focus = 1;
        my $text = Gtk2::Label->new;
        my $time = 12;
        Gtk->timeout_add(1000, sub {
	    $text->set(N("Leaving in %d seconds", $time));
	    $time-- or Gtk->main_quit;
            1;
	});

        my $background = "/usr/share/mdk/xfdrake/xfdrake-test-card.jpg";
        my $qiv = "/usr/bin/qiv";
        run_program::rooted($::prefix, $qiv, "-y", $background)
            if -r "$::prefix/$background" && -x "$::prefix/$qiv";

        my $in = interactive::gtk->new;
	$in->exit($in->ask_yesorno('', [ N("Is this the correct setting?"), $text ], 0) ? 0 : 222);
    );
    my $rc = close $F;
    my $err = $?;

    $rc || $err == 222 << 8 or $warn_error->('');

    unlink "$::prefix/$f", "$::prefix/$f-4";
    unlink "/tmp/.X11-unix/X9" if $::prefix;
    kill 2, $pid;
    $::noShadow = 0;

    $rc;
}
