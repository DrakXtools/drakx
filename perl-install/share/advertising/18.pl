#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Enjoy the Wide Range of Applications</b>"), center => 1 ],
	' ',
	N("In the Mandriva Linux menu you will find <b>easy-to-use</b> applications for <b>all of your tasks</b>:"),
	N("	* Create, edit and share office documents with <b>OpenOffice.org</b>."),
	N("	* Manage your personal data with the integrated personal information suites <b>Kontact</b> and <b>Evolution</b>."),
	N("	* Browse the web with <b>Mozilla</b> and <b>Konqueror</b>."),
	N("	* Participate in online chat with <b>Kopete</b>."),
	N("	* Listen to your <b>audio CDs</b> and <b>music files</b>, watch your <b>videos</b>."),
	N("	* Edit and create images with the <b>GIMP</b>."),
	N("	* ..."));
