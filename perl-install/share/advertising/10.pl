#!/usr/bin/perl

use utf8;

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandriva Products (Nomad Products)</b>"), center => 1 ],
	' ',
	N("Mandriva has developed two products that allow you to use Mandriva Linux <b>on any computer</b> and without any need to actually install it:"),
	N("	* <b>Move</b>, a Mandriva Linux distribution that runs entirely from a bootable CD-ROM."),
	N("	* <b>GlobeTrotter</b>, a Mandriva Linux distribution pre-installed on the ultra-compact “LaCie Mobile Hard Drive”."));
