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
            psk => network::tools::convert_key_for_wpa_supplicant($ethntf->{WIRELESS_ENC_KEY}),
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

sub ndiswrapper_installed_drivers() {
    `ndiswrapper -l` =~ /(\w+)\s+driver present/mg;
}

sub ndiswrapper_available_drivers() {
    `ndiswrapper -l` =~ /(\w+)\s+driver present, hardware present/mg;
}

sub ndiswrapper_setup() {
    eval { modules::unload("ndiswrapper") };
    #- unload ndiswrapper first so that the newly installed .inf files will be read
    eval { modules::load("ndiswrapper") };

    #- FIXME: move this somewhere in get_eth_cards, so that configure_eth_aliases correctly writes ndiswrapper
    #- find the first interface matching an ndiswrapper driver, try ethtool then sysfs
    my @available_drivers = ndiswrapper_available_drivers();
    my $ntf_name = find {
        my $drv = c::getNetDriver($_) || readlink("/sys/class/net/$_/driver");
        $drv =~ s!.*/!!;
        member($drv, @available_drivers);
    } detect_devices::getNet();
    #- fallback on wlan0
    return $ntf_name ||  "wlan0";
}

1;
