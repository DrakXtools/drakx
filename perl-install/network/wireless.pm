package network::wireless;

use strict;
use common;

our %wireless_enc_modes = (
    none => N("None"),
    open => N("Open WEP"),
    restricted => N("Restricted WEP"),
    'wpa-psk' => N("WPA Pre-Shared Key"),
);

my $wpa_supplicant_conf = "/etc/wpa_supplicant.conf";

sub convert_wep_key_for_iwconfig {
    #- 5 or 13 characters, consider the key as ASCII and prepend "s:"
    #- else consider the key as hexadecimal, do not strip dashes
    #- always quote the key as string
    my ($real_key, $restricted) = @_;
    my $key = member(length($real_key), (5, 13)) ? "s:$real_key" : $real_key;
    $restricted ? "restricted $key" : "open $key";
}

sub get_wep_key_from_iwconfig {
    #- strip "s:" if the key is 5 or 13 characters (ASCII)
    #- else the key as hexadecimal, do not modify
    my ($key) = @_;
    $key =~ s/^s:// if member(length($key), (7,15));
    my ($mode, $real_key) = $key =~ /^(?:(open|restricted)\s+)?(.*)$/;
    ($real_key, $mode eq 'restricted');
}

sub convert_key_for_wpa_supplicant {
    my ($key) = @_;
    if ($key =~ /^([[:xdigit:]]{4}[\:-]?)+[[:xdigit:]]{2,}$/) {
        $key =~ s/[\:-]//g;
        return lc($key);
    } else {
        return qq("$key");
    }
}

sub wlan_ng_needed {
    my ($module) = @_;
    $module =~ /^prism2_/;
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
    my ($essid, $key, $device, $module) = @_;
    my $wlan_conf_file = "$::prefix/etc/wlan/wlan.conf";
    my @wlan_devices = split(/ /, (cat_($wlan_conf_file) =~ /^WLAN_DEVICES="(.*)"/m)[0]);
    push @wlan_devices, $device unless member($device, @wlan_devices);
    #- enable device and make it use the choosen ESSID
    wlan_ng_update_vars($wlan_conf_file,
                        {
                            WLAN_DEVICES => qq("@wlan_devices"),
                            "SSID_$device" => qq("$essid"),
                            "ENABLE_$device" => "y"
                        });

    my $wlan_ssid_file = "$::prefix/etc/wlan/wlancfg-$essid";
    #- copy default settings for this ESSID if config file does not exist
    -f $wlan_ssid_file or cp_f("$::prefix/etc/wlan/wlancfg-DEFAULT", $wlan_ssid_file);

    #- enable/disable encryption
    wlan_ng_update_vars($wlan_ssid_file,
                        {
                            (map { $_ => $key ? "true" : "false" } qw(lnxreq_hostWEPEncrypt lnxreq_hostWEPDecrypt dot11PrivacyInvoked dot11ExcludeUnencrypted)),
                            AuthType => $key ? qq("sharedkey") : qq("opensystem"),
                            if_($key,
                                dot11WEPDefaultKeyID => 0,
                                dot11WEPDefaultKey0 => qq("$key")
                            )
                        });
    #- hide settings for non-root users
    chmod 0600, $wlan_conf_file;
    chmod 0600, $wlan_ssid_file;

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
    "wext";
}

sub wpa_supplicant_add_network {
    my ($essid, $enc_mode, $key) = @_;
    my $conf = wpa_supplicant_read_conf();
    my $network = {
        ssid => qq("$essid"),
        scan_ssid => 1,
    };

    if ($enc_mode eq 'wpa-psk') {
        $network->{psk} = convert_key_for_wpa_supplicant($key);
    } else {
        $network->{key_mgmt} = 'NONE';
        if (member($enc_mode, qw(open restricted))) {
            put_in_hash($network, {
                wep_key0 => convert_key_for_wpa_supplicant($key),
                wep_tx_keyidx => 0,
                auth_alg => $enc_mode eq 'restricted' ? 'SHARED' : 'OPEN',
            });
        }
    }

    @$conf = difference2($conf, [ wpa_supplicant_find_similar($conf, $network) ]);
    push @$conf, $network;
    wpa_supplicant_write_conf($conf);
}

sub wpa_supplicant_find_similar {
    my ($conf, $network) = @_;
    grep {
        my $current = $_;
        any { exists $network->{$_} && $network->{$_} eq $current->{$_} } qw(ssid bssid);
    } @$conf;
}

sub wpa_supplicant_read_conf() {
    my @conf;
    my $network;
    foreach (cat_($::prefix . $wpa_supplicant_conf)) {
        if ($network) {
            #- in a "network = {}" block
            if (/^\s*(\w+)=(.*?)(?:\s*#.*)?$/) {
                $network->{$1} = $2;
            } elsif (/^\}/) {
                #- end of network block
                push @conf, $network;
                undef $network;
            }
        } elsif (/^\s*network={/) {
            #- beginning of a new network block
            $network = {};
        }
    }
    \@conf;
}

sub wpa_supplicant_write_conf {
    my ($conf) = @_;
    my $buf;
    my @conf = @$conf;
    my $network;
    foreach (cat_($::prefix . $wpa_supplicant_conf)) {
        if ($network) {
            #- in a "network = {}" block
            if (/^\s*(\w+)=(.*)$/) {
                push @{$network->{entries}}, { key => $1, value => $2 };
                member($1, qw(ssid bssid)) and $network->{$1} = $2;
            } elsif (/^\}/) {
                #- end of network block, write it
                $buf .= "network={$network->{comment}\n";

                my $new_network = first(wpa_supplicant_find_similar(\@conf, $network));
                foreach (@{$network->{entries}}) {
                    my $key = $_->{key};
                    if ($new_network) {
                        #- do not write entry if not provided in the new network
                        exists $new_network->{$key} or next;
                        #- update value from the new network
                        $_->{value} = delete $new_network->{$key};
                    }
                    $buf .= "    ";
                    $buf .= "$key=$_->{value}" if $key;
                    $buf .= "$_->{comment}\n";
                }
                if ($new_network) {
                    #- write new keys
                    while (my ($key, $value) = each(%$new_network)) {
                        $buf .= "    $key=$value\n";
                    }
                }
                $buf .= "}\n";
                $new_network and @conf = grep { $_ != $new_network } @conf;
                undef $network;
            } else {
                #- unrecognized, keep it anyway
                push @{$network->{entries}}, { comment => $_ };
            }
        } else {
            if (/^\s*network={/) {
                #- beginning of a new network block
                $network = {};
            } else {
                #- keep other options, comments
                $buf .= $_;
            }
        }
    }

    #- write remaining networks
    foreach (@conf) {
        $buf .= "\nnetwork={\n";
        while (my ($key, $value) = each(%$_)) {
            $buf .= "    $key=$value\n";
        }
        $buf .= "}\n";
    }

    output($::prefix . $wpa_supplicant_conf, $buf);
    #- hide keys for non-root users
    chmod 0600, $::prefix . $wpa_supplicant_conf;
}

1;
