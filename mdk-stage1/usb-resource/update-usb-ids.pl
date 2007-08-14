#!/usr/bin/perl

use strict;
use MDK::Common;

my @modules = chomp_(`perl ../../kernel/modules.pl pci_modules4stage1 "bus/usb"`)
  or die "unable to get USB controller modules";
print "char *usb_controller_modules[] = {
";
printf qq|\t"%s",\n|, $_ foreach @modules;
print "};
unsigned int usb_controller_modules_len = sizeof(usb_controller_modules) / sizeof(char *);
";

@modules = chomp_(`perl ../../kernel/modules.pl pci_modules4stage1 "network/usb disk/usb"`)
  or die "unable to get USB modules";

print "char *usb_modules[] = {
";
printf qq|\t"%s",\n|, $_ foreach @modules;
print "};
unsigned int usb_modules_len = sizeof(usb_modules) / sizeof(char *);
";
