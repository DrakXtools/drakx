#!/usr/bin/perl -w

use MDK::Common;

my @prev = get("DrakX.pot.old");
my @curr = get("DrakX.pot");

@prev == @curr or die "the number of messages has changed: " . int(@prev) . " is now " . int(@curr);

my %l = map_index { $_ => $prev[$::i] } @curr;

while (my ($new, $old) = each %l) {
    my ($s_old) = $old =~ /"(.*)\\n"/ or die "<$old>";
    my ($s_new) = $new =~ /"(.*)\\n"/ or die "<$new>";
    next if $s_old eq $s_new;

    warn "mismatch\n  in $s_old\n  vs $s_new\n";
}

print STDERR "Is that ok (Y/n) ? ";
<STDIN> !~ /n/i or exit;

foreach my $po (glob_("*.po")) {
    my $s = cat_($po);
    while (my ($new, $old) = each %l) {
	my $offset = index($s, $old);
	if ($offset >= 0) {
	    #	print STDERR "replacing $old with $new\n";
	    substr($s, $offset, length($old), $new);
	}
    }
    output($po, $s);
}


sub get {
    my ($file) = @_;
    my @l;
    foreach (cat_($file)) {
	my $nb = /^#:.*help\.pm/ .. /msgstr ""/ or next;
	if ($nb =~ /E0/) {
	    push @l, $s if $s;
	    $s = '';
	} elsif (/^"/) {
	    $s .= $_;
	}
    }
    @l;
}

