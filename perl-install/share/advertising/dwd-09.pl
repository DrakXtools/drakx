#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Note</b>"), center => 1 ],
        ' ',
		N("This is the Mandrake Linux \"Download version\"."),
		' ',
		N("The free download version does not include commercial software, and therefore may not work with certain proprietary network cards and video cards such as NVIDA(r) nForce. To avoid possible compatibiity issues with these devices, we recommend the purchase of one of our retail products that includes commercial drivers and additional software.")); 
