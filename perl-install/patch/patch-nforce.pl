use install_steps;
use common;

package install_steps;

my $old_afterInstallPackages = \&afterInstallPackages;
undef *afterInstallPackages;
*afterInstallPackages = sub {
    &$old_afterInstallPackages;

    my ($o) = @_;

    #- workaround nforce stuff.
    #
    # modules.pm uses /lib/modules/VERSION/modules*map to know which
    # sound drivers to use : this'll cause i810_audio to override
    # nvaudio since it exports the nvforce audio pci ids
    #
    # the right solution is to :
    #
    # - remove the nforce ids from i810_audio until the oss driver got
    #   fixes implemented in alsa driver for nforce (snd-intel8x0.o)
    #
    # - ask nvidia to declare which pci ids they use and export them
    #   for depmod :
    #   MODULE_DEVICE_TABLE (pci, <name_of_the struct pci_device_id variable>);

    foreach (keys %{$o->{packages}{provides}{kernel}}) {
	my $p = $o->{packages}{depslist}[$_];
	my ($ext, $version, $release) = $p->name =~ /^kernel-([^\d\-]*)-?([^\-]*)\.([^\-\.]*)$/ or next;
	-s "$o->{prefix}/lib/modules/$version-$release$ext/kernel/drivers/sound/nvaudio.o.gz" and
	  unlink "$o->{prefix}/lib/modules/$version-$release$ext/kernel/drivers/sound/i810_audio.o.gz";
    }

};
