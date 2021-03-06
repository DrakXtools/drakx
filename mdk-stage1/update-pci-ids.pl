#!/usr/bin/perl

use lib '../kernel';
use strict;
use MDK::Common;


my %t = ( 
    network => 'network/main|gigabit|pcmcia|virtual|wireless',
    medias_ide  => 'disk/ide',
    medias_other => 'disk/scsi|hardware_raid|sata|virtual bus/firewire',
);

foreach my $type (keys %t) {
    my @modules = chomp_(`perl ../kernel/modules.pl pci_modules4stage1 "$t{$type}"`)
	or die "unable to get PCI modules";

    print "#ifndef DISABLE_".uc($type)."
const char* ${type}_pci_modules[] = {
";
    printf qq|\t"%s",\n|, $_ foreach @modules;
    print "};
unsigned int ${type}_pci_modules_len = sizeof(${type}_pci_modules) / sizeof(const char *);
#endif

";
}
