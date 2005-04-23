#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Discovery, Your First Linux Desktop</b>"), center => 1 ],
         ' ',
	 N("You are now installing <b>Mandriva Linux Discovery</b>."),
		 ' ',
         N("Discovery is the <b>easiest</b> and most <b>user-friendly</b> Linux distribution. It includes a hand-picked selection of <b>premium software</b> for office, multimedia and Internet activities. Its menu is task-oriented, with a single application per task."));
