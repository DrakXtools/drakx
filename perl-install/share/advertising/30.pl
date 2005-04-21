#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandriva Expert</b>"), center => 1 ],
	' ',
	N("Do you require <b>assistance?</b> Meet Mandriva's technical experts on <b>our technical support platform</b> www.mandrakeexpert.com."),
	' ',
	N("Thanks to the help of <b>qualified Mandrivalinux experts</b>, you will save a lot of time."),
	' ',
	N("For any question related to Mandrivalinux, you have the possibility to purchase support incidents at <b>store.mandrakesoft.com</b>."));