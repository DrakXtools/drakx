#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>The KDE Choice</b>"), center => 1 ],
	' ',
	N("With your Discovery, you will be introduced to <b>KDE</b>, the most advanced and user-friendly <b>graphical desktop environment</b> available."),
	' ',
	N("KDE will make your <b>first steps</b> with Linux so <b>easy</b> that you won't ever think of running another operating system!"),
	' ',
	N("KDE also includes a lot of <b>well integrated applications</b> such as Konqueror, the web browser and Kontact, the personal information manager."));