#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>PowerPack+, The Linux Solution for Desktops and Servers</b>"), center => 1 ],
	' ',
	N("You are now installing <b>Mandrakelinux PowerPack+</b>."),
	' ',
	N("PowerPack+ is a <b>full-featured Linux solution</b> for small to medium-sized <b>networks</b>. PowerPack+ includes thousands of <b>desktop applications</b> and a comprehensive selection of world-class <b>server applications</b>."));