#!/usr/bin/perl

use lib "../../perl-install";
use common qw(:common);
use pci_probing::pcitable;

print '
#define PCI_REVISION_ID         0x08    /* Revision ID */

struct pci_module_map {
	unsigned short	vendor;     /* PCI vendor id */
	unsigned short	device;     /* PCI device id */
	const char      *name;      /* PCI human readable name */
	const char      *module;    /* module to load */
};

';

my %t = (scsi => 'scsi', eth => 'net');

foreach (keys %t) {
    print "
struct pci_module_map ${_}_pci_ids[] = {
";
    my %l;
    foreach (glob("../../kernel*/lib/modules/*/$t{$_}/*.o")) {
	m|([^/]*)\.o$|;
	$l{$1} = 1;
    }
    while (my ($k, $v) = each %pci_probing::pcitable::ids) {
	$l{$v->[1]} or next;
	printf qq|\t{0x%04x  , 0x%04x  , ( "%s" ), ( "%s" )} ,\n|,
	  $k / 0x10000, $k % 0x10000, $v->[0], $v->[1];
    }

print "
};
int ${_}_num_ids=sizeof(${_}_pci_ids)/sizeof(struct pci_module_map);
"

}
