#!/usr/bin/perl

use lib qw(/usr/lib/libDrakX);
use CGI;
use common;
use c;

my $q = CGI->new;
$| = 1;

my $script_name = $q->url(-relative => 1);

# name inversed (must be in sync with interactive_http.html)
my $pipe_r = "/tmp/interactive_http_w";
my $pipe_w = "/tmp/interactive_http_r";

if ($q->param('state') eq 'new') {
    force_exit_dead_prog();
    mkfifo($pipe_r); mkfifo($pipe_w);

    spawn_server($q->param('prog'));
    first_step();

} elsif ($q->param('state') eq 'next_step') {
    next_step();
} else {
    error("booh...");
}

sub read_ {
    local *F;
    open F, "<$pipe_r" or error("Failed to connect to the prog");
    my $t;
    print $t while sysread F, $t, 1;
}
sub write_ {
    local *F;
    open F, ">$pipe_w" or die;
    my $q = CGI->new;
    $q->save(\*F);
}

sub first_step { read_() }
sub next_step { write_(); read_() }


sub force_exit_dead_prog {
    -p $pipe_w or return;
    {
	local *F;
	sysopen F, $pipe_w, 1 | c::O_NONBLOCK() or return;
	syswrite F, "force_exit_dead_prog=1\n";
    }

    my $cnt = 10;
    while (-p $pipe_w) {
	sleep 1;
	$cnt-- or error("Dead prog failed to exit");
    }
}

sub spawn_server {
    my ($prog) = @_;

    my @authorised_progs = map { chomp_($_) } cat_('/etc/drakxtools_http/authorised_progs');
    member($prog, @authorised_progs) or error("You tried to call a non-authorised program");

    fork and return;

    $ENV{INTERACTIVE_HTTP} = $script_name;

    open STDIN, "</dev/zero";
    open STDOUT, ">/dev/null"; #tmp/log";
    open STDERR, ">&STDOUT";

    c::setsid();
    exec $prog or die "prog $prog not found\n";
}

sub error {
    print $q->header(), $q->start_html();
    print $q->h1(N("Error")), @_;
    print $q->end_html(), "\n";
    exit 0;
}

sub mkfifo {
    my ($f) = @_;
    -p $f and return;
    unlink $f;
    syscall_('mknod', $f, c::S_IFIFO() | 0600, 0) or die "mkfifo failed";
    chmod 0666, $f;
}
