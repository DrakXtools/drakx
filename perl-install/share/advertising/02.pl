#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Open Source</b>"), center => 1 ],
         ' ',
	 N("Welcome to the <b>world of open source</b>!"),
		 ' ',
         N("Mandriva Linux is committed to the open source model. This means that this new release is the result of <b>collaboration</b> between <b>Mandriva's team of developers</b> and the <b>worldwide community</b> of Mandriva Linux contributors."),
         ' ',
         N("We would like to <b>thank</b> everyone who participated in the development of this latest release."));
