package run_program;

use diagnostics;
use strict;

use log;

1;

sub run($@) { rooted('', @_) }

sub rooted($$@) {
    my ($root, $name, @args) = @_;

    log::l("running: $name @args" . ($root ? " with root $root" : ""));
    $root ? $root .= '/' : ($root = '');

    fork and wait, return $? == 0;
    {
	open STDIN, "/dev/null" or die "can't open /dev/null as stdin";

	open STDERR, ">> /dev/tty7" or open STDERR, ">> /tmp/exec.log" or die "runProgramRoot can't log :(";
	open STDOUT, ">> /dev/tty7" or open STDOUT, ">> /tmp/exec.log" or die "runProgramRoot can't log :(";

	$root and chroot $root;
	chdir "/";

	unless (exec $name, @args) {
	    log::l("exec of $name failed: $!");
	    exec('false') or exit(1);
	}
    }
}
