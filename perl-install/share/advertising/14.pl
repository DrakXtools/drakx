#!/usr/bin/perl

use utf8;

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>OpenOffice.org</b>"), center => 1 ],
	' ',
	N("With Discovery, you will discover <b>OpenOffice.org</b>."),
	' ',
	N("It is a <b>full-featured office suite</b> that includes word processor, spreadsheet, presentation and drawing applications."),
	' ',
	N("OpenOffice.org can read and write most types of <b>Microsoft® Office</b> documents such as Word, Excel and PowerPoint® files."));
