#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Groupware Server</b>"), center => 1 ],
	' ',
	N("PowerPack+ will give you access to <b>Kolab</b>, a full-featured <b>groupware server</b> which will, thanks to the client <b>Kontact</b>, allow you to:"),
	N("	* Send and receive your <b>e-mails</b>."),
	N("	* Share your <b>agendas</b> and your <b>address books</b>."),
	N("	* Manage your <b>memos</b> and <b>task lists</b>."));