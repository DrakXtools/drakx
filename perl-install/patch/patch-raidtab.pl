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
