#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakesoft Products (Nomad Products)</b>"), center => 1 ],
	' ',
	N("Mandrakesoft has developed two products that allow you to use Mandrakelinux <b>on any computer</b> and without any need to actually install it:"),
	N("	* <b>Move</b>, a Mandrakelinux distribution that runs entirely from a bootable CD-Rom."),
	N("	* <b>GlobeTrotter</b>, a Mandrakelinux distribution pre-installed on the ultra-compact “LaCie Mobile Hard Drive”."));