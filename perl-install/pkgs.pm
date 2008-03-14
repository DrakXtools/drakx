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
			log::l("can not handle complicate flags for packages appearing twice ($name)");
			$fatal_error++;
		    }
		    log::l("package $name appearing twice with different rates ($rate != " . $rates{$name} . ")") if $rate != $rates{$name};
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
	} elsif ($::isStandalone) {
         $flags->{$_} = \@flags;
	}
    }
    push @{$packages->{needToCopy} ||= []}, @$need_to_copy if ref($packages);
    return ($rates, $flags) if $::isStandalone;
}

1;
