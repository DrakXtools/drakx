use MDK::Common;

log::l("PATCH: 2006-new-dmraid");

if (-e '/mnt/dmraid') {
    mkdir_p('/tmp/bin');
    cp_af('/mnt/dmraid', '/tmp/bin');
    $ENV{PATH} = "/tmp/bin:$ENV{PATH}";
} else {
    warn "ERROR: dmraid not available\n";
    die "ERROR: dmraid not available\n";
}
