use diagnostics;
use strict;

sub insmod {

    @_ or die "usage: insmod <module>.o [params]\n";

    my $file = shift;
    my $tmpname;

    unless (-r $file) {
	local *F;
	open F, "/modules/modules.cgz" or die "error opening /modules/modules.cgz";

	$tmpname = "/tmp/" . basename($file);

	installCpioFile(\*F, $file, $tmpname, 0) or die "error extracting file";
    }

    my $rc = insmod_main($tmpname || $file, @_);

    unlink($tmpname);

    return $rc;
}
sub modprobe { &insmod }
