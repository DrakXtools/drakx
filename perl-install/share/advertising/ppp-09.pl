#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakestore</b>"), center => 1 ],
	' ',
	N("Find all Mandrakesoft products and services at <b>Mandrakestore</b> -- our full service e-commerce platform."),
        ' ',
	N("Stop by today at <b>www.mandrakestore.com</b>")); 
