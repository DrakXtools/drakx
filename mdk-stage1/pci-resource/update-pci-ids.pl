#!/usr/bin/perl

use strict;
use MDK::Common;

require '/usr/bin/merge2pcitable.pl';
my $pci = read_pcitable("/usr/share/ldetect-lst/pcitable");

print '
#define PCI_REVISION_ID         0x08    /* Revision ID */

struct pci_module_map {
	unsigned short	vendor;     /* PCI vendor id */
	unsigned short	device;     /* PCI device id */
	const char      *name;      /* PCI human readable name */
	const char      *module;    /* module to load */
};

';

my %t = ( 
    network => 'network/main',
    medias  => 'disk/scsi|hardware_raid',
);

foreach my $type (keys %t) {
    my @modules = chomp_(`perl ../../kernel/modules.pl pci_modules4stage1:"$t{$type}"`);

    print "#ifndef DISABLE_".uc($type)."
struct pci_module_map ${type}_pci_ids[] = {
";

    foreach my $k (sort keys %$pci) {
	my $v = $pci->{$k};
	member($v->[0], @modules) or next;
	$k =~ /^(....)(....)/;
	printf qq|\t{ 0x%s, 0x%s, "%s", "%s" },\n|,
	  $1, $2, $v->[1], $v->[0];
    }

    print "};
int ${type}_num_ids = sizeof(${type}_pci_ids) / sizeof(struct pci_module_map);
#endif

";
}
