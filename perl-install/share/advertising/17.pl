#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Enjoy our Multimedia Features</b>"), center => 1 ],
	' ',
	N("Discovery will also make <b>multimedia</b> very easy for you:"),
	N("	* Watch your favorite <b>videos</b> with Kaffeine."),
	N("	* Listen to your <b>music files</b> with amaroK."),
	N("	* Edit and create <b>images</b> with the GIMP."),
	N("	* ..."));