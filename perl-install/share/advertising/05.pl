#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Download Version</b>"), center => 1 ],
         ' ',
	 N("You are now installing <b>Mandrakelinux Download</b>. This is the free version that Mandrakesoft wants to keep <b>available to everyone</b>."),
		 ' ',
         N("The Download version <b>cannot include</b> all the software that is not open source. Therefore, you won't find in the Download version:"),
	 N("	* <b>Proprietary drivers</b> (such as drivers for NVIDIA®, ATI™, etc.)."),
	 N("	* <b>Proprietary software</b> (such as Acrobat® Reader®, RealPlayer®, Flash™, etc.)."),
	 ' ',
	 N("You won't have access to the <b>services included</b> in the other Mandrakesoft products either."));
