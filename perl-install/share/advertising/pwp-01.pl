#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Congratulations for choosing Mandrakelinux!</b>"), center => 1 ],
        ' ',
	N("Welcome to the Open Source world!"),
        ' ',
	N("Your new Mandrakelinux distribution is the result of collaborative efforts between Mandrakesoft developers and Mandrakelinux contributors throughout the world."),
	' ',
	N("We would like to thank everyone who participated in the development of our latest release.")); 
