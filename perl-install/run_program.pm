package run_program; # $Id$

use diagnostics;
use strict;

use MDK::Common;
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
sub rooted_get_stdout {
    my ($root, $name, @args) = @_;
    my @r;
    rooted($root, $name, '>', \@r, @args) or return;
    @r;
}

sub run { rooted('', @_) }

sub rooted {
    my ($root, $name, @args) = @_;
    my $str = ref $name ? $name->[0] : $name;
    log::l("running: $str @args" . ($root ? " with root $root" : ""));

    return 1 if $root && $<;

    $root ? $root .= '/' : ($root = '');
    install_any::check_prog (ref $name ? $name->[0] : $name) if !$root && $::isInstall;


    my ($stdout_raw, $stdout_mode, $stderr_raw, $stderr_mode);
    ($stdout_mode, $stdout_raw, @args) = @args if $args[0] =~ /^>>?$/;
    ($stderr_mode, $stderr_raw, @args) = @args if $args[0] =~ /^2>>?$/;
    
    $ENV{HOME} || $::isInstall or die q($HOME is unset, so I don't know where to put my temporary files);
    my $stdout = $stdout_raw && (ref($stdout_raw) ? "$ENV{HOME}/tmp/.drakx-stdout.$$" : $stdout_raw);
    my $stderr = $stderr_raw && (ref($stderr_raw) ? "$ENV{HOME}/tmp/.drakx-stderr.$$" : $stderr_raw);

    if (my $pid = fork) {
	waitpid $pid, 0;
	$? == 0 or return;
	if ($stdout_raw && ref($stdout_raw)) {
	    if (ref($stdout_raw) eq 'ARRAY') { 
		@$stdout_raw = cat_($stdout);
	    } else { 
		$$stdout_raw = cat_($stdout);
	    }
	    unlink $stdout;
	}
	if ($stderr_raw && ref($stderr_raw)) {
	    if (ref($stderr_raw) eq 'ARRAY') { 
		@$stderr_raw = cat_($stderr);
	    } else { 
		$$stderr_raw = cat_($stderr);
	    }
	    unlink $stderr;
	}
	1;
    } else {
	if ($stderr && $stderr eq 'STDERR') {
	} elsif ($stderr) {
	    $stderr_mode =~ s/2//;
	    open STDERR, "$stderr_mode $root$stderr" or die "run_program can't output in $root$stderr (mode `$stderr_mode')";
	} elsif ($::isInstall) {
	    open STDERR, ">> /tmp/ddebug.log" or open STDOUT, ">> /dev/tty7" or die "run_program can't log, give me access to /tmp/ddebug.log";
	}
	if ($stdout && $stdout eq 'STDOUT') {
	} elsif ($stdout) {
	    open STDOUT, "$stdout_mode $root$stdout" or die "run_program can't output in $root$stdout (mode `$stdout_mode')";
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
