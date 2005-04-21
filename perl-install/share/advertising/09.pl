#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandriva Products</b>"), center => 1 ],
	' ',
	N("<b>Mandriva</b> has developed a wide range of <b>Mandrivalinux</b> products."),
	' ',
	N("The Mandrivalinux products are:"),
	N("	* <b>Discovery</b>, Your First Linux Desktop."),
	N("	* <b>PowerPack</b>, The Ultimate Linux Desktop."),
	N("	* <b>PowerPack+</b>, The Linux Solution for Desktops and Servers."),
	N("	* <b>Mandrivalinux for x86-64</b>, The Mandrivalinux solution for making the most of your 64-bit processor."));
