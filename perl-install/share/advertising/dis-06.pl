#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Surf The Internet</b>"), center => 1 ],
        ' ',
	N("You can also:"),
	N("	- browse the Web"),
	N("	- chat"),
	N("	- organize a video-conference"),
	N("	- create your own Web site"),
	N("	- ...")); 
