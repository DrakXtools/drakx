#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandriva Products (Professional Solutions)</b>"), center => 1 ],
	' ',
	N("Below are the Mandriva products designed to meet the <b>professional needs</b>:"),
	N("	* <b>Corporate Desktop</b>, The Mandrivalinux Desktop for Businesses."),
	N("	* <b>Corporate Server</b>, The Mandrivalinux Server Solution."),
	N("	* <b>Multi-Network Firewall</b>, The Mandrivalinux Security Solution."));