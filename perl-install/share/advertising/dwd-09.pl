#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold
#
# And text MUST BE in ASCII or UTF-8 *ONLY*
# Don't use iso-8859-1 or any other encoding, it breaks everything! 

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Note</b>"), center => 1 ],
        ' ',
	N("This is the Mandrakelinux <b>Download version</b>."),
	' ',
	N("The free download version does not include commercial software, and therefore may not work with certain modems (such as some ADSL and RTC) and video cards (such as ATI® and NVIDIA®).")); 
