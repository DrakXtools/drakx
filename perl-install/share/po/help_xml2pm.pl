#!/usr/bin/perl -w

use XML::Parser;
use MDK::Common;
use utf8;

my $dir = "doc/manualB/modules";
my $xsltproc = "/usr/bin/xsltproc";

if ( ! -x "$xsltproc" ){
    print "You need to have \"$xsltproc\" - ";
    print "so type \"urpmi libxslt-proc\" please.\n";
    exit 1;
}

my %helps = map {
    my $lang = $_;
    my @l = grep { !/drakx-MNF-chapter/ } map { /(drakx-.*).xml$/ } all("$dir/$lang");
    if (@l < 20) { () } else {
	my $template_file = "$dir/$lang/drakx.xml";
	my $file = "$dir/$lang/drakx_full.xml";
    	output($template_file, template($lang, @l));
	system("$xsltproc id.xsl $template_file > $file") == 0 or die "$xsltproc id.xsl $template_file failed\n";
    
	my $p = new XML::Parser(Style => 'Tree');
	my $tree = $p->parsefile($file);

	$lang => rewrite2(rewrite1(@$tree), $lang);
    }
} all($dir);

my $base = delete $helps{en} || die;
save_help($base);

foreach my $lang (keys %helps) {
    print "Now transforming: $lang\n";
    my ($charset) = cat_("$lang.po") =~ /charset=([^\\]+)/ or die "missing charset in $lang.po\n";
    open(my $F, ">:encoding($charset)", "help-$lang.pot");
    print $F <<EOF;
msgid ""
msgstr ""
"Content-Type: text/plain; charset=$charset\\n"

EOF
    foreach my $id (keys %{$helps{$lang}}) {
#	warn "Writing id=$id in lang=$lang\n";
	$base->{$id} or warn "$lang:$id doesn't exist in english\n", next;
	print $F qq(# DO NOT BOTHER TO MODIFY HERE, SEE:\n# cvs.mandrakesoft.com:/cooker/$dir/$lang/drakx-chapter.xml\n);
	print_in_PO($F, to_ascii($base->{$id}[0]), $helps{$lang}{$id}[0]);
    }
}
unlink(".memdump");

sub print_in_PO {
    my ($F, $msgid, $msgstr) = @_;

    print $F qq(msgid ""\n");
    print $F join(qq(\\n"\n"), split "\n", $msgid);
    print $F qq("\nmsgstr ""\n");
    print $F join(qq(\\n"\n"), split "\n", $msgstr);
    print $F qq("\n\n);
}

sub save_help {
    my ($help, $inside_strings) = @_;

    open(my $F, ">:encoding(ascii)", "../../help.pm");
    print $F <<'EOF';
package help;
use common;

1;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.
EOF
    foreach (sort keys %$help) {
	my ($main, @inside) = map { '"' . to_ascii($_) . '"' } @{$help->{$_}};
	my $s = join(', ', $main, map { qq(N($_)) } @inside);
	print STDERR "Writing id=$_\n";
	print $F <<EOF;
sub $_() {
    N($s);
}
EOF
	my @nb = $main =~ /\%s/g; @nb == @inside or die "bad \%s in $_\n";
    }
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

my $help;
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

my @inside_strings;
sub rewrite2_ {
    my ($tree, @parents) = @_;
    ref($tree) or return $tree;
    !$tree->{attr}{condition} || $tree->{attr}{condition} !~ /no-inline-help/ or return '';

    my @prev_inside_strings;
    my ($id) = $tree->{attr}{id} ? $tree->{attr}{id} =~ /drakxid-([^-]+)$/ : ();
    if ($id) {
	@prev_inside_strings = @inside_strings;
	@inside_strings = ();
    }

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

    if ($id) {
	my $t = $text;
	$t =~ s/^\s+//;

	my @footnotes = map { 
	    my $s = rewrite2_({ %$_, tag => 'para' });
	    $s =~ s/^\s+//;
	    "(*) $s";
	} find_tag('footnote', $tree);
	$help->{$id} = [ aerate($t . join('', @footnotes)), @inside_strings ];
	unshift @inside_strings, @prev_inside_strings;
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
    } elsif (member($tree->{tag}, 'literal', 'filename')) {
	($i18ned_open_label_quote || "\\\"") . $text . ($i18ned_close_label_quote || "\\\"");
    } elsif (member($tree->{tag}, 'guilabel', 'guibutton', 'guimenu')) {
	$text =~ s/\s+$//;
	push @inside_strings, $text;
	($i18ned_open_label_quote || "\\\"") . "%s" . ($i18ned_close_label_quote || "\\\"");
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

sub template {
    my ($lang, @l) = @_;
    my $entities = join("\n", map { qq(<!ENTITY $_ SYSTEM '$_.xml'>) } @l);
    my $body = join("\n", map { '&' . $_ . ';' } @l);

    <<EOF;
<?xml version='1.0' encoding='ISO-8859-1'?>

<!DOCTYPE book PUBLIC "-//OASIS//DTD DocBook XML V4.1.2//EN"
"/usr/share/sgml/docbook/xml-dtd-4.1.2/docbookx.dtd"[

$entities

<!ENTITY % params.ent SYSTEM "../../manuals/Starter/$lang/params.ent">
%params.ent;
<!ENTITY % strings.ent SYSTEM "../../manuals/Starter/$lang/strings.ent">
%strings.ent;

<!ENTITY step-only-for-expert "">

<!ENTITY % acronym-list SYSTEM "../../entities/$lang/acronym_list.ent" >
%acronym-list;
<!ENTITY % button-list SYSTEM "../../entities/$lang/button_list.ent" >
%button-list;
<!ENTITY % companies SYSTEM "../../entities/$lang/companies.ent" >
%companies;
<!ENTITY % icon-list SYSTEM "../../entities/$lang/icon_list.ent" >
%icon-list;
<!ENTITY % menu-list SYSTEM "../../entities/$lang/menu_list.ent" >
%menu-list;
<!ENTITY % tab-list SYSTEM "../../entities/$lang/tab_list.ent" >
%tab-list;
<!ENTITY % tech SYSTEM "../../entities/$lang/tech.ent" >
%tech;
<!ENTITY % text-field-list SYSTEM "../../entities/$lang/text_field_list.ent" >
%text-field-list;
<!ENTITY % titles SYSTEM "../../entities/$lang/titles.ent" >
%titles;
<!ENTITY % typo SYSTEM "../../entities/$lang/typo.ent" >
%typo;
<!ENTITY % common SYSTEM "../../entities/common.ent" >
%common;
<!ENTITY % common-acronyms SYSTEM "../../entities/common_acronyms.ent" >
%common-acronyms;
<!ENTITY % prog-list SYSTEM "../../entities/prog_list.ent" >
%prog-list;

<!ENTITY lang '$lang'>

]>

<book>
  <title>DrakX Documentation</title>

$body

</book>
EOF

}
