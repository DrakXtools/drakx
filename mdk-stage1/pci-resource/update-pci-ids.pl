#!/usr/bin/perl

use MDK::Common;
use lib qw(../../perl-install);

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
	  medias => [ 'hd', 'cdrom', 'other' ]
	);
my %sanity_check = 
  arch() =~ /ia64/ ?
  ( network => [ '3c59x', 'eepro100', 'e100', 'tulip', 'via-rhine', 'ne2k-pci', '8139too' ],
    medias => [ 'aic7xxx', 'advansys', 'sym53c8xx', 'initio' ],
  ) :
  arch() =~ /ppc/ ?
  ( network => [ '3c59x', 'eepro100', 'tulip', 'via-rhine', 'ne2k-pci', '8139too' ],
    medias => [ 'aic7xxx', 'sym53c8xx', 'initio' ],
  ) :
  ( network => [ '3c59x', 'eepro100', 'e100', 'tulip', 'via-rhine', 'ne2k-pci', '8139too', 'tlan' ],
    medias => [ 'aic7xxx', 'advansys', 'sym53c8xx', 'initio' ],
  );

foreach $type (keys %t) {
    print STDERR "$type (checks: ", join('/', @{$sanity_check{$type}}), ") ";
    foreach $floppy (@{$t{$type}}) {
	foreach $marfile (glob("../../all.modules/*/${floppy}_modules.mar")) {
	    -f $marfile or die "\t*FAILED* Sorry, need $marfile mar file\n";
	    my @modz = `../mar/mar -l $marfile`;
	    if ($marfile !~ /(2\.2\.14)|(other)/) {
		foreach $mandatory (@{$sanity_check{$type}}) {
		    grep(/\t$mandatory\.o/, @modz) or die "\t*FAILED* Sanity check should prove that $mandatory.o be part of $marfile\n"
		}
	    }
	    print STDERR ".";
	}
    }

    my %names_in_stage2 = ( network => [ 'net' ], medias => [ 'scsi', 'disk', 'big' ] );
    require modules;
    my @modulez;
    push @modulez, modules::module_of_type__4update_kernel($_) foreach @{$names_in_stage2{$type}};

    print "#ifndef DISABLE_".uc($type)."
struct pci_module_map ${type}_pci_ids[] = {
";

    foreach my $k (sort keys %$drivers) {
	$v = $drivers->{$k};
	member($v->[0], @modulez) or next;
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
