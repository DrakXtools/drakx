#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Online Store</b>"), center => 1 ],
	' ',
	N("To learn more about Mandriva products and services, you can visit our <b>e-commerce platform</b>."),
	' ',
	N("There you can find all our products, services and third-party products."),
	' ',
	N("This platform has just been <b>redesigned</b> to improve its efficiency and usability."),
	' ',
	[ N("Stop by today at <b>store.mandrakesoft.com</b>!"), center => 1 ]);