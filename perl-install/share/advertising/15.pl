#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Kontact</b>"), center => 1 ],
	' ',
	N("Discovery includes <b>Kontact</b>, the new KDE <b>groupware solution</b>."),
	' ',
	N("More than just a full-featured <b>e-mail client</b>, Kontact also includes an <b>address book</b>, a <b>calendar</b>, plus a tool for taking <b>notes</b>!"),
	' ',
	N("It is the easiest way to communicate with your contacts and to organize your time."));