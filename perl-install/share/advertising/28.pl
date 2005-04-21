#!/usr/bin/perl

use utf8;

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandriva Club</b>"), center => 1 ],
	' ',
	N("<b>Mandriva Club</b> is the <b>perfect companion</b> to your Mandrivalinux product.."),
	' ',
	N("Take advantage of <b>valuable benefits</b> by joining Mandriva Club, such as:"),
	N("	* <b>Special discounts</b> on products and services of our online store <b>store.mandrakesoft.com</b>."),
	N("	* Access to <b>commercial applications</b> (for example to NVIDIA® or ATI™ drivers)."),
	N("	* Participation in Mandrivalinux <b>user forums</b>."),
	N("	* <b>Early and privileged access</b>, before public release, to Mandrivalinux <b>ISO images</b>."),
	N("	* And many more."));
