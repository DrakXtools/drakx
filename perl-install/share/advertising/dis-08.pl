#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakelinux Control Center</b>"), center => 1 ],
        ' ',
	N("The Mandrakelinux Control Center is an essential collection of Mandrakelinux-specific utilities for simplifying the configuration of your computer."),
	' ',
	N("You will immediately appreciate this collection of handy utilities for easily configuring hardware devices, defining mount points, setting up Network and Internet, adjusting the security level of your computer, and just about everything related to the system."));
