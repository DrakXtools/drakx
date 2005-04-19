package network::wireless;

use strict;
use common;
use modules;
use detect_devices;
use c;

sub convert_wep_key_for_iwconfig {
    #- 5 or 13 characters, consider the key as ASCII and prepend "s:"
    #- else consider the key as hexadecimal, do not strip dashes
    #- always quote the key as string
    my ($key) = @_;
    member(length($key), (5, 13)) ? "s:$key" : $key;
}

sub get_wep_key_from_iwconfig {
    #- strip "s:" if the key is 5 or 13 characters (ASCII)
    #- else the key as hexadecimal, do not modify
    my ($key) = @_;
    $key =~ s/^s:// if member(length($key), (7,15));
    $key;
}

sub convert_key_for_wpa_supplicant {
    my ($key) = @_;
    if ($key =~ /^([[:xdigit:]]{4}[\:-])+[[:xdigit:]]{2,}$/) {
        $key =~ s/[\:-]//g;
        return lc($key);
    } else {
        return qq("$key");
    }
}

#- FIXME: to be improved (quotes, comments) and moved in common files
sub wlan_ng_update_vars {
    my ($file, $vars) = @_;
    substInFile {
        while (my ($key, $value) = each(%$vars)) {
            s/^#?\Q$key\E=(?:"[^#]*"|[^#\s]*)(\s*#.*)?/$key=$value$1/ and delete $vars->{$key};
        }
        $_ .= join('', map { "$_=$vars->{$_}\n" } keys %$vars) if eof;
    } $file;
}

sub wlan_ng_configure {
    my ($in, $ethntf, $module) = @_;
    $in->do_pkgs->install('prism2-utils');
    if ($ethntf->{WIRELESS_ESSID}) {
        my $wlan_conf_file = "$::prefix/etc/wlan/wlan.conf";
        my @wlan_devices = split(/ /, (cat_($wlan_conf_file) =~ /^WLAN_DEVICES="(.*)"/m)[0]);
        push @wlan_devices, $ethntf->{DEVICE} unless member($ethntf->{DEVICE}, @wlan_devices);
        #- enable device and make it use the choosen ESSID
        wlan_ng_update_vars($wlan_conf_file,
                            {
                                WLAN_DEVICES => qq("@wlan_devices"),
                                "SSID_$ethntf->{DEVICE}" => qq("$ethntf->{WIRELESS_ESSID}"),
                                "ENABLE_$ethntf->{DEVICE}" => "y"
                            });
        my $wlan_ssid_file = "$::prefix/etc/wlan/wlancfg-$ethntf->{WIRELESS_ESSID}";
        #- copy default settings for this ESSID if config file does not exist
        -f $wlan_ssid_file or cp_f("$::prefix/etc/wlan/wlancfg-DEFAULT", $wlan_ssid_file);
        #- enable/disable encryption
        wlan_ng_update_vars($wlan_ssid_file,
                            {
                                (map { $_ => $ethntf->{WIRELESS_ENC_KEY} ? "true" : "false" } qw(lnxreq_hostWEPEncrypt lnxreq_hostWEPDecrypt dot11PrivacyInvoked dot11ExcludeUnencrypted)),
                                AuthType => $ethntf->{WIRELESS_ENC_KEY} ? qq("sharedkey") : qq("opensystem"),
                                if_($ethntf->{WIRELESS_ENC_KEY},
                                    dot11WEPDefaultKeyID => 0,
                                    dot11WEPDefaultKey0 => qq("$ethntf->{WIRELESS_ENC_KEY}")
                                )
                            });
        #- hide settings for non-root users
        chmod 0600, $wlan_conf_file;
        chmod 0600, $wlan_ssid_file;
    }
    #- apply settings on wlan interface
    require services;
    services::restart($module eq 'prism2_cs' ? 'pcmcia' : 'wlan');
}

sub wpa_supplicant_get_driver {
    my ($module) = @_;
    $module =~ /^hostap_/ ? "hostap" :
    $module eq "prism54" ? "prism54" :
    $module =~ /^ath_/ ? "madwifi" :
    $module =~ /^at76c50|atmel_/ ? "atmel" :
    $module eq "ndiswrapper" ? "ndiswrapper" :
    $module =~ /^ipw2[12]00$/ ? "ipw" :
    "wext";
}

sub wpa_supplicant_configure {
    my ($in, $ethntf) = @_;
    require services;
    $in->do_pkgs->install('wpa_supplicant');

    wpa_supplicant_add_network({
            ssid => qq("$ethntf->{WIRELESS_ESSID}"),
            psk => convert_key_for_wpa_supplicant($ethntf->{WIRELESS_ENC_KEY}),
            scan_ssid => 1,
    });
}

sub wpa_supplicant_add_network {
    my ($new_network) = @_;
    my $wpa_supplicant_conf = "$::prefix/etc/wpa_supplicant.conf";
    my $s;
    my %network;
    foreach (cat_($wpa_supplicant_conf)) {
        if (%network) {
            #- in a "network = {}" block
            if (/^\s*(\w+)=(.*?)(\s*#.*)?$/) {
                push @{$network{entries}}, { key => $1, value => $2, comment => $3 };
                $1 eq 'ssid' and $network{ssid} = $2;
            } elsif (/^\}/) {
                #- end of network block, write it
                $s .= "network={$network{comment}\n";
                my $update = $network{ssid} eq $new_network->{ssid};
                foreach (@{$network{entries}}) {
                    my $key = $_->{key};
                    if ($update) {
                        #- do not write entry if not provided in the new network
                        exists $new_network->{$key} or next;
                        #- update value from the new network
                        $_->{value} = delete $new_network->{$key};
                    }
                    if ($key) {
                        $s .= "    $key=$_->{value}$_->{comment}\n";
                    } else {
                        $s .= " $_->{comment}\n";
                    }
                }
                if ($update) {
                    while (my ($key, $value) = each(%$new_network)) {
                        $s .= "    $key=$value\n";
                    }
                }
                $s .= "}\n";
                undef %network;
                $update and undef $new_network;
            } else {
                #- unrecognized, keep it anyway
                push @{$network{entries}}, { comment => $_ };
            }
        } else {
            if (/^\s*network={(.*)/) {
                #- beginning of a new network block
                $network{comment} = $1;
            } else {
                #- keep other options, comments
                $s .= $_;
            }
        }
    }
    if ($new_network) {
        #- network wasn't found, write it
        $s .= "\nnetwork={\n";
        #- write ssid first
        if (my $ssid = delete $new_network->{ssid}) {
            $s .= "    ssid=$ssid\n";
        }
        while (my ($key, $value) = each(%$new_network)) {
            $s .= "    $key=$value\n";
        }
        $s .= "}\n";
    }
    output($wpa_supplicant_conf, $s);
    #- hide keys for non-root users
    chmod 0600, $wpa_supplicant_conf;
}

my $ndiswrapper_prefix = "$::prefix/etc/ndiswrapper";

sub ndiswrapper_installed_drivers() {
    grep { -d "$ndiswrapper_prefix/$_" } all($ndiswrapper_prefix);
}

sub ndiswrapper_present_devices {
    my ($driver) = @_;
    my @supported_devices;
    foreach (all("$ndiswrapper_prefix/$driver")) {
        my ($ids) = /^([0-9A-Z]{4}:[0-9A-Z]{4})\.[05]\.conf$/;
        $ids and push @supported_devices, $ids;
    }
    grep { member(uc(sprintf("%04x:%04x", $_->{vendor}, $_->{id})), @supported_devices) } detect_devices::probeall();
}

sub ndiswrapper_get_devices {
    my ($in, $driver) = @_;
    my @devices = ndiswrapper_present_devices($driver);
    @devices or $in->ask_warn(N("Error"), N("No device supporting the %s ndiswrapper driver is present!", $driver));
    @devices;
}

sub ndiswrapper_ask_driver {
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

sub ndiswrapper_find_matching_devices {
    my ($device) = @_;
    my $net_path = '/sys/class/net';
    my @devices;

    foreach my $interface (all($net_path)) {
        my $dev_path = "$net_path/$interface/device";
        -l $dev_path or next;

        my %map = (vendor => 'vendor', device => 'id');
        if (every { hex(chomp_(cat_("$dev_path/$_"))) eq $device->{$map{$_}} } keys %map) {
            my $driver = readlink("$net_path/$interface/driver");
            $driver =~ s!.*/!!;
            push @devices, [ $interface, $driver ];
        }
    }

    @devices;
}

sub ndiswrapper_find_conflicting_devices {
    my ($device) = @_;
    grep { $_->[1] ne "ndiswrapper" } ndiswrapper_find_matching_devices($device);
}

sub ndiswrapper_find_interface {
    my ($device) = @_;
    my $dev = find { $_->[1] eq "ndiswrapper" } ndiswrapper_find_matching_devices($device);
    $dev->[0];
}

sub ndiswrapper_setup_device {
    my ($in, $device) = @_;

    eval { modules::unload("ndiswrapper") };
    #- unload ndiswrapper first so that the newly installed .inf files will be read
    eval { modules::load("ndiswrapper") };

    if ($@) {
        $in->ask_warn(N("Error"), N("Unable to load the ndiswrapper module!"));
        return;
    }

    my @ndiswrapper_conflicts = ndiswrapper_find_conflicting_devices($device);
    if (@ndiswrapper_conflicts) {
        $in->ask_yesorno(N("Warning"), N("The selected device has already been configured with the %s driver.
Do you really want to use a ndiswrapper driver ?", $ndiswrapper_conflicts[0][1])) or return;
    }

    my $interface = ndiswrapper_find_interface($device);
    unless ($interface) {
        $in->ask_warn(N("Error"), N("Unable to find the ndiswrapper interface!"));
        return;
    }

    $interface;
}

1;
