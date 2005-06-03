package network::ndiswrapper;

use strict;
use common;
use modules;
use detect_devices;

my $ndiswrapper_prefix = "$::prefix/etc/ndiswrapper";

sub installed_drivers() {
    grep { -d "$ndiswrapper_prefix/$_" } all($ndiswrapper_prefix);
}

sub present_devices {
    my ($driver) = @_;
    my @supported_devices;
    foreach (all("$ndiswrapper_prefix/$driver")) {
        my ($ids) = /^([0-9A-Z]{4}:[0-9A-Z]{4})\.[05]\.conf$/;
        $ids and push @supported_devices, $ids;
    }
    grep { member(uc(sprintf("%04x:%04x", $_->{vendor}, $_->{id})), @supported_devices) } detect_devices::probeall();
}

sub get_devices {
    my ($in, $driver) = @_;
    my @devices = present_devices($driver);
    @devices or $in->ask_warn(N("Error"), N("No device supporting the %s ndiswrapper driver is present!", $driver));
    @devices;
}

sub ask_driver {
    my ($in) = @_;
    if (my $inf_file = $in->ask_file(N("Please select the Windows driver (.inf file)"), "/mnt/cdrom")) {
        my $driver = basename(lc($inf_file));
        $driver =~ s/\.inf$//;

        #- first uninstall the driver if present, may solve issues if it is corrupted
        -d "$ndiswrapper_prefix/$driver" and system('ndiswrapper', '-e', $driver);

        unless (system('ndiswrapper', '-i', $inf_file) == 0) {
            $in->ask_warn(N("Error"), N("Unable to install the %s ndiswrapper driver!", $driver));
            return undef;
        }

        return $driver;
    }
    undef;
}

sub find_matching_devices {
    my ($device) = @_;
    my $net_path = '/sys/class/net';
    my @devices;

    foreach my $interface (all($net_path)) {
        my $dev_path = "$net_path/$interface/device";
        -l $dev_path or next;
        my $map = detect_devices::get_sysfs_device_id_map($dev_path);
        if (every { hex(chomp_(cat_("$dev_path/" . $map->{$_}))) eq $device->{$_} } keys %$map) {
            my $driver = readlink("$net_path/$interface/driver");
            $driver =~ s!.*/!!;
            push @devices, [ $interface, $driver ];
        }
    }

    @devices;
}

sub find_conflicting_devices {
    my ($device) = @_;
    grep { $_->[1] ne "ndiswrapper" } find_matching_devices($device);
}

sub find_interface {
    my ($device) = @_;
    my $dev = find { $_->[1] eq "ndiswrapper" } find_matching_devices($device);
    $dev->[0];
}

sub setup_device {
    my ($in, $device) = @_;

    #- unload ndiswrapper first so that the newly installed .inf files will be read
    eval { modules::unload("ndiswrapper") };
    eval { modules::load("ndiswrapper") };

    if ($@) {
        $in->ask_warn(N("Error"), N("Unable to load the ndiswrapper module!"));
        return;
    }

    my @conflicts = find_conflicting_devices($device);
    if (@conflicts) {
        $in->ask_yesorno(N("Warning"), N("The selected device has already been configured with the %s driver.
Do you really want to use a ndiswrapper driver ?", $conflicts[0][1])) or return;
    }

    my $interface = find_interface($device);
    unless ($interface) {
        $in->ask_warn(N("Error"), N("Unable to find the ndiswrapper interface!"));
        return;
    }

    $interface;
}

1;
