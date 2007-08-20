#!/usr/bin/perl

use lib '../kernel';
use strict;
use MDK::Common;

my @aliases;
my ($main) = `ls -t /lib/modules/*/modules.alias`;
foreach (cat_(chomp_($main))) {
    push @aliases, [ $1, $2 ] if /^alias\s+(pcmcia:\S+)\s+(\S+)$/; #- modalias, module
}
@aliases or die "unable to get PCMCIA aliases";

print '
struct pcmcia_alias {
	const char      *modalias;
	const char      *module;
};

';

my %t = ( 
    network => 'network/pcmcia',
    medias  => 'disk/pcmcia',
);

foreach my $type (keys %t) {
    my @modules = chomp_(`perl ../../kernel/modules.pl pci_modules4stage1 "$t{$type}"`)
	or die "unable to get PCMCIA modules";

    print "#ifndef DISABLE_".uc($type)."
struct pcmcia_alias ${type}_pcmcia_ids[] = {
";
    print qq|\t{ "$_->[0]", "$_->[1]" },\n| foreach grep { member($_->[1], @modules) } @aliases;
    print "};
unsigned int ${type}_pcmcia_num_ids = sizeof(${type}_pcmcia_ids) / sizeof(struct pcmcia_alias);

#endif

";

}
