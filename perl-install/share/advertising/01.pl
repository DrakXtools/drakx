#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>What is Mandrivalinux?</b>"), center => 1 ],
         ' ',
	 N("Welcome to <b>Mandrivalinux</b>!"),
		 ' ',
         N("Mandrivalinux is a <b>Linux distribution</b> that comprises the core of the system, called the <b>operating system</b> (based on the Linux kernel) together with <b>a lot of applications</b> meeting every need you could even think of."),
         ' ',
         N("Mandrivalinux is the most <b>user-friendly</b> Linux distribution today. It is also one of the <b>most widely used</b> Linux distributions worldwide!"));