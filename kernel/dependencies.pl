use strict;

use MDK::Common;
use list_modules;

my $depfile = shift @ARGV;
load_dependencies($depfile);
print STDERR "Loaded dependencies from $depfile\n";

my @modules = uniq(map { dependencies_closure($_) } @ARGV);
print join " ", map { "$_.o" } @modules;
print "\n";
