#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>What is Mandrakelinux?</b>"), center => 1 ],
        ' ',
	N("Mandrakelinux is an Open Source distribution created with thousands of the choicest applications from the Free Software world. Mandrakelinux is one of the most widely used Linux distributions worldwide!"),
        ' ',
        N("Mandrakelinux includes the famous graphical desktops KDE and GNOME, plus the latest versions of the most popular Open Source applications.")); 
