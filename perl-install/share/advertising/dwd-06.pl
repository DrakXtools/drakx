#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>MandrakeStore</b>"), center => 1 ],
         ' ',
         N("Find all Mandrakesoft products at <b>MandrakeStore</b> -- our full service e-commerce platform."),
         ' ',
         N("Find out also support incidents if you have any problems, from standard to professional support, from 1 to 50 incidents, take the one which meets perfectly your needs!"),
	' ',
	 N("Stop by today at <b>www.mandrakestore.com</b>")); 
