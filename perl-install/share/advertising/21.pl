#!/usr/bin/perl

use utf8;

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Development Languages</b>"), center => 1 ],
	' ',
	N("With all these <b>powerful tools</b>, you will be able to write applications in <b>dozens of programming languages</b>:"),
	N("	* The famous <b>C language</b>."),
	N("	* Object oriented languages:"),
	N("		* <b>C++</b>"),
	N("		* <b>Java™</b>"),
	N("	* Scripting languages:"),
	N("		* <b>Perl</b>"),
	N("		* <b>Python</b>"),
	N("	* And many more."));
