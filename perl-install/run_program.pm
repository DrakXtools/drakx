package run_program;

use diagnostics;
use strict;

use log;

1;

sub run($@) { rooted('', @_) }

sub rooted {
    my ($root, $name, @args) = @_;
    my $str = ref $name ? $name->[0] : $name;
    log::l("running: $str @args" . ($root ? " with root $root" : ""));
    $root ? $root .= '/' : ($root = '');

    fork and wait, return $? == 0;
    {
	open STDIN, "/dev/null" or die "can't open /dev/null as stdin";

	open STDERR, ">> /dev/tty7" or open STDERR, ">> /tmp/exec.log" or die "runProgramRoot can't log :(";
	open STDOUT, ">> /dev/tty7" or open STDOUT, ">> /tmp/exec.log" or die "runProgramRoot can't log :(";

	$root and chroot $root;
	chdir "/";

	if (ref $name) {
	    unless (exec { $name->[0] } $name->[1], @args) {
		log::l("exec of $name->[0] failed: $!");
		exec('false') or exit(1);
	    }
	} else {
	    unless (exec $name, @args) {
		log::l("exec of $name failed: $!");
		exec('false') or exit(1);
	    }

	}
    }
	
}
