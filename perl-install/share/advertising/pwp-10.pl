#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Do you require assistance?</b>"), center => 1 ],
         ' ',
         N("<b>Mandrakeexpert</b> is the primary source for technical support."),
	 ' ',
	 N("If you have Linux questions, subscribe to Mandrakeexpert at <b>www.mandrakeexpert.com</b>")); 
