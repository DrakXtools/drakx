package run_program; # $Id$

use diagnostics;
use strict;

use log;

1;

sub run_or_die {
    my ($name, @args) = @_;
    run($name, @args) or die "$name failed\n";
}
sub rooted_or_die {
    my ($root, $name, @args) = @_;
    rooted($root, $name, @args) or die "$name failed\n";
}
sub run { rooted('', @_) }

sub rooted {
    my ($root, $name, @args) = @_;
    my $str = ref $name ? $name->[0] : $name;
    log::l("running: $str @args" . ($root ? " with root $root" : ""));

    return 1 if $root && $<;

    $root ? $root .= '/' : ($root = '');
    install_any::check_prog (ref $name ? $name->[0] : $name) if !$root && $::isInstall;

    if (my $pid = fork) {
	waitpid $pid, 0;
	return $? == 0;
    }
    {
	my ($stdout, $stdoutm, $stderr, $stderrm);
	($stdoutm, $stdout, @args) = @args if $args[0] =~ /^>>?$/;
	($stderrm, $stderr, @args) = @args if $args[0] =~ /^2>>?$/;

	if ($stderr) {
	    $stderrm =~ s/2//;
	    open STDERR, "$stderrm $root$stderr" or die "run_program can't output in $root$stderr (mode `$stderrm')";
	} elsif ($::isInstall) {
	    open STDERR, ">> /tmp/ddebug.log" or open STDOUT, ">> /dev/tty7" or die "run_program can't log, give me access to /tmp/ddebug.log";
	}
	if ($stdout) {
	    open STDOUT, "$stdoutm $root$stdout" or die "run_program can't output in $root$stdout (mode `$stdoutm')";
	} elsif ($::isInstall) {
	    open STDOUT, ">> /tmp/ddebug.log" or open STDOUT, ">> /dev/tty7" or die "run_program can't log, give me access to /tmp/ddebug.log";
	}

	$root and chroot $root;
	chdir "/";

	if (ref $name) {
	    unless (exec { $name->[0] } $name->[1], @args) {
		log::l("exec of $name->[0] failed: $!");
		c::_exit(128);
	    }
	} else {
	    unless (exec $name, @args) {
		log::l("exec of $name failed: $!");
		c::_exit(128);
	    }

	}
    }

}
