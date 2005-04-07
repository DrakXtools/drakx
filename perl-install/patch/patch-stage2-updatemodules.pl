# put this file in install/patch.pl, and boot with auto_install=install/patch.pl
# put modules in install/modules and list them below

my @modules = map { "install/modules/$_.ko" } 'tg3';

foreach my $remote (@modules) {
    my $local = '/tmp/' . basename($remote);
    
    install_any::getAndSaveFile($remote, $local);

    run_program::run(["/usr/bin/insmod_", "insmod"], "-f", $local);
}
