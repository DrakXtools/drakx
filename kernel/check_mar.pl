#!/usr/bin/perl

use MDK::Common;

my $mar = '../mdk-stage1/mar/mar';
-x $mar or die "ERROR: Sorry, need $mar binary\n";

my %sanity_check = (
    hd => [ 
	qw(aic7xxx sym53c8xx initio), 
	if_(arch() !~ /ppc/, 'advansys'),
    ],
    network => [ 
	qw(3c59x eepro100 tulip via-rhine ne2k-pci 8139too), 
	if_(arch() !~ /ppc/, 'e100'), 
	if_(arch() !~ /ppc|ia64/, 'tlan'),
    ],
);

my $main_version = chomp_(cat_("all.kernels/.main"));

foreach (keys %sanity_check) {
    my $marfile = "all.modules/$main_version/${_}_modules.mar";
    -e $mar or die "ERROR: missing $marfile\n";

    my @l = map { /(\S+)\.o/ } `$mar -l $marfile`;
    my @pbs = difference2($sanity_check{$_}, \@l);

    @pbs and die "ERROR: sanity check should prove that " . join(" ", @pbs) . "be part of $marfile\n";
}
