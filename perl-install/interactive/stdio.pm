package interactive::stdio; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common;

$| = 1;

sub readln() {
    my $l = <STDIN>;
    chomp $l;
    $l;
}

sub check_it {
    my ($i, $n) = @_;
    $i =~ /^\s*\d+\s*$/ && 1 <= $i && $i <= $n;
}

sub good_choice {
    my ($def_s, $max) = @_;
    my $i;
    do {
	defined $i and print N("Bad choice, try again\n");
	print N("Your choice? (default %s) ", $def_s);
	$i = readln();
    } until !$i || check_it($i, $max);
    $i;
}

sub ask_fromW {
    my ($_o, $common, $l, $_l2) = @_;

    add2hash_($common, { ok => N("Ok"), cancel => N("Cancel") }) if !exists $common->{ok};

ask_fromW_begin:

    my $already_entries = 0;
    my $predo_widget = sub {
	my ($e) = @_;

	$e->{type} = 'list' if $e->{type} =~ /(icon|tree)list/;
	#- combo does not exist, fallback to a sensible default
	$e->{type} = $e->{not_edit} ? 'list' : 'entry' if $e->{type} eq 'combo';

	if ($e->{type} eq 'entry') {
	    my $t = "\t$e->{label} $e->{text}\n";
	    if ($already_entries) {
		length($already_entries) > 1 and print N("Entries you'll have to fill:\n%s", $already_entries);
		$already_entries = 1;
		print $t;
	    } else {
		$already_entries = $t;
	    }
	}
    };

    my @labels;
    my $format_label = sub { my ($e) = @_; return sprintf("`%s' %s %s\n", ${$e->{val}}, $e->{label}, $e->{text}) };
    my $do_widget = sub {
	my ($e, $ind) = @_;

	if ($e->{type} eq 'bool') {
	    print "$e->{text} $e->{label}\n";
	    print N("Your choice? (0/1, default `%s') ", ${$e->{val}} || '0');
	    my $i = readln();
	    if ($i) {
		to_bool($i) != to_bool(${$e->{val}}) and $common->{changed}->($ind);
		${$e->{val}} = $i;
	    }
	} elsif ($e->{type} =~ /list/) {
	    $e->{text} || $e->{label} and print "=> $e->{label} $e->{text}\n";
	    my $n = 0; my $size = 0;
	    foreach (@{$e->{list}}) {
		$n++;
		my $t = "$n: " . may_apply($e->{format}, $_) . "\t";
		if ($size + length($t) >= 80) {
		    print "\n";
		    $size = 0;
		}
		print $t;
		$size += length($t);
	    }
	    print "\n";
	    my $i = good_choice(may_apply($e->{format}, ${$e->{val}}), $n);
	    print "Setting to <", $i ? ${$e->{list}}[$i-1] : ${$e->{val}}, ">\n";
	    $i and ${$e->{val}} = ${$e->{list}}[$i-1], $common->{changed}->($ind);
	} elsif ($e->{type} eq 'button') {
	    print N("Button `%s': %s", $e->{label}, may_apply($e->{format}, ${$e->{val}})), " $e->{text}\n";
	    print N("Do you want to click on this button?");
	    my $i = readln();
	    $i && $i !~ /^n/i and $e->{clicked_may_quit}(), $common->{changed}->($ind);
	} elsif ($e->{type} eq 'label') {
	    my $t = $format_label->($e);
	    push @labels, $t;
	    print $t;
	} elsif ($e->{type} eq 'entry') {
	    print "$e->{label} $e->{text}\n";
	    print N("Your choice? (default `%s'%s) ", ${$e->{val}}, ${$e->{val}} ? N(" enter `void' for void entry") : '');
	    my $i = readln();
	    ${$e->{val}} = $i || ${$e->{val}};
	    ${$e->{val}} = '' if ${$e->{val}} eq 'void';
	    print "Setting to <", ${$e->{val}}, ">\n";
	    $i and $common->{changed}->($ind);
	} else {
	    printf "UNSUPPORTED WIDGET TYPE (type <%s> label <%s> text <%s> val <%s>\n", $e->{type}, $e->{label}, $e->{text}, ${$e->{val}};
	}
    };

    print "* ";
    $common->{title} and print "$common->{title}\n";
    print(map { "$_\n" } @{$common->{messages}});

    $predo_widget->($_) foreach @$l;
    if (listlength(@$l) > 30) {
	my $ll = listlength(@$l);
	print N("=> There are many things to choose from (%s).\n", $ll);
ask_fromW_handle_verylonglist:
	print
N("Please choose the first number of the 10-range you wish to edit,
or just hit Enter to proceed.
Your choice? ");
	my $i = readln();
	if (check_it($i, $ll)) {
	    each_index { $do_widget->($_, $::i) } grep_index { $::i >= $i-1 && $::i < $i+9 } @$l;
	    goto ask_fromW_handle_verylonglist;
	}
    } else {
	each_index { $do_widget->($_, $::i) } @$l;
    }

    my $lab;
    each_index { $labels[$::i] && (($lab = $format_label->($_)) ne $labels[$::i]) and print N("=> Notice, a label changed:\n%s", $lab) }
      grep { $_->{type} eq 'label' } @$l;

    my $i;
    if (listlength(@$l) != 1 || $common->{ok} ne N("Ok") || $common->{cancel} ne N("Cancel")) {
	print "[1] ", $common->{ok} || N("Ok");
	$common->{cancel} and print "  [2] $common->{cancel}";
	@$l and print "  [9] ", N("Re-submit");
	print "\n";
	do {
	    defined $i and print N("Bad choice, try again\n");
	    print N("Your choice? (default %s) ", $common->{focus_cancel} ? $common->{cancel} : $common->{ok});
	    $i = readln() || ($common->{focus_cancel} ? "2" : "1");
	} until check_it($i, 9);
	$i == 9 and goto ask_fromW_begin;
    } else {
	$i = 1;
    }
    if ($i == 1 && !$common->{validate}()) {
	goto ask_fromW_begin;
    }
    return $i != 2;
}

sub wait_messageW {
    my ($_o, $_title, $message, $message_modifiable) = @_;
    print join "\n", $message, $message_modifiable;
}
sub wait_message_nextW { 
    my $m = join "\n", $_[1];
    print "\r$m", ' ' x (60 - length $m);
}
sub wait_message_endW { print "\nDone\n" }

1;

