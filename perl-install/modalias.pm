package modalias;

# TODO:
# - be faster (Elapsed time: lspcidrake.pl ~ 0.28s instead of 0.12s for old lspcidrake

use strict;
use MDK::Common;
use c;

my @config_groups = (
    [
	"/lib/module-init-tools/modprobe.default",
	"/etc/modprobe.conf",
	"/etc/modprobe.d",
    ],
    [
        "/lib/module-init-tools/ldetect-lst-modules.alias",
    ],
    [
        "/lib/modules/" . c::kernel_version() . "/modules.alias",
    ],
);
my @classes = qw(ide ieee1394 input pci pcmcia pnp serio usb);
my @alias_groups;

my $alias_re = qr/^\s*alias\s+(([^:]+):\S+)\s+(\S+)$/;

sub alias_to_ids {
    my ($alias) = @_;
    my ($vendor, $device);
    # returns (vendor, device)
    if (($vendor, $device) = $alias =~ /:v([0-9A-F]{4})[dp]([0-9A-F]{4})/) {
        return ($vendor, $device);
    } elsif (($vendor, $device) = $alias =~ /:v0{4}([0-9A-F]{4})[dp]0{4}([0-9A-F]{4})/) {
        return ($vendor, $device);
    }
}

sub parse_path {
    my ($group, $path) = @_;
    if (-d $path) {
        parse_path($group, "$path/$_") foreach all($path);
    } elsif (-f $path) {
        foreach (cat_($path)) {
            if (my ($alias, $class, $module) = $_ =~ $alias_re) {
                my ($vendor, $device) = alias_to_ids($alias);
                if (member($class, @classes)) {
                    if ($vendor) {
                        $group->{$class} ||= {};
                        $group->{$class}{$vendor} ||= {};
                        $group->{$class}{$vendor}{$device} ||= [];
                        push @{$group->{$class}{$vendor}{$device}}, $alias, $module;
                    } else {
                        push @{$group->{$class}{other}}, $alias, $module;
                    }
                }
            }
        }
    }
}

sub parse_file_modules {
    my ($path) = @_;
    my %modules;
    foreach (cat_($path)) {
        if (my ($alias, undef, $module) = $_ =~ $alias_re) {
            push @{$modules{$module}}, $alias;
        }
    }
    \%modules;
}

sub get_alias_groups() {
    @alias_groups = map {
        my $group = {};
        parse_path($group, $_) foreach @$_;
        $group;
    } @config_groups unless @alias_groups;
    @alias_groups;
}

sub get_modules {
    my ($modalias) = @_;
    my ($class) = $modalias =~ /^([^:]+):\S+$/;
    my ($vendor, $device) = alias_to_ids($modalias);
    $class && member($class, @classes) or return;

    require File::FnMatch;
    foreach my $group (get_alias_groups()) {
        my @aliases;
        foreach my $subgroup ($group->{$class}{$vendor}{$device}, $group->{$class}{other}) {
            foreach (group_by2(@$subgroup)) {
                File::FnMatch::fnmatch($_->[0], $modalias) and push @aliases, $_->[1];
            }
        }
        return uniq(@aliases) if @aliases;
    }
}

1;
