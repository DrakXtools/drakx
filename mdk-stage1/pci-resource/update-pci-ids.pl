#!/usr/bin/perl

use MDK::Common;

-x "../mar/mar" or die "\t*FAILED* Sorry, need ../mar/mar binary\n";

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

my %t = ( network => [ 'network' ],
	  medias => [ 'hd', 'cdrom' ]
	);
my %sanity_check = 
  arch() =~ /ia64/ ?
  ( network => [ '3c59x', 'eepro100', 'e100', 'tulip', 'via-rhine', 'ne2k-pci', '8139too' ],
    medias => [ 'aic7xxx', 'advansys', 'sym53c8xx', 'initio' ],
  ) :
  ( network => [ '3c59x', 'eepro100', 'e100', 'tulip', 'via-rhine', 'ne2k-pci', '8139too', 'tlan' ],
    medias => [ 'aic7xxx', 'advansys', 'ncr53c8xx', 'sym53c8xx', 'initio' ],
  );

foreach $type (keys %t) {
    print STDERR $type;
    my @modulez;
    foreach $floppy (@{$t{$type}}) {
	foreach $marfile (glob("../../all.modules/*/${floppy}_modules.mar")) {
	    -f $marfile or die "\t*FAILED* Sorry, need $marfile mar file\n";
	    my @modz = `../mar/mar -l $marfile`;
	    if ($marfile !~ /2\.2\.14/) {
		foreach $mandatory (@{$sanity_check{$type}}) {
		    grep(/\t$mandatory\.o/, @modz) or die "\t*FAILED* Sanity check should prove that $mandatory.o be part of $marfile\n"
		}
	    }
	    push @modulez, @modz;
	    print STDERR ".";
	}
    }

    print "#ifndef DISABLE_".uc($type)."
struct pci_module_map ${type}_pci_ids[] = {
";

    while (my ($k, $v) = each %$drivers) {
	grep(/^\t$v->[0]\.o/, @modulez) or next;
	$k =~ /^(....)(....)/;
	printf qq|\t{ 0x%s, 0x%s, "%s", "%s" },\n|,
	  $1, $2, $v->[1], $v->[0];
    }

    print "};
int ${type}_num_ids = sizeof(${type}_pci_ids) / sizeof(struct pci_module_map);
#endif

";

    print STDERR "\n";
}
