#!/usr/bin/perl

use strict;
use lib qw(/usr/lib/libDrakX);

use common;
use harddrake::sound;
use list_modules;


my @listed_modules = @{$list_modules::l{multimedia}{sound}};
my @drivers = (keys %harddrake::sound::oss2alsa, keys %harddrake::sound::alsa2oss);
my @alternatives = uniq map { @{$_} } values %harddrake::sound::oss2alsa, values %harddrake::sound::alsa2oss;

# check harddrake::sound's data structures're coherent
print "unknown alternative drivers : [", join(', ', difference2(\@alternatives, \@drivers)), "]\n";

# check that list_modules and harddrake::sound are synced
print "non real sound modules (submodules, tv, usb, ...) : [", join(', ', difference2(\@drivers, \@listed_modules)), "]\n";
print "forgotten sound modules : [", join(', ', difference2(\@listed_modules, \@drivers)), "]\n";
