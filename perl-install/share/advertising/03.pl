#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>The GPL</b>"), center => 1 ],
         ' ',
	 N("Most of the software included in the distribution and all of the Mandrivalinux tools are licensed under the <b>General Public License</b>."),
		 ' ',
         N("The GPL is at the heart of the open source model; it grants everyone the <b>freedom</b> to use, study, distribute and improve the software any way they want, provided they make the results available."),
         ' ',
         N("The main benefit of this is that the number of developers is virtually <b>unlimited</b>, resulting in <b>very high quality</b> software."));