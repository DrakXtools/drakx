#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Join the Mandrake Linux community!</b>"), center => 1 ],
        ' ',
	N("If you would like to get involved, please subscribe to the \"Cooker\" mailing list by visiting mandrake-linux.com/cooker"),
        ' ',
        N("To learn more about our dynamic community, please visit <b>www.mandrake-linux.com</b>!"));
