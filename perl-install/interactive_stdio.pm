package interactive_stdio; # $Id$

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common);

$| = 1;

sub readln {
    my $l = <STDIN>;
    chomp $l;
    $l;
}

sub check_it {
    my ($i, $n) = @_;
    $i =~ /^\s*\d+\s*$/ && 1 <= $i && $i <= $n
}

sub ask_from_listW {
    my ($o, $title_, $messages, $list, $def) = @_;
    my ($title, @okcancel) = ref $title_ ? @$title_ : ($title_, _("Ok"), _("Cancel"));
    print map { "$_\n" } @$messages;
    my $i;

    if (@$list < 10 && sum(map { length $_ } @$list) < 50) {
	my @l;
	do {
	    if (defined $i) {
		@l ? print _("Ambiguity (%s), be more precise\n", join(", ", @l)) :
		     print _("Bad choice, try again\n");
	    }
	    @$list == 1 ? print @$list :
	                  print join("/", @$list), _(" ? (default %s) ", $def);
	    $i = readln() || $def;
	    @l = grep { /^$i/ } @$list;
	} until (@l == 1);
	$l[0];
    } else {
	my $n = 0; foreach (@$list) {
	    $n++;
	    $def eq $_ and $def = $n;
	    print "$n: $_\n";
	}
	do {
	    defined $i and print _("Bad choice, try again\n");
	    print _("Your choice? (default %s) ", $def);
	    $i = readln() || $def;
	} until (check_it($i, $n));
	$list->[$i - 1];
    }
}

sub ask_many_from_list_refW {
    my ($o, $title, $messages, $list, $val) = @_;
    my @defaults;
    print map { "$_\n" } @$messages;
    my $n = 0; foreach (@$list) {
	$n++;
	print "$n: $_\n";
	push @defaults, $n if ${$val->[$n - 1]};
    }
    my $i;
    TRY_AGAIN:
    defined $i and print _("Bad choice, try again\n");
    print _("Your choice? (default %s  enter `none' for none) ", join(',', @defaults));
    $i = readln();
    my @t = split ',', $i;
    if ($i =~ /^none$/i) {
	@t = ();
    } else {
	foreach (@t) { check_it($_, $n) or goto TRY_AGAIN }
    }

    $$_ = 0 foreach @$val;
    ${$val->[$_ - 1]} = 1 foreach @t;
    $val;
}

sub wait_messageW {
    my ($o, $title, $message) = @_;
    print join "\n", @$message;
}
sub wait_message_nextW { 
    my $m = join "\n", @{$_[1]};
    print "\r$m", ' ' x (60 - length $m);
}
sub wait_message_endW { print "\nDone\n" }

1;

