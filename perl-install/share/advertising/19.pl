#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Development Environments</b>"), center => 1 ],
	' ',
	N("PowerPack gives you the best tools to <b>develop</b> your own applications."),
	' ',
	N("You will enjoy the powerful, integrated development environment from KDE, <b>KDevelop</b>, which will let you program in a lot of languages."),
	' ',
	N("PowerPack also ships with <b>GCC</b>, the leading Linux compiler and <b>GDB</b>, the associated debugger."));