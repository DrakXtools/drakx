package cdrom;

use diagnostics;
use strict;

use detect_devices;


my %transTable = ( cm206 => 'cm206cd', sonycd535 => 'cdu535');

1;


sub setupCDdevicePanel {
    my ($type) = @_;
}

sub findAtapi {
    my $ide = ideGetDevices();
    foreach (@$ide) { $_->{type} eq 'cdrom' and return $_->{device} }
    error();
}

sub findSCSIcdrom {
    detect_devices::isSCSI() or return error();
    my $scsi = detect_devices::getSCSI();
    foreach (@$scsi) { $_->{type} eq 'cdrom' and return $_->{device} }
    error();
}

sub setupCDdevice {
    my ($cddev, $dl) = @_;
    #-TODO
}

sub removeCDmodule {
    #- this wil fail silently if no CD module has been loaded
    removeDeviceDriver('cdrom');
    1;
}

