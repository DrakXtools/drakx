#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Choose your graphical Desktop environment!</b>"), center => 1 ],
        ' ',
	N("When you log into your Mandrakelinux system for the first time, you can choose between several popular graphical desktops environments, including: KDE, GNOME, WindowMaker, IceWM, and others."));
