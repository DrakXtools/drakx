package interactive_stdio;

use diagnostics;
use strict;
use vars qw(@ISA);

@ISA = qw(interactive);

use interactive;
use common qw(:common);

1;

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
    my ($o, $title, $messages, $list, $def) = @_;
    my $i;
    print map { "$_\n" } @$messages;

    if (@$list < 10 && sum(map { length $_ } @$list) < 50) {
	my @l;
	do {
	    if (defined $i) {
		@l ? print _("Ambiguity (%s) be more precise\n", join(", ", @l)) :
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

sub ask_many_from_listW {
    my ($o, $title, $messages, $list, $default) = @_;
    my @defaults;
    print map { "$_\n" } @$messages;
    my $n = 0; foreach (@$list) { 
	$n++; 
	print "$n: $_\n"; 
	push @defaults, $n if $default->[$n - 1];
    }
    my $i;
    TRY_AGAIN:
    defined $i and print _("Bad choice, try again\n");
    print _("Your choice? (default %s  enter `none' for none) ", join(',', @defaults));
    $i = readln();
    my @t = split ',', $i;
    foreach (@t) { check_it($_, $n) or goto TRY_AGAIN }

    my @rr = (0) x @$list;
    $rr[$_ - 1] = 1 foreach @t;
    @rr;
}


