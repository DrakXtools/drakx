use bootloader;
package bootloader;
log::l("PATCHING: fixing 9.1 aes.o missing in initrd for / on loopback");

*mkinitrd = sub {
    my ($kernelVersion, $initrdImage) = @_;

    my $loop_boot = loopback::prepare_boot();

    modules::load('loop');
    if (!run_program::rooted($::prefix, "mkinitrd", "--with=aes", "-v", "-f", $initrdImage, "--ifneeded", $kernelVersion)) {
	unlink("$::prefix/$initrdImage");
	die "mkinitrd failed";
    }
    loopback::save_boot($loop_boot);

    -e "$::prefix/$initrdImage";
};
