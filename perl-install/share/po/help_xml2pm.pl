#!/usr/bin/perl -w

use XML::Parser;
use MDK::Common;

my $help;
my $dir = "doc/manual/literal/drakx";
my @langs = grep { /^..$/ && -e "$dir/$_/drakx-help.xml" } all($dir) or die "no XML help found in $dir\n";

my %helps = map {
    my $lang = $_;
    my $p = new XML::Parser(Style => 'Tree');
    open F, "xsltproc id.xsl $dir/$lang/drakx-help.xml|";
    my $tree = $p->parse(*F);

    $lang => rewrite2(rewrite1(@$tree), $lang);
} @langs;

my $base = delete $helps{en} || die;
save_help($base);

foreach my $lang (keys %helps) {
    print "Now transforming: $lang\n";
    local *F;
    my ($charset) = cat_("$lang.po") =~ /charset=([^\\]+)/ or die "missing charset in $lang.po\n";
    open F, "| iconv -f utf8 -t $charset//TRANSLIT > help-$lang.pot";
    #open F, "|cat - > help-$lang.pot";
    print F "\n";
    foreach my $id (keys %{$helps{$lang}}) {
	$base->{$id} or die "$lang:$id doesn't exist in english\n";
	print F qq(# DO NOT BOTHER TO MODIFY HERE, SEE:\n# cvs.mandrakesoft.com:/cooker/doc/manual/literal/drakx/$lang/drakx-help.xml\n);
	print F qq(msgid ""\n");
	print F join(qq(\\n"\n"), split "\n", $base->{$id});
	print F qq("\nmsgstr ""\n");
	print F join(qq(\\n"\n"), split "\n", $helps{$lang}{$id});
	print F qq("\n\n);
    }
}
unlink(".memdump");

sub save_help {
    my ($help) = @_;
    local *F;
    open F, "| LC_ALL=fr iconv -f utf8 -t ascii//TRANSLIT > ../../help.pm";
    print F q{package help;
use common;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.

%steps = (
empty => '',
};
    print F qq(
$_ => 
__("$help->{$_}"),
) foreach sort keys %$help;
    print F ");\n";
}

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
	    push @l, $tree
	} elsif ($tag eq 'screen') {
	    $tree->[1] eq '0' or die "screen tag contains non CDATA\n";
	    push @l, $tree->[2];
	} else {
	    push @l, rewrite1($tag, $tree);
	}
    }
    { attr => $attr, tag => lc $tag, children => \@l };
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
    use utf8;
    my ($tree, $lang) = @_;
    our $i18ned_open_text_quote  = $ {{ 
	fr => "« ",
	de => "„",
	es => "\\\"",
	it => "''",
	}}{$lang};
    our $i18ned_close_text_quote = $ {{ 
	fr => " »",
	de => "“",
	es => "\\\"",
	it => "''",
	}}{$lang};
    our $i18ned_open_label_quote  = $ {{ fr => "« ", de => "„"}}{$lang};
    our $i18ned_close_label_quote = $ {{ fr => " »", de => "“"}}{$lang};
    our $i18ned_open_command_quote  = $ {{ fr => "« ", de => "„"}}{$lang};
    our $i18ned_close_command_quote = $ {{ fr => " »", de => "“"}}{$lang};
    our $i18ned_open_input_quote  = $ {{ fr => "« ", de => "»"}}{$lang};
    our $i18ned_close_input_quote = $ {{ fr => " »", de => "«"}}{$lang};
    our $i18ned_open_key_quote  = $ {{ de => "["}}{$lang};
    our $i18ned_close_key_quote = $ {{ de => "]"}}{$lang};
    # rewrite2_ fills in $help
    $help = {};
    rewrite2_($tree);
    $help;
}

sub rewrite2_ {
    my ($tree) = @_;
    ref($tree) or return $tree;

    my $text = do {
	my @l = map { rewrite2_($_) } @{$tree->{children}};
	my $text = "";
	foreach (grep { !/^\s*$/ } @l) {
	    s/^ // if $text =~ /\s$/;
	    $text =~ s/ $// if /^\s/;
	    $text =~ s/\n+$// if /^\n/;
	    $text .= $_;
	}
	$text;
    };

    if (0) {
    } elsif (member($tree->{tag}, 'formalpara', 'para', 'itemizedlist', 'orderedlist')) {
	$text =~ s/^\s(?!\s)//;
	$text =~ s/^( ?\n)+//;
	$text =~ s/\s+$//;
	qq(\n$text\n);
    } elsif (member($tree->{tag}, 'quote', 'citetitle', 'foreignphrase')) {
	($i18ned_open_text_quote || "``") . $text . ($i18ned_close_text_quote || "''");
    } elsif (member($tree->{tag}, 'guilabel', 'guibutton', 'guimenu', 'literal')) {
	($i18ned_open_label_quote || "\\\"") . $text . ($i18ned_close_label_quote || "\\\"");
    } elsif ($tree->{tag} eq 'command') {
	($i18ned_open_command_quote || "\\\"") . $text . ($i18ned_close_command_quote || "\\\"");
    } elsif ($tree->{tag} eq 'userinput') {
	($i18ned_open_input_quote || ">>") . $text . ($i18ned_close_input_quote || "<<");
    } elsif ($tree->{tag} eq 'keycap') {
	($i18ned_open_key_quote || "[") . $text . ($i18ned_close_key_quote || "]");
    } elsif (member($tree->{tag}, 'keysym')) {
	qq($text);
    } elsif (member($tree->{tag}, 'footnote')) {
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

    } elsif (member($tree->{tag},  
		    'acronym', 'application', 'emphasis',  
		    'keycombo', 'note', 
		    'superscript', 'systemitem', 
		    'tip', 'ulink', 'xref' 
		   )) {
	# ignored tags
	$text;
    } elsif (member($tree->{tag},
		    'title', 'article', 'primary', 'secondary', 
		    'indexterm', 
		   )) {
	# dropped tags
	'';
    } elsif ($tree->{tag} eq 'sect1') {
	$text =~ s/^\s+//;

	my @footnotes = map { 
	    my $s = rewrite2_({ %$_, tag => 'para' });
	    $s =~ s/^\s+//;
	    "(*) $s";
	} find('footnote', $tree);
	$help->{$tree->{attr}{id}} = aerate($text . join('', @footnotes));
	'';
    } elsif ($tree->{tag} eq 'screen') {
	qq(\n$text\n);
    } else {
	die "unknown tag $tree->{tag}\n";
    }
}

sub aerate {
    my ($s) = @_;
    #- the warp_text column is adjusted so that xgettext do not wrap text around
    #- which cause msgmerge to add a lot of fuzzy
    my $s2 = join("\n\n", map { join("\n", warp_text($_, 75)) } split "\n", $s);
    $s2;
}
