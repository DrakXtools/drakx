#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Surf The Internet</b>"), center => 1 ],
        ' ',
	N("Discover the new integrated personal information suite KDE Kontact."),
	' ',
	N("More than just a full-featured email client, <b>Kontact</b> also includes an address book, a calendar and scheduling program, plus a tool for taking notes!")); 
