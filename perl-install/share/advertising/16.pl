#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Surf the Internet</b>"), center => 1 ],
	' ',
	N("Discovery will give you access to <b>every Internet resource</b>:"),
	N("	* Browse the <b>Web</b> with Konqueror."),
	N("	* <b>Chat</b> online with your friends using Kopete."),
	N("	* <b>Transfer</b> files with KBear."),
	N("	* ..."));