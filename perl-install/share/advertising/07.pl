#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>PowerPack, The Ultimate Linux Desktop</b>"), center => 1 ],
	' ',
	N("You are now installing <b>Mandrakelinux PowerPack</b>."),
	' ',
	N("PowerPack is Mandrakesoft's <b>premier Linux desktop</b> product. PowerPack includes <b>thousands of applications</b> - everything from the most popular to the most advanced."));