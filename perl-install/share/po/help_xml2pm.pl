#!/usr/bin/perl

use XML::Parser;
use MDK::Common;

@ARGV == 1 or die "usage: help_xml2pm <drakx-help.xml>\n";

my $p = new XML::Parser(Style => 'Tree');
my $tree = $p->parsefile($ARGV[0]);
my $help = {};

# rewrite2 fills in $help
rewrite2(rewrite1(@$tree));

print 
q{package help;
use common;
%steps = (
empty => '',
};
print qq(
$_ => 
__("$help->{$_}"),
) foreach sort keys %$help;
print ");\n";


# i don't like the default tree format given by XML::Parser,
# rewrite it in my own tree format
sub rewrite1 {
    my ($tag, $tree) = @_;
    my ($attr, @nodes) = @$tree;
    my @l;
    while (@nodes) {
	my ($tag, $tree) = splice(@nodes, 0, 2);
	if ($tag eq '0') {
	    foreach ($tree) {
		s/\s+/ /gs;
		s/"/\\"/g;
	    }
	}
	push @l, $tag eq '0' ? $tree : rewrite1($tag, $tree);
    }
    { attr => $attr, tag => $tag, children => \@l };
}

# return the list of nodes named $tag
sub find {
    my ($tag, $tree) = @_;
    if (!ref($tree)) {
	();
    } elsif ($tree->{tag} eq $tag) {
	$tree;
    } else {
	map { find($tag, $_) } @{$tree->{children}};
    }
}

sub rewrite2 {
    my ($tree) = @_;
    ref($tree) or return $tree;

    my $text = do {
	my @l = map { rewrite2($_) } @{$tree->{children}};
	my $text;
	foreach (grep { !/^\s*$/ } @l) {
	    s/^ // if $text =~ /\s$/;
	    $text =~ s/ $// if /^\s/;
	    $text =~ s/\n+$// if /^\n/;
	    $text .= $_;
	}
	$text;
    };

    if (0) {
    } elsif (member($tree->{tag}, 'para', 'itemizedlist', 'orderedlist')) {
	$text =~ s/^\s(?!\s)//;
	$text =~ s/^( ?\n)+//;
	$text =~ s/\s+$//;
	qq(\n$text\n);
    } elsif ($tree->{tag} eq 'quote') {
	qq(``$text'');
    } elsif ($tree->{tag} eq 'command') {
	qq(\\"$text\\");
    } elsif ($tree->{tag} eq 'userinput') {
	qq(>>$text<<);
    } elsif ($tree->{tag} eq 'footnote') {
	'(*)'
    } elsif ($tree->{tag} eq 'warning') {
	$text =~ s/^(\s+)/$1!! /;
	$text =~ s/(\s+)$/ !!$1/;
	$text;
    } elsif ($tree->{tag} eq 'listitem') {
	my $cnt;
	$text =~ s/^\s+//;
	$text =~ s/^/' ' . ($cnt++ ? '  ' : '* ')/emg;
	"\n$text\n";

    } elsif (member($tree->{tag}, 'guibutton', 'guimenu', 'guilabel',
                    'emphasis', 'acronym', 'keycap', 'ulink', 'tip', 'note',
		    'primary', 'indexterm',
		   )) {
	# ignored tags
	$text;
    } elsif (member($tree->{tag}, 'title', 'article')) {
	# dropped tags
	'';
    } elsif ($tree->{tag} eq 'sect1') {
	$text =~ s/^\s+//;

	my @footnotes = map { 
	    my $s = rewrite2({ %$_, tag => 'para' });
	    $s =~ s/^\s+//;
	    "(*) $s";
	} find('footnote', $tree);
	$help->{$tree->{attr}{id}} = aerate($text . join('', @footnotes));
	'';
    } else {
	die "unknown tag $tree->{tag}\n";
    }
}

sub aerate {
    my ($s) = @_;
    my $s2 = join("\n\n", map { join("\n", warp_text($_)) } split "\n", $s);
    $s2;
}
