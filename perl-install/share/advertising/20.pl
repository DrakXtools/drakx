#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Development Editors</b>"), center => 1 ],
	' ',
	N("PowerPack will let you choose between those <b>popular editors</b>:"),
	N("	* <b>Emacs</b>: a customizable and real time display editor."),
	N("	* <b>XEmacs</b>: another open source text editor and application development system."),
	N("	* <b>Vim</b>: an advanced text editor with more features than standard Vi."));