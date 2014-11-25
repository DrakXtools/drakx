package drakbug;

use c;
use strict;
use common qw(backtrace if_);


sub bug_handler {
    my ($error, $is_signal) = @_;

    # exceptions in eval are OK:
    return if $error && $^S ne '0' && !$is_signal;

    # exceptions with "\n" are normal ways to quit:
    if (!$is_signal && eval { $error eq MDK::Common::String::formatError($error) }) {
        warn $error;
        exit(255);
    }

    # we want the full backtrace:
    if ($is_signal) {
        my $ctrace = c::C_backtrace();
        $ctrace =~ s/0:.*(\d+:[^:]*Perl_sighandler)/$1/sig;
        $error .= "\nGlibc's trace:\n$ctrace\n";
    }
    $error .= "Perl's trace:\n" . common::backtrace() if $error;

    my $progname = $0;

    # do not loop if drakbug crashes and do not complain about wizcancel:
    if ($progname =~ /drakbug/ || $error =~ /wizcancel/ || !-x '/usr/bin/drakbug') {
    	warn $error;
    	exit(1);
    }
    $progname =~ s|.*/||;
    exec('drakbug',  if_($error, '--error', $error), '--incident', $progname);
    c::_exit(1);
}

if (!$ENV{DISABLE_DRAKBUG}) {
    $SIG{SEGV} = sub { bug_handler(@_, 1) };
    $SIG{__DIE__} = \&bug_handler;
}

1;
