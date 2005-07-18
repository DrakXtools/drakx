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

struct pci_module_map_full {
	unsigned short	vendor;     /* PCI vendor id */
	unsigned short	device;     /* PCI device id */
	unsigned short	subvendor;  /* PCI subvendor id */
	unsigned short	subdevice;  /* PCI subdevice id */
	const char      *name;      /* PCI human readable name */
	const char      *module;    /* module to load */
};

';

my %t = ( 
    network => 'network/main|gigabit|tokenring|wireless|pcmcia',
    medias  => 'disk/scsi|hardware_raid|sata',
);

foreach my $type (keys %t) {
    my @modules = chomp_(`perl ../../kernel/modules.pl pci_modules4stage1 "$t{$type}"`);

    my (@entries, @entries_full);

    foreach my $k (sort keys %$pci) {
	my $v = $pci->{$k};
	member($v->[0], @modules) or next;
	$k =~ /^(....)(....)(....)(....)/;
	my $values = { vendor => $1, device => $2, subvendor => $3, subdevice => $4, driver => $v->[0], description => $v->[1] };
	if ($values->{subdevice} eq 'ffff' && $values->{subvendor} eq 'ffff') {
	    push @entries, $values;
	} else {
	    push @entries_full, $values;
	}
    }

    print "#ifndef DISABLE_".uc($type)."
struct pci_module_map ${type}_pci_ids[] = {
";
    printf qq|\t{ 0x%s, 0x%s, "%s", "%s" },\n|, $_->{vendor}, $_->{device}, $_->{description}, $_->{driver}
      foreach @entries;
    print "};
unsigned int ${type}_num_ids = sizeof(${type}_pci_ids) / sizeof(struct pci_module_map);
";

    print "
struct pci_module_map_full ${type}_pci_ids_full[] = {
";
    printf qq|\t{ 0x%s, 0x%s, 0x%s, 0x%s, "%s", "%s" },\n|, $_->{vendor}, $_->{device}, $_->{subvendor}, $_->{subdevice}, $_->{description}, $_->{driver}
      foreach @entries_full;
    print "};
unsigned int ${type}_num_ids_full = sizeof(${type}_pci_ids_full) / sizeof(struct pci_module_map_full);

#endif

";
}
