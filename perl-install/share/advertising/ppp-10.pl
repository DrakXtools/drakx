#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("Become a <b>Mandrakeclub</b> member!"), center => 1 ],
        ' ',
	N("Take advantage of valuable benefits, products and services by joining Mandrakeclub, such as:"),
	' ',
	N("	- Full access to commercial applications"),
	N("	- Special download mirror list exclusively for Mandrakeclub Members"),
	N("	- Voting for software to put in Mandrakelinux"),
	N("	- Special discounts for products and services at Mandrakestore"),
	N("	- Plus much more"),
	' ',
	N("For more information, please visit <b>www.mandrakeclub.com</b>")); 
