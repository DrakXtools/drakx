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
    my ($in, $raw_X, $card, $auto) = @_;

    Xconfig::card::check_bad_card($card) or return 1;
    $in->ask_yesorno(_("Test of the configuration"), _("Do you want to test the configuration?"), 1) or return 1 if !$auto;


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
    unless ($pid = fork) {
	system("xauth add :9 . `mcookie`");
	open STDERR, ">$f_err";
	chroot $::prefix if $::prefix;
	exec $card->{prog}, 
	  if_($card->{prog} !~ /Xsun/, "-xf86config", $f),
	  ":9" or c::_exit(0);
    }

    do { sleep 1 } until xtest(":9") || waitpid($pid, c::WNOHANG());

    my $b = before_leaving { unlink $f_err };

    if (!xtest(":9")) {
	local $_;
	local *F; open F, $f_err;
      i: while (<F>) {
	    if (Xconfig::card::using_xf4($card)) {
		if (/^\(EE\)/ && !/Disabling/ || /^Fatal\b/) {
		    my @msg = !/error/ && $_ ;
		    while (<F>) {
			/reporting a problem/ and last;
			push @msg, $_;
			$in->ask_warn('', [ _("An error occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
			return 0;
		    }
		}
	    } else {
		if (/\b(error|not supported)\b/i) {
		    my @msg = !/error/ && $_ ;
		    while (<F>) {
			/not fatal/ and last i;
			/^$/ and last;
			push @msg, $_;
		    }
		    $in->ask_warn('', [ _("An error occurred:"), " ", @msg, _("\ntry to change some parameters") ]);
		    return 0;
		}
	    }
	}
    }

    $::noShadow = 1;
    local *F;
    open F, "|perl 2>/dev/null";
    print F "use lib qw(", join(' ', @INC), ");\n";
    print F q{
        require lang;
        require my_gtk; 
        my_gtk->import(qw(:wrappers)); #- help perl_checker
	use interactive::gtk;
        use run_program;

        $::prefix = "} . $::prefix . q{";
        $::isStandalone = 1;

        lang::bindtextdomain();

	$ENV{DISPLAY} = ":9";

        gtkset_background(200 * 257, 210 * 257, 210 * 257);
        my ($h, $w) = Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW)->get_size;
        $my_gtk::force_position = [ $w / 3, $h / 2.4 ];
	$my_gtk::force_focus = 1;
        my $text = Gtk::Label->new;
        my $time = 8;
        Gtk->timeout_add(1000, sub {
	    $text->set(_("Leaving in %d seconds", $time));
	    $time-- or Gtk->main_quit;
            1;
	});

        my $background = "/usr/share/mdk/xfdrake/xfdrake-test-card.jpg";
        my $qiv = "/usr/bin/qiv";
        run_program::rooted($::prefix, $qiv, "-y", $background)
            if -r "$::prefix/$background" && -x "$::prefix/$qiv";

        my $in = interactive::gtk->new;
	$in->exit($in->ask_yesorno('', [ _("Is this the correct setting?"), $text ], 0) ? 0 : 222);
    };
    my $rc = close F;
    my $err = $?;

    unlink "$::prefix/$f", "$::prefix/$f-4";
    unlink "/tmp/.X11-unix/X9" if $::prefix;
    kill 2, $pid;
    $::noShadow = 0;

    $rc || $err == 222 << 8 or $in->ask_warn('', _("An error occurred, try to change some parameters"));
    $rc;
}
