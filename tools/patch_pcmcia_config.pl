#!/usr/bin/perl

use MDK::Common;

listlength(@ARGV) == 2 or die "usage: $0 /path/to/etc/pcmcia/config /path/to/modules.dep\n";

my ($pcmcia_config, $modules_dep) = @ARGV;


my @ignore_modules_in_deps = qw(pcmcia_core ds);

my @conf_contents = cat_($pcmcia_config);
die "uhm, problem, <$pcmcia_config> seems short in lines\n" if listlength(@conf_contents) < 10;

foreach (cat_($modules_dep)) {
    /^(\S+): (.*)/ and $deps{$1} = [ split ' ', $2 ] or die "could not understand `$_' in <$modules_dep>\n";
}

foreach my $confline (@conf_contents) {
    $confline =~ /class.*\s+module\s+(.*)/ or next;
    my @modules = map { /"([^"]+)"(.*)/ && [ $1, $2 ] } split ',', $1;
    $_->[0] =~ s|.*/([^/]+)$|$1|g foreach @modules;  #- remove directories since we don't support that during install
    my @deps = grep { !member($_, @ignore_modules_in_deps, map { $_->[0] } @modules) } map { @{$deps{$_->[0]}} } @modules;
    my $new_modz = join ', ', (map { "\"$_\"" } @deps), (map { "\"$_->[0]\"$_->[1]" } @modules);
    $confline =~ s/(class.*\s+module\s+).*/$1$new_modz/;
}

output($pcmcia_config, @conf_contents);
