#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Choose your Favorite Desktop Environment</b>"), center => 1 ],
	' ',
	N("With PowerPack, you will have the choice of the <b>graphical desktop environment</b>. Mandrakesoft has chosen <b>KDE</b> as the default one."),
	' ',
	N("KDE is one of the <b>most advanced</b> and <b>user-friendly</b> graphical desktop environment available. It includes a lot of integrated applications."),
	' ',
	N("But we advise you to try all available ones (including <b>GNOME</b>, <b>IceWM</b>, etc.) and pick your favorite."));