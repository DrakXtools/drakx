#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Discover the full-featured groupware solution!</b>"), center => 1 ],
        ' ',
		N("It includes both server and client features for:"),
		N("	- Sending and receiving emails"),
		N("	- Calendar, Task List, Memos, Contacts, Meeting Request (sending and receiving), Task Requests (sending and receiving)"),
		N("	- Address Book (server and client)"),
		N("	- Plus much more")); 
