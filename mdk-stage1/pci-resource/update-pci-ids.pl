#!/usr/bin/perl

use lib "../../perl-install";

use common qw(:common);
require '../../../soft/ldetect-lst/convert/merge2pcitable.pl';

my $drivers = read_pcitable("../../../soft/ldetect-lst/lst/pcitable");


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
    print "#ifndef DISABLE_NETWORK\n" if ($_ eq 'eth');
    print "#ifndef DISABLE_MEDIAS\n" if ($_ eq 'scsi');

    print "
struct pci_module_map ${_}_pci_ids[] = {
";
    my %l;
    foreach (glob("../../kernel*/lib/modules/*/$t{$_}/*.o")) {
	m|([^/]*)\.o$|;
	$l{$1} = 1;
    }
    while (my ($k, $v) = each %$drivers) {
	$l{$v->[0]} or next;
	$k =~ /^(....)(....)/;
	printf qq|\t{0x%s  , 0x%s  , ( "%s" ), ( "%s" )} ,\n|,
	   $1, $2, $v->[1], $v->[0];
    }

print "
};
int ${_}_num_ids=sizeof(${_}_pci_ids)/sizeof(struct pci_module_map);
";

    print "#endif\n";

}
