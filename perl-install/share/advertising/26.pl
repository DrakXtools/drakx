#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>The Open Source Model</b>"), center => 1 ],
	' ',
	N("Like all computer programming, open source software <b>requires time and people</b> for development. In order to respect the open source philosophy, Mandriva sells added value products and services to <b>keep improving Mandrivalinux</b>. If you want to <b>support the open source philosophy</b> and the development of Mandrivalinux, <b>please</b> consider buying one of our products or services!"));