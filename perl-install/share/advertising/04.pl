#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 10;
$border = 10;  #- for leftish text

# Use <b>text</b> for bold

# @text = ([ N("text to display"), center => 1 ],

@text = ([ N("<b>Join the Community</b>"), center => 1 ],
         ' ',
	 N("Mandrakelinux has one of the <b>biggest communities</b> of users and developers. The role of such a community is very wide, ranging from bug reporting to the development of new applications. The community plays a <b>key role</b> in the Mandrakelinux world."),
		 ' ',
         N("To <b>learn more</b> about our dynamic community, please visit <b>www.mandrakelinux.com</b> or directly <b>www.mandrakelinux.com/en/cookerdevel.php3</b> if you would like to get <b>involved</b> in the development."));