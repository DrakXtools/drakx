package interactive::http; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use CGI;
use interactive;
use common;
use log;

my $script_name = $ENV{INTERACTIVE_HTTP};
my $no_header;
my $pipe_r = "/tmp/interactive_http_r";
my $pipe_w = "/tmp/interactive_http_w";

sub open_stdout() {
    open STDOUT, ">$pipe_w" or die;
    $| = 1;
    print CGI::header();
    $no_header = 1;    
}

# cont_stdout must be called after open_stdout and before the first print
sub cont_stdout {
    my ($o_title) = @_;
    print CGI::start_html('-title' => $o_title) if $no_header;
    $no_header = 0;
}

sub new_uid() {
    my ($s, $ms) = gettimeofday();
    $s * 256 + $ms % 256;
}

sub new {
    open_stdout();
    bless {}, $_[0];
}

sub end { 
    -e $pipe_r or return; # do not run this twice
    my $q = CGI->new;
    cont_stdout("Exit");
    print "It's done, thanks for playing", $q->end_html;
    close STDOUT;
    unlink $pipe_r, $pipe_w;
}
sub exit { end(); exit($_[1]) }
END { end() }

sub ask_fromW {
    my ($o, $common, $l, $_l2) = @_;

  redisplay:
    my $uid = new_uid();
    my $q = CGI->new;
    $q->param(state => 'next_step');
    $q->param(uid => $uid);
    cont_stdout($common->{title});

#    print $q->img({ -src => "/icons/$o->{icon}" }) if $o->{icon};
    print @{$common->{messages}};
    print $q->start_form('-name' => 'form', '-action' => $script_name, '-method' => 'post');

    print "<table>\n";

    each_index {
	my $e = $_;

	print "<tr><td>$e->{label}</td><td>\n";

	$e->{type} = 'list' if $e->{type} =~ /(icon|tree)list/;

	#- combo does not exist, fallback to a sensible default
	$e->{type} = $e->{not_edit} ? 'list' : 'entry' if $e->{type} eq 'combo';

	if ($e->{type} eq 'bool') {
	    print $q->checkbox('-name' => "w$::i", '-checked' => ${$e->{val}} && 'on', '-label' => $e->{text} || " ");
	} elsif ($e->{type} eq 'button') {
	    print "nobuttonyet";
	} elsif ($e->{type} =~ /list/) {
	    my %t; 
	    $t{$_} = may_apply($e->{format}, $_) foreach @{$e->{list}};

	    print $q->scrolling_list('-name' => "w$::i",
				     '-values' => $e->{list},
				     '-default' => [ ${$e->{val}} ],
				     '-size' => 5, '-multiple' => '', '-labels' => \%t);
	} else {
	    print $e->{hidden} ?
	      $q->password_field('-name' => "w$::i", '-default' => ${$e->{val}}) :
		   $q->textfield('-name' => "w$::i", '-default' => ${$e->{val}});
	}

	print "</td></tr>\n";
    } @$l;

    print "</table>\n";
    print $q->p;
    print $q->submit('-name' => 'ok_submit', '-value' => $common->{ok} || N("Ok"));
    print $q->submit('-name' => 'cancel_submit', '-value' => $common->{cancel} || N("Cancel")) if $common->{cancel} || !exists $common->{ok};
    print $q->hidden('state'), $q->hidden('uid');
    print $q->end_form, $q->end_html;

    close STDOUT; # page terminated

    while (1) {	
	open(my $F, "<$pipe_r") or die;
	$q = CGI->new($F);
	$q->param('force_exit_dead_prog') and $o->exit;
	last if $q->param('uid') == $uid;

	open_stdout(); # re-open for writing
	cont_stdout(N("Error"));
	print $q->h1(N("Error")), $q->p("Sorry, you can not go back");
	goto redisplay;
    }
    each_index {
	my $e = $_;
	my $v = $q->param("w$::i");
	if ($e->{type} eq 'bool') {
	    $v = $v eq 'on';
	}
	${$e->{val}} = $v;
    } @$l;

    open_stdout(); # re-open for writing
    $q->param('ok_submit');
}

sub p {
    print "\n" . CGI::br($_) foreach @_;
}

sub wait_messageW {
    my ($_o, $_title, $message, $message_modifiable) = @_;
    cont_stdout();
    print "\n" . CGI::p();
    p($message, $message_modifiable);
}

sub wait_message_nextW {
    my ($_o, $message, $_w) = @_;
    p($message);
}
sub wait_message_endW {
    my ($_o, $_w) = @_;
    p(N("Done"));
    print "\n" . CGI::p();
}

sub ok {
    N("Ok");
}

sub cancel {
    N("Cancel");
}


1;
