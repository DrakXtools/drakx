#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakelinux Control Center</b>"), center => 1 ],
	' ',
	N("The <b>Mandrakelinux Control Center</b> is an essential collection of Mandrakelinux-specific utilities designed to simplify the configuration of your computer."),
	' ',
	N("You will immediately appreciate this collection of <b>more than 60</b> handy utilities for <b>easily configuring your system</b>: hardware devices, mount points, network and Internet, security level of your computer, etc."));