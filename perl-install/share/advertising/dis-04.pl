#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>OpenOffice.org</b>: The complete Linux office suite."), center => 1 ],
        ' ',
	N("<b>WRITER</b> is a powerful word processor for creating all types of text documents. Documents may include images, diagrams and tables."),
	N("<b>CALC</b> is a feature-packed spreadsheet which enables you to compute, analyze and manage all of your data."),
	N("<b>IMPRESS</b> is the fastest, most powerful way to create effective multimedia presentations."),
	N("<b>DRAW</b> will produce everything from simple diagrams to dynamic 3D illustrations.")); 
