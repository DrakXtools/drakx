#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Servers</b>"), center => 1 ],
	' ',
	N("Empower your business network with <b>premier server solutions</b> including:"),
	N("	* <b>Samba</b>: File and print services for Microsoft® Windows® clients."),
	N("	* <b>Apache</b>: The most widely used web server."),
	N("	* <b>MySQL</b> and <b>PostgreSQL</b>: The world's most popular open source databases."),
	N("	* <b>CVS</b>: Concurrent Versions System, the dominant open source network-transparent version control system."),
	N("	* <b>ProFTPD</b>: The highly configurable GPL-licensed FTP server software."),
	N("	* <b>Postfix</b> and <b>Sendmail</b>: The popular and powerful mail servers."));