#!/usr/bin/perl

$width = 556;
$height = 303;

$y_start = 80;
$border = 10;  #- for leftish text

@text = ([ N("Congratulations for choosing <b>Mandrake Linux</b>!"), center => 1 ],
         ' ',
         N("Mandrake Linux is committed to the Open Source Model and fully respects the <b>General Public License</b>. This new release is the result of collaboration between MandrakeSoft's team of developers and the worldwide community of Mandrake Linux <b>contributors</b>."),
         ' ',
         [ N("We would like to thank everyone who participated in the development of this latest release."), center => 1 ]);
