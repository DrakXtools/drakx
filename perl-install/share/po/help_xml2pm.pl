#!/usr/bin/perl -w

use XML::Parser;
use MDK::Common;
use utf8;

my $help;
my $dir = "doc/manualB/modules";
my $xsltproc = "/usr/bin/xsltproc";

if ( ! -x "$xsltproc" ){
    print "You need to have \"$xsltproc\" - ";
    print "so type \"urpmi libxslt-proc\" please.\n";
    exit 1;
}
my @langs = grep { !/ru|pt/ } grep { /^..$/ && -e "$dir/$_/drakx-chapter.xml" } all($dir) or die "no XML help found in $dir\n";

my %helps = map {
    my $lang = $_;
    my $file = "$dir/$lang/drakx_full.xml";
    my $template_file = "$dir/$lang/drakx.xml";
    
    output($template_file, do { (my $s = $template) =~ s/__LANG__/$lang/g; $s });
    system("$xsltproc id.xsl $template_file > $file") == 0 or die "$xsltproc id.xsl $template_file failed\n";
    
    my $p = new XML::Parser(Style => 'Tree');
    my $tree = $p->parsefile($file);

    $lang => rewrite2(rewrite1(@$tree), $lang);
} @langs;

my $base = delete $helps{en} || die;
save_help($base);

foreach my $lang (keys %helps) {
    print "Now transforming: $lang\n";
    local *F;
    my ($charset) = cat_("$lang.po") =~ /charset=([^\\]+)/ or die "missing charset in $lang.po\n";
    open F, ">:encoding($charset)", "help-$lang.pot";
    print F "\n";
    foreach my $id (keys %{$helps{$lang}}) {
	$base->{$id} or warn "$lang:$id doesn't exist in english\n", next;
	print F qq(# DO NOT BOTHER TO MODIFY HERE, SEE:\n# cvs.mandrakesoft.com:/cooker/$dir/$lang/drakx-chapter.xml\n);
	print F qq(msgid ""\n");
	print F join(qq(\\n"\n"), split "\n", to_ascii($base->{$id}));
	print F qq("\nmsgstr ""\n");
	print F join(qq(\\n"\n"), split "\n", $helps{$lang}{$id});
	print F qq("\n\n);
    }
}
unlink(".memdump");

sub save_help {
    my ($help) = @_;

    #- HACK, don't let this one disappear
    $help->{configureXxdm} = 
'Finally, you will be asked whether you want to see the graphical interface
at boot. Note this question will be asked even if you chose not to test the
configuration. Obviously, you want to answer \"No\" if your machine is to
act as a server, or if you were not successful in getting the display
configured.';

    local *F;
    open F, ">:encoding(ascii)", "../../help.pm";
    print F q{package help;
use common;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.

our %steps = (
};
    foreach (sort keys %$help) {
	my $s = to_ascii($help->{$_});
	print STDERR "Writing id=$_\n";
	print F qq(\n$_ => \nN_("$s"),\n);
    }
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
		s/\x{ad}//g;
		s/\x{2013}/-/g;
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
sub find_tag {
    my ($tag, $tree) = @_;
    if (!ref($tree)) {
	();
    } elsif ($tree->{tag} eq $tag) {
	$tree;
    } else {
	map { find_tag($tag, $_) } @{$tree->{children}};
    }
}

sub rewrite2 {
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
    my ($tree, @parents) = @_;
    ref($tree) or return $tree;
    !$tree->{attr}{condition} || $tree->{attr}{condition} !~ /no-inline-help/ or return '';

    my $text = do {
	my @l = map { rewrite2_($_, $tree, @parents) } @{$tree->{children}};
	my $text = "";
	foreach (@l) {
	    s/^ // if $text =~ /\s$/;
	    $text =~ s/ $// if /^\s/;
	    $text =~ s/\n+$// if /^\n/;
	    $text .= $_;
	}
	$text;
    };

    if ($tree->{attr}{id} && $tree->{attr}{id} =~ /drakxid-(.+)/) {
	my $id = $1;
	my $t = $text;
	$t =~ s/^\s+//;

	my @footnotes = map { 
	    my $s = rewrite2_({ %$_, tag => 'para' });
	    $s =~ s/^\s+//;
	    "(*) $s";
	} find_tag('footnote', $tree);
	$help->{$id} = aerate($t . join('', @footnotes));
    }

    if (0) {
    } elsif (member($tree->{tag}, 'formalpara', 'para', 'itemizedlist', 'orderedlist')) {
	$text =~ s/^\s(?!\s)//;
	$text =~ s/^( ?\n)+//;
	$text =~ s/\s+$//;
	qq(\n$text\n);
    } elsif (member($tree->{tag}, 'quote', 'citetitle', 'foreignphrase')) {
	$text =~ s/^\Q$i18ned_open_label_quote\E(.*)\Q$i18ned_close_label_quote\E$/$1/ if $i18ned_open_label_quote;
	($i18ned_open_text_quote || "``") . $text . ($i18ned_close_text_quote || "''");
    } elsif (member($tree->{tag}, 'guilabel', 'guibutton', 'guimenu', 'literal', 'filename')) {
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
	my $cnt = (any { $_->{tag} eq 'variablelist' } @parents) ? 1 : 0;
	$text =~ s/^\s+//;
	$text =~ s/^/' ' . ($cnt++ ? '  ' : '* ')/emg;
	"\n$text\n";
    } elsif (member($tree->{tag},  
		    'acronym', 'application', 'emphasis',  
		    'keycombo', 'note', 'sect1', 'sect2',
		    'superscript', 'systemitem', 
		    'tip', 'ulink', 'xref', 'varlistentry', 'variablelist', 'term',
		   )) {
	# ignored tags
	$text;
    } elsif (member($tree->{tag},
		    qw(title article primary secondary indexterm revnumber
                       date authorinitials revision revhistory revremark chapterinfo
                       imagedata imageobject mediaobject figure
                       abstract book chapter)
		   )) {
	# dropped tags
	'';
    } elsif ($tree->{tag} eq 'screen') {
	qq(\n$text\n);
    } else {
	warn "unknown tag $tree->{tag}\n";
    }
}

sub aerate {
    my ($s) = @_;
    #- the warp_text column is adjusted so that xgettext do not wrap text around
    #- which cause msgmerge to add a lot of fuzzy
    my $s2 = join("\n\n", map { join("\n", warp_text($_, 75)) } split "\n", $s);
    $s2;
}

sub to_ascii {
    local $_ = $_[0];
    tr[ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ]
      [AAAAAAACEEEEIIIIDNOOOOOxOUUUUY_aaaaaaaceeeeiiiionooooo_ouuuuy_y];
    s/\x81//g; #- why is this needed???
    s/ß/ss/g;
    $_;
}

BEGIN {
    $template = <<'EOF';
<?xml version='1.0' encoding='ISO-8859-1'?>

<!DOCTYPE book PUBLIC "-//OASIS//DTD DocBook XML V4.1.2//EN"
"/usr/share/sgml/docbook/xml-dtd-4.1.2/docbookx.dtd"[

<!ENTITY drakx-chapter SYSTEM 'drakx-chapter.xml'>

<!ENTITY % params.ent SYSTEM "../../manuals/Starter/__LANG__/params.ent">
%params.ent;
<!ENTITY % strings.ent SYSTEM "../../manuals/Starter/__LANG__/strings.ent">
%strings.ent;

<!ENTITY step-only-for-expert "">

<!ENTITY % acronym-list SYSTEM "../../entities/__LANG__/acronym_list.ent" >
%acronym-list;
<!ENTITY % button-list SYSTEM "../../entities/__LANG__/button_list.ent" >
%button-list;
<!ENTITY % companies SYSTEM "../../entities/__LANG__/companies.ent" >
%companies;
<!ENTITY % icon-list SYSTEM "../../entities/__LANG__/icon_list.ent" >
%icon-list;
<!ENTITY % menu-list SYSTEM "../../entities/__LANG__/menu_list.ent" >
%menu-list;
<!ENTITY % tab-list SYSTEM "../../entities/__LANG__/tab_list.ent" >
%tab-list;
<!ENTITY % tech SYSTEM "../../entities/__LANG__/tech.ent" >
%tech;
<!ENTITY % text-field-list SYSTEM "../../entities/__LANG__/text_field_list.ent" >
%text-field-list;
<!ENTITY % titles SYSTEM "../../entities/__LANG__/titles.ent" >
%titles;
<!ENTITY % typo SYSTEM "../../entities/__LANG__/typo.ent" >
%typo;
<!ENTITY % common SYSTEM "../../entities/common.ent" >
%common;
<!ENTITY % common-acronyms SYSTEM "../../entities/common_acronyms.ent" >
%common-acronyms;
<!ENTITY % prog-list SYSTEM "../../entities/prog_list.ent" >
%prog-list;

<!ENTITY lang '__LANG__'>

]>

<book>
  <title>DrakX Documentation</title>

  &drakx-chapter;

</book>
EOF

}
