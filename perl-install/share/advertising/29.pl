#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Mandrakeonline</b>"), center => 1 ],
	' ',
	N("<b>Mandrakeonline</b> is a new premium service that Mandrakesoft is proud to offer its customers!"),
	' ',
	N("Mandrakeonline provides a wide range of valuable services for <b>easily updating</b> your Mandrakelinux systems:"),
	N("	* <b>Perfect</b> system security (automated software updates)."),
	N("	* <b>Notification</b> of updates (by e-mail or by an applet on the desktop)."),
	N("	* Flexible <b>scheduled</b> updates."),
	N("	* Management of <b>all your Mandrakelinux systems</b> with one account."));