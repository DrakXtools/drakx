#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakesoft Products (Professional Solutions)</b>"), center => 1 ],
	' ',
	N("Below are the Mandrakesoft products designed to meet the <b>professional needs</b>:"),
	N("	* <b>Corporate Desktop</b>, The Mandrakelinux Desktop for Businesses."),
	N("	* <b>Corporate Server</b>, The Mandrakelinux Server Solution."),
	N("	* <b>Multi-Network Firewall</b>, The Mandrakelinux Security Solution."));