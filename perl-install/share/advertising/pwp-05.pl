#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Development tools</b>"), center => 1 ],
        ' ',
	N("PowerPack includes everything needed for developing and creating your own software, including:"),
	N("	- <b>Kdevelop:</b> a full featured, easy to use Integrated Development Environment for C++ programming"),
	N("	- <b>GCC:</b> the GNU Compiler Collection"),
	N("	- <b>GDB:</b> the GNU Project debugger")); 
