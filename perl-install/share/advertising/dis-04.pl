#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>OpenOffice.org</b>: The complete Linux office suite."), center => 1 ],
        ' ',
	N("WRITER is a powerful word processor for creating all types of text documents. Documents may include images, diagrams and tables."),
	N("CALC is a feature-packed spreadsheet which enables you to compute, analyze and manage all of your data."),
	N("IMPRESS is the fastest, most powerful way to create effective multimedia presentations."),
	N("DRAW will produce everything from simple diagrams to dynamic 3D illustrations.")); 
