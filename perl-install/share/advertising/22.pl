#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Development Tools</b>"), center => 1 ],
	' ',
	N("PowerPack gives you the best tools to <b>develop</b> your own applications."),
	' ',
	N("With the powerful integrated development environment <b>KDevelop</b> and the leading Linux compiler <b>GCC</b>, you will be able to create applications in <b>many different languages</b> (C, C++, Java™, Perl, Python, etc.)."));