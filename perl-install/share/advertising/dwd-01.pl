#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Congratulations for choosing Mandrakelinux!</b>"), center => 1 ],
         ' ',
		 N("Welcome to the Open Source world!"),
		 ' ',
         N("Mandrakelinux is committed to the Open Source Model and fully respects the General Public License. This new release is the result of collaboration between Mandrakesoft's team of developers and the worldwide community of Mandrakelinux contributors."),
         ' ',
         N("We would like to thank everyone who participated in the development of this latest release."));
