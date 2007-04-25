#!/usr/bin/perl

use strict;
use MDK::Common;

require '/usr/bin/merge2pcitable.pl';
my $pci = read_pcitable("/usr/share/ldetect-lst/pcitable");
my $usb = read_pcitable("/usr/share/ldetect-lst/usbtable");

print '


struct usb_module_map {
	unsigned short	vendor;     /* vendor */
	unsigned short	id;         /* device */
	const char      *name;      /* human readable name */
	const char      *module;    /* module to load */
};

';

print "struct pci_module_map usb_pci_ids[] = {

";

foreach my $k (sort keys %$pci) {
    my $v = $pci->{$k};
    $v->[0] =~ /^usb-|^ehci-hcd|^ohci1394/ or next;
    $k =~ /^(....)(....)/;
    printf qq|\t{ 0x%s, 0x%s, "", "%s" },\n|,
      $1, $2, $v->[0];
}

print "};
int usb_num_ids=sizeof(usb_pci_ids)/sizeof(struct pci_module_map);
";

print "struct usb_module_map usb_usb_ids[] = {
";

my @modules = chomp_(`perl ../../kernel/modules.pl pci_modules4stage1 "network/usb disk/usb"`)
or die "unable to get USB modules";

    foreach my $k (sort keys %$usb) {
	my $v = $usb->{$k};
	member($v->[0], @modules) or next;
	$k =~ /^(....)(....)/;
	printf qq|\t{ 0x%s, 0x%s, "%s", "%s" },\n|,
	  $1, $2, $v->[1], $v->[0];
    }

    print "};
int usb_usb_num_ids=sizeof(usb_usb_ids)/sizeof(struct usb_module_map);
";
