#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakeclub</b>"), center => 1 ],
	' ',
	N("<b>Mandrakeclub</b> is the <b>perfect companion</b> to your Mandrakelinux product.."),
	' ',
	N("Take advantage of <b>valuable benefits</b> by joining Mandrakeclub, such as:"),
	N("	* <b>Special discounts</b> on products and services of our online store <b>store.mandrakesoft.com</b>."),
	N("	* Access to <b>commercial applications</b> (for example to NVIDIA® or ATI™ drivers)."),
	N("	* Participation in Mandrakelinux <b>user forums</b>."),
	N("	* <b>Early and privileged access</b>, before public release, to Mandrakelinux <b>ISO images</b>."),
	N("	* And many more."));