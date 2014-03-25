package pkgs;

use strict;

use common;
use run_program;
use detect_devices;
use log;

sub rpmsrate_rate_max() {
    5; # also defined in perl-URPM
}

sub rpmsrate_rate_default() {
    detect_devices::need_light_desktop() ? 5 : 4;
}

sub read_rpmsrate_raw {
    my ($file) = @_;
    my $line_nb = 0;
    my $fatal_error;
    my (%flags, %rates, @need_to_copy);
    my (@l);
    local $_;
    foreach (cat_($file)) {
	$line_nb++;
	/\t/ and die "tabulations not allowed at line $line_nb\n";
	s/#.*//; # comments

	my ($indent, $data) = /(\s*)(.*)/;
	next if !$data; # skip empty lines

	@l = grep { $_->[0] < length $indent } @l;

	my @m = @l ? @{$l[-1][1]} : ();
	my ($t, $flag, @l2);
	while ($data =~ 
	       /^((
                   [1-6]
                   |
                   (?:            (?: !\s*)? [0-9A-Z_]+(?:".*?")?)
                   (?: \s*\|\|\s* (?: !\s*)? [0-9A-Z_]+(?:".*?")?)*
                  )
                  (?:\s+|$)
                 )(.*)/x) { #@")) {
	    ($t, $flag, $data) = ($1,$2,$3);
	    while ($flag =~ s,^\s*(("[^"]*"|[^"\s]*)*)\s+,$1,) {}
	    push @m, $flag;
	    push @l2, [ length $indent, [ @m ] ];
	    $indent .= $t;
	}
	if ($data) {
	    # has packages on same line
	    my ($rates, $flags) = partition { /^\d$/ } @m;
	    my ($rate) = @$rates or die sprintf qq(missing rate for "%s" at line %d (flags are %s)\n), $data, $line_nb, join('&&', @m);
	    foreach my $name (split ' ', $data) {
		if (uc($name) eq $name) {
		    log::l("$line_nb: $name is parsed as a package name, not as a flag");
		}
		if (member('INSTALL', @$flags)) {
		    push @need_to_copy, $name if !member('NOCOPY', @$flags);
		    next;    #- do not need to put INSTALL flag for a package.
		}
		if (member('PRINTER', @$flags)) {
		    push @need_to_copy, $name;
		}
		my @new_flags = @$flags;
		if (my $previous = $flags{$name}) {
		    my @common = intersection($flags, $previous);
		    my @diff1 = difference2($flags, \@common);
		    my @diff2 = difference2($previous, \@common);
		    if (!@diff1 || !@diff2) {
			@new_flags = @common;
		    } elsif (@diff1 == 1 && @diff2 == 1) {
			@new_flags = (@common, join('||', $diff1[0], $diff2[0]));
		    } else {
			log::l("$line_nb: cannot handle complicate flags for packages appearing twice ($name)");
			$fatal_error++;
		    }
		    log::l("$line_nb: package $name appearing twice with different rates ($rate != " . $rates{$name} . ")") if $rate != $rates{$name};
		}
		$rates{$name} = $rate;
		$flags{$name} = \@new_flags;
	    }
	    push @l, @l2;
	} else {
	    push @l, [ $l2[0][0], $l2[-1][1] ];
	}
    }
    $fatal_error and die "$fatal_error fatal errors in rpmsrate";
    \%rates, \%flags, \@need_to_copy;
}

sub read_rpmsrate {
    my ($packages, $rpmsrate_flags_chosen, $file, $match_all_hardware) = @_;

    my ($rates, $flags, $need_to_copy) = read_rpmsrate_raw($file);
    
    my ($TYPEs, @probeall);
    if (!$match_all_hardware) {
	$TYPEs = detect_devices::matching_types();
	@probeall = detect_devices::probeall();
    }

    foreach (keys %$flags) {
	my @flags = @{$flags->{$_}};
	my $p;
	if ($::isInstall) {
            $p = install::pkgs::packageByName($packages, $_) or next;
            if (my @l = map { /locales-(.*)/ ? qq(LOCALES"$1") : () } $p->requires_nosense) {
                if (@l > 1) {
                    log::l("ERROR: package $_ is requiring many locales") if !member($_, qw(lsb libreoffice-langpack-br));
                } else {
                    push @flags, @l;
                }
            }
	}

	@flags = map {
	    my ($user_flags, $known_flags) = partition { /^!?CAT_/ } split('\|\|', $_);
	    my $ok = find {
		my $inv = s/^!//;
		return 0 if $::isStandalone && $inv;
		if (my ($p) = /^HW"(.*)"/) {
		    $match_all_hardware ? 1 : ($inv xor find { $_->{description} =~ /$p/i } @probeall);
		} elsif (($p) = /^DRIVER"(.*)"/) {
		    $match_all_hardware ? 1 : ($inv xor find { $_->{driver} =~ /$p/i } @probeall);
		} elsif (($p) = /^TYPE"(.*)"/) {
		    $match_all_hardware ? 1 : ($inv xor $TYPEs->{$p});
		} elsif (($p) = /^HW_CAT"(.*)"/) {
		    $match_all_hardware ? 1 : ($inv xor detect_devices::probe_category($p));
		} else { # LOCALES"", SOUND, ...
		    $inv xor $rpmsrate_flags_chosen->{$_};
		}
	    } @$known_flags;
	    $ok ? 'TRUE' : @$user_flags ? join('||', @$user_flags) : 'FALSE';
	} @flags;

	@flags = member('FALSE', @flags) ? 'FALSE' : @flags;
	if ($::isInstall) {
            $p->set_rate($rates->{$_});
            $p->set_rflags(@flags);
	} else {
            $flags->{$_} = \@flags;
	}
    }
    push @{$packages->{needToCopy} ||= []}, @$need_to_copy if ref($packages);
    return ($rates, $flags);
}


sub simple_read_rpmsrate {
    my ($o_match_all_hardware, $o_ignore_flags) = @_;
    my ($rates, $flags) = read_rpmsrate({}, {}, $::prefix . '/usr/share/meta-task/rpmsrate-raw', $o_match_all_hardware);

    # FIXME: we do not handle !CAT_desktop but we do not care for now:
    if (!$o_match_all_hardware && $o_ignore_flags) {
        while (my ($pkg, $pkg_flags) = each %$flags) {
            my $flags_str = "@$pkg_flags";
            if ($flags_str =~ /TRUE/ && any { $flags_str =~ /[^!]$_/ } @$o_ignore_flags) {
                delete $flags->{$pkg};
            }
        }
    }

    grep { member('TRUE', @{$flags->{$_}}) && $rates->{$_} >= 5 } keys %$flags;
}

sub detect_rpmsrate_hardware_packages {
    my ($o_match_all_hardware, $ignore_flags) = @_;
    grep { !/openoffice|java/ } simple_read_rpmsrate($o_match_all_hardware, $ignore_flags);
}

sub detect_graphical_drivers {
    my ($do_pkgs, $o_match_all_hardware) = @_;
    require Xconfig::card;
    require Xconfig::proprietary;

    my @cards;
    if ($o_match_all_hardware) {
        my $all_cards = Xconfig::card::readCardsDB("$ENV{SHARE_PATH}/ldetect-lst/Cards+");
        @cards = values %$all_cards;
    } else {
        @cards = Xconfig::card::probe();
    }

    my @firmware_pkgs = grep { $_ } uniq(map { $_->{FIRMWARE} } @cards);
    my @drivers = grep { $_ } uniq(map { split(/\,/, $_->{Driver2}) } @cards);
    my @proprietary_pkgs = map { Xconfig::proprietary::pkgs_for_Driver2($_, $do_pkgs) } @drivers;
    return @firmware_pkgs, @proprietary_pkgs;
}

sub detect_network_drivers {
    my ($do_pkgs, $o_match_all_hardware) = @_;
    require network::connection;
    require network::thirdparty;

    my @l;
    foreach my $type (network::connection->get_types) {
        $type->can('get_thirdparty_settings') or next;
        my @network_settings;
        my @all_settings = @{$type->get_thirdparty_settings || []};
        if ($o_match_all_hardware) {
            @network_settings = @all_settings;
        } else {
            my @connections = $type->get_connections(automatic_only => 1, fast_only => 1);
            @network_settings = map { network::thirdparty::find_settings(\@all_settings, $_->get_driver) } @connections;
        }
        foreach my $settings (@network_settings) {
            foreach (@network::thirdparty::thirdparty_types) {
                my @packages = network::thirdparty::get_required_packages($_, $settings);
                push @l, network::thirdparty::get_available_packages($_, $do_pkgs, @packages);
            }
        }
    }
    @l;
}

sub detect_hardware_packages {
    my ($do_pkgs, $o_match_all_hardware) = @_;
    my @ignore_flags = $::isInstall ? () : (
        if_(!$do_pkgs->is_installed('task-kde4-minimal'), "CAT_KDE"),
        if_(!$do_pkgs->is_installed('task-gnome-minimal'), "CAT_GNOME"),
    );
    (
        ($::isInstall ? () : detect_rpmsrate_hardware_packages($o_match_all_hardware, \@ignore_flags)),
        detect_graphical_drivers($do_pkgs, $o_match_all_hardware),
        detect_network_drivers($do_pkgs, $o_match_all_hardware),
    );
}

sub detect_unused_hardware_packages {
    my ($do_pkgs) = @_;
    my @all_hardware_packages = detect_hardware_packages($do_pkgs, 'match_all_hardware');
    my @used_hardware_packages = detect_hardware_packages($do_pkgs);
    my @unneeded_hardware_packages = difference2(\@all_hardware_packages, \@used_hardware_packages);
    $do_pkgs->are_installed(@unneeded_hardware_packages);
}

sub detect_unselected_locale_packages {
    my ($do_pkgs) = @_;
    require lang;
    my $locales_prefix = 'locales-';
    my $locale = lang::read();
    my $selected_locale = $locales_prefix . lang::locale_to_main_locale($locale->{lang});
    my @available_locales = $do_pkgs->are_installed($locales_prefix . '*');
    member($selected_locale, @available_locales) ? difference2(\@available_locales, [ $selected_locale ]) : ();
}

sub remove_unused_locale_packages {
    my ($in, $do_pkgs, $o_prefix) = @_;

    my $wait;
    $wait = $in->wait_message(N("Please wait"), N("Gathering system information..."));
    my @unselected_locales = detect_unselected_locale_packages($do_pkgs);
    undef $wait;

    # Packages to not remove even if they seem unused
    my @wanted_locale_packages = qw(locales-en);
    @unselected_locales = difference2(\@unselected_locales, \@wanted_locale_packages);

    #- we should have some gurpme
    $wait = $in->wait_message(N("Please wait"), N("Preparing for installation..."));
    run_program::rooted($o_prefix, 'urpme', '--auto', @unselected_locales,
        );
    #- use script from One to list language files (/usr/share/locale mainly) and remove them?
}

sub remove_unused_packages {
    my ($in, $do_pkgs, $o_prefix) = @_;

    my $wait;
    $wait = $in->wait_message(N("Unused packages removal"), N("Finding unused hardware packages..."));
    my @unused_hardware_packages = detect_unused_hardware_packages($do_pkgs);
    undef $wait;
    $wait = $in->wait_message(N("Unused packages removal"), N("Finding unused localization packages..."));
    my @unselected_locales = detect_unselected_locale_packages($do_pkgs);
    undef $wait;

    # Packages to not remove even if they seem unused
    my @wanted_hardware_packages = qw(gnome-bluetooth pulseaudio-module-bluetooth gnome-phone-manager bluedevil kppp ppp wireless-tools wpa_supplicant kernel-firmware-nonfree radeon-firmware ralink-firmware rtlwifi-firmware ipw2100-firmware ipw2200-firmware iwlwifi-3945-ucode iwlwifi-4965-ucode iwlwifi-agn-ucode);
    @unused_hardware_packages = difference2(\@unused_hardware_packages, \@wanted_hardware_packages);

    @unused_hardware_packages || @unselected_locales or return;

    my $hardware = @unused_hardware_packages;
    my $locales = @unselected_locales;
    $in->ask_from(
	N("Unused packages removal"),
	N("We have detected that some packages are not needed for your system configuration.") . "\n" .
	N("We will remove the following packages, unless you choose otherwise:"),
	[
	 if_(@unused_hardware_packages,
	     { text => N("Unused hardware support"), val => \$hardware, type => "bool" },
	     { label => N("Unused hardware support") . "\n" . join("\n", map { "  " . $_ } sort(@unused_hardware_packages)), advanced => 1 },
	 ),
	 if_(@unselected_locales,
	     { text => N("Unused localization"), val => \$locales, type => "bool" },
	     { label => N("Unused localization") . "\n"  . join("\n", map { "  " . $_ } sort(@unselected_locales)), advanced => 1 },
	 ),
	],
	if_($::isWizard, cancel => N("Skip")),
    ) && ($hardware || $locales) or return;

    #- we should have some gurpme
    $wait = $in->wait_message(N("Please wait"), N("Removing packages..."));
    run_program::rooted($o_prefix, 'urpme', '--auto',
		     if_($hardware, @unused_hardware_packages),
		     if_($locales, @unselected_locales),
	);
    #- use script from One to list language files (/usr/share/locale mainly) and remove them?
}

1;
