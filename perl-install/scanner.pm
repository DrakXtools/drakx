#!/usr/bin/perl

# scanner.pm $Id$
# Yves Duret <yduret at mandrakesoft.com>
# Copyright (C) 2001 MandrakeSoft
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
# pbs/TODO:
# - no scsi support
# - devfs use dev_is_devfs()
# - with 2 scanners same manufacturer -> will overwrite previous conf -> only 1 conf !!
# - lp: see printerdrake
# - install: prefix ??

package scanner;
use lib qw(/usr/lib/libDrakX);
use standalone;
use common;
use detect_devices;


my $_sanedir = "/etc/sane.d";
my $_scannerDBdir = "$ENV{SHARE_PATH}/ldetect-lst";
$scannerDB = readScannerDB("$_scannerDBdir/ScannerDB");

sub confScanner {
    my ($model, $port) = @_;
    $port = detect_devices::dev_is_devfs() ? "/dev/usb/scanner0" : "/dev/scanner" if (!$port);
    my $a = $scannerDB->{$model}{server};
    output("$_sanedir/$a.conf", (join "\n",@{$scannerDB->{$model}{lines}}));
    substInFile {s/\$DEVICE/$port/} "$_sanedir/$a.conf";
    add2dll($a);
}

sub add2dll {
    return if member($_[0], chomp_(cat_("$_sanedir/dll.conf")));
    local *F;
    open F, ">>$_sanedir/dll.conf" or die "can't write SANE config in $_sanedir/dll.conf: $!";
    print F $_[0];
    close F;
}

sub findScannerUsbport {
    my ($i, $elem, @res) = (0, {});
    foreach (grep { $_->{driver} =~ /scanner/ } detect_devices::usb_probe()) {
	#my ($manufacturer, $model) = split '\|', $_->{description};
	#$_->{description} =~ s/Hewlett[-\s_]Packard/HP/;
	push @res, { port => "/dev/usb/scanner$i", val => { #CLASS => 'SCANNER',
							    #MODEL => $model,
							    #MANUFACTURER => $manufacturer,
							    DESCRIPTION => $_->{description},
							    #id => $_->{id},
							    #vendor => $_->{vendor},
							  }};
	++$i;
    }
    @res;
}

sub readScannerDB {
    my ($file) = @_;
    my ($card, %cards);

    my $F = common::openFileMaybeCompressed($file);

    my ($lineno, $cmd, $val) = 0;
    my $fs = {
        LINE => sub { push @{$card->{lines}}, $val },
	NAME => sub {
	    $cards{$card->{type}} = $card if $card;
	    $card = { type => $val };
	},
	SEE => sub {
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";

	    push @{$card->{lines}}, @{$c->{lines} || []};
	    add2hash($card->{flags}, $c->{flags});
	    add2hash($card, $c);
	},
	SERVER => sub { $card->{server} = $val; },
	DRIVER => sub { $card->{driver} = $val; },
	UNSUPPORTED => sub { $card->{flags}{unsupported} = 1 },
	COMMENT => sub {},
    };

    local $_;
    while (<$F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and do { $cards{$card->{type}} = $card if $card; last };
	($cmd, $val) = /(\S+)\s*(.*)/ or next; #log::l("bad line $lineno ($_)"), next;
	my $f = $fs->{$cmd};
	$f ? $f->() : log::l("unknown line $lineno ($_)");
    }
    \%cards;
}

sub updateScannerDBfromUsbtable {
    substInFile {s/END//} "ScannerDB";
    local *F;
    open F, ">>ScannerDB" or die "can't write ScannerDB config in ScannerDB: $!";
    foreach (cat_("$ENV{SHARE_PATH}/ldetect-lst/usbtable")) {
	my (undef, undef, $mod, $name) = chomp_(split /\s/,$_,4);
	next unless ($mod eq "\"scanner\"");
	$name =~ s/\"(.*)\"$/$1/;
	if (member($name, keys %$scanner::scannerDB)) {
	    print "$name already in ScannerDB\n";
	    next;
	}
	print F "NAME $name\nDRIVER usb\nUNSUPPORTED\n\n";
    }
     print F "END\n";
    close F;
}

#-----------------------------------------------
# $Log$
# Revision 1.1  2001/10/10 12:44:59  yduret
# *** empty log message ***
#
