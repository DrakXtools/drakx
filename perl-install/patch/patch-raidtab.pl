use detect_devices;
package detect_devices;
log::l("PATCHING");

*raidAutoStartRaidtab = sub {
    my (@parts) = @_;
    log::l("patched raidAutoStartRaidtab");
    $::isInstall or return;
    require raid;
    #- faking a raidtab, it seems to be working :-)))
    #- (choosing any inactive md)
    raid::inactivate_all();
    foreach (@parts) {
	my ($nb) = grep { !raid::is_active("md$_") } 0..7;
	output("/tmp/raidtab", "raiddev /dev/md$nb\n  device " . devices::make($_->{device}) . "\n");
	run_program::run('raidstart', '-c', "/tmp/raidtab", devices::make("md$nb"));
    }
    unlink "/tmp/raidtab";
};

use raid;
package raid;

*prepare_prefixed = sub {
    my ($raids, $prefix) = @_;

    log::l("patched prepare_prefixed");

    $raids or return;

    &write($raids, "/etc/raidtab") if ! -e "/etc/raidtab";
    
    eval { cp_af("/etc/raidtab", "$prefix/etc/raidtab") };
    foreach (grep { $_ } @$raids) {
	devices::make("$prefix/dev/$_->{device}") foreach @{$_->{disks}};
    }
};
