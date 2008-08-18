package pkgs; # $Id$

use strict;

use common;
use run_program;
use detect_devices;
use log;


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
                   [1-5]
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
			log::l("$line_nb: can not handle complicate flags for packages appearing twice ($name)");
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
	$p = install::pkgs::packageByName($packages, $_)  or next;
	if (my @l = map { /locales-(.*)/ ? qq(LOCALES"$1") : () } $p->requires_nosense) {
	    if (@l > 1) {
		log::l("ERROR: package $_ is requiring many locales") if $_ ne 'lsb';
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
		} else {
		    $inv xor $rpmsrate_flags_chosen->{$_};
		}
	    } @$known_flags;
	    $ok ? 'TRUE' : @$user_flags ? join('||', @$user_flags) : 'FALSE';
	} @flags;

	if ($::isInstall) {
	$p->set_rate($rates->{$_});
	$p->set_rflags(member('FALSE', @flags) ? 'FALSE' : @flags);
	} else {
         $flags->{$_} = \@flags;
	}
    }
    push @{$packages->{needToCopy} ||= []}, @$need_to_copy if ref($packages);
    return ($rates, $flags);
}


sub simple_read_rpmsrate {
    my ($o_match_all_hardware) = @_;
    my ($rates, $flags) = read_rpmsrate({}, {}, $::prefix . '/usr/share/meta-task/rpmsrate-raw', $o_match_all_hardware);
    grep { member('TRUE', @{$flags->{$_}}) && $rates->{$_} >= 5 } keys %$flags;
}

sub list_hardware_packages {
    my ($o_match_all_hardware) = @_;
    grep { !/openoffice/ } simple_read_rpmsrate($o_match_all_hardware);
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

    my @drivers = grep { $_ } uniq(map { $_->{Driver2} } @cards);
    map { Xconfig::proprietary::pkgs_for_Driver2($_, $do_pkgs) } @drivers;
}

sub detect_network_drivers {
    my ($do_pkgs, $o_match_all_hardware) = @_;
    require network::connection;
    require network::thirdparty;

    my @l;
    foreach my $type (network::connection->get_types) {
        $type->can('get_thirdparty_settings') or next;
        my @network_settings;
        if ($o_match_all_hardware) {
            @network_settings = @{$type->get_thirdparty_settings || []};
        } else {
            my @connections = $type->get_connections(automatic_only => 1, fast_only => 1);
            @network_settings = map { @{$_->get_thirdparty_settings || []} } @connections;
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
    (
        ($::isInstall ? () : list_hardware_packages($o_match_all_hardware)),
        detect_graphical_drivers($do_pkgs, $o_match_all_hardware),
        detect_network_drivers($do_pkgs, $o_match_all_hardware),
    );
}

1;
