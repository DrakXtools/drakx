#!/usr/bin/perl

use lib "../../perl-install";

use common qw(:common);
require '/usr/bin/merge2pcitable.pl';

my $drivers = read_pcitable("/usr/share/ldetect-lst/pcitable");


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

if (-x "../mar/mar" && -f "../../modules/network_modules.mar" && -f "../../modules/hd_modules.mar") {
    $modulez{'eth'} = [ `../mar/mar -l ../../modules/network_modules.mar` ];
    $modulez{'scsi'} = [ `../mar/mar -l ../../modules/hd_modules.mar` ];
    $check_marfiles = 1;
}


foreach $type (keys %t) {
    print "#ifndef DISABLE_NETWORK\n" if ($type eq 'eth');
    print "#ifndef DISABLE_MEDIAS\n" if ($type eq 'scsi');

    print "
struct pci_module_map ${type}_pci_ids[] = {
";
    my %l;
    foreach (glob("../../kernel/lib/modules/*/$t{$type}/*.o"), glob("../../kernel/lib/modules/*/kernel/drivers/$t{$type}/{*/,}*.o")) {
	m|([^/]*)\.o$|;
	$l{$1} = 1;
    }
    my %absent;
    while (my ($k, $v) = each %$drivers) {
	$l{$v->[0]} or next;
	$k =~ /^(....)(....)/;
	printf qq|\t{0x%s  , 0x%s  , ( "%s" ), ( "%s" )} ,\n|,
	   $1, $2, $v->[1], $v->[0];
	if (defined($check_marfiles)) {
	    ($absent{$v->[0]} = 1) if (!grep(/^$v->[0]\.o\s/, @{$modulez{$type}}));
	}
    }

    if (%absent) { print STDERR "\tmissing for $type: "; foreach (keys %absent) { print STDERR "$_ " } print STDERR "\n"; };

print "
};
int ${type}_num_ids=sizeof(${type}_pci_ids)/sizeof(struct pci_module_map);
";

    print "#endif\n";

}
