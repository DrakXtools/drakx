package scanner;
# scanner.pm $Id$
# Yves Duret <yduret at mandrakesoft.com>
# Copyright (C) 2001-2002 MandrakeSoft
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
# - scsi mis-configuration
# - devfs use dev_is_devfs()
# - with 2 scanners same manufacturer -> will overwrite previous conf -> only 1 conf !!
# - lp: see printerdrake
# - install: prefix --> done

use standalone;
use common;
use detect_devices;
use log;


my $_sanedir = "$::prefix/etc/sane.d";
my $_scannerDBdir = "$::prefix$ENV{SHARE_PATH}/ldetect-lst";
my $scannerDB = readScannerDB("$_scannerDBdir/ScannerDB");

sub confScanner {
    my ($model, $port) = @_;
    $port ||= detect_devices::dev_is_devfs() ? "$::prefix/dev/usb/scanner0" : "$::prefix/dev/scanner";
    my $a = $scannerDB->{$model}{server};
    #print "file:[$a]\t[$model]\t[$port]\n| ", (join "\n| ", @{$scannerDB->{$model}{lines}}),"\n";
    output("$_sanedir/$a.conf", (join "\n", @{$scannerDB->{$model}{lines}}));
    substInFile { s/\$DEVICE/$port/ } "$_sanedir/$a.conf";
    add2dll($a);
}

sub add2dll {
    return if member($_[0], chomp_(cat_("$_sanedir/dll.conf")));
    append_to_file("$_sanedir/dll.conf", "$_[0]\n");
}

sub detect {
    my ($i, @res) = 0;
    foreach (grep { $_->{driver} =~ /scanner/ } detect_devices::usb_probe()) {
	#my ($manufacturer, $model) = split '\|', $_->{description};
	#$_->{description} =~ s/Hewlett[-\s_]Packard/HP/;
	$_->{description} =~ s/Seiko\s+Epson/Epson/i;
	push @res, { port => "/dev/usb/scanner$i", val => { #CLASS => 'SCANNER',
							    #MODEL => $model,
							    #MANUFACTURER => $manufacturer,
							    DESCRIPTION => $_->{description},
							    #id => $_->{id},
							    #vendor => $_->{vendor},
							  } };
	++$i;
    }
    foreach (grep { $_->{media_type} =~ /scanner/ } detect_devices::getSCSI()) {
	   $_->{info} =~ s/Seiko\s+Epson/Epson/i;
	   push @res, { port => "/dev/sg", 
				 val => { DESCRIPTION => $_->{info} },
	   };
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
	    #$cards{$card->{type}} = $card if ($card and !$card->{flags}{unsupported});
	    $cards{$card->{type}} = $card if $card;
	    $val =~ s/Seiko\s+Epson/Epson/i;
	    $card = { type => $val };
	},
	SEE => sub {
	    $val =~ s/Seiko\s+Epson/Epson/i;
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";

	    push @{$card->{lines}}, @{$c->{lines} || []};
	    add2hash($card->{flags}, $c->{flags});
	    add2hash($card, $c);
	},
	ASK => sub { $card->{ask} = $val },
	SERVER => sub { $card->{server} = $val },
	DRIVER => sub { $card->{driver} = $val },
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
    substInFile { s/END// } "ScannerDB";
    my $to_add = "# generated from usbtable by scannerdrake\n";
    foreach (cat_("$ENV{SHARE_PATH}/ldetect-lst/usbtable")) {
	my ($vendor_id, $product_id, $mod, $name) = chomp_(split /\s/,$_,4);
	next if $mod ne '"scanner"';
	$name =~ s/\"(.*)\"$/$1/;
	if (member($name, keys %$scanner::scannerDB)) {
	    print "#[$name] already in ScannerDB!\n";
	    next;
	}
	$to_add .= "NAME $name\nDRIVER usb\nCOMMENT usb $vendor_id $product_id\nUNSUPPORTED\n\n";
    }
    $to_add .= "END\n";

    append_to_file("ScannerDB", $to_add);
}

sub updateScannerDBfromSane {
    my ($_sanesrcdir) = @_;
    substInFile { s/END// } "ScannerDB";

    my $to_add = "# generated from Sane by scannerdrake\n";
    # for compat with our usbtable
    my $sane2DB = { 
		   "Acer" => "Acer Peripherals Inc.",
		   "AGFA" => "AGFA-Gevaert NV",
		   "Agfa" => "AGFA-Gevaert NV",
		   "Epson" => "Epson Corp.",
		   "Fujitsu Computer Products of America" => "Fujitsu",
		   "HP" => sub { $_[0] =~ s/HP\s/Hewlett-Packard|/; $_[0] =~ s/HP4200/Hewlett-Packard|ScanJet 4200C/; $_[0] },
		   "Hewlett-Packard" => sub { $_[0] =~ s/HP 3200 C/Hewlett-Packard|ScanJet 3200C/; $_[0] },
		   "Kodak" => "Kodak Co.",
		   "Mustek" => "Mustek Systems Inc.",
		   "NEC" => "NEC Systems",
		   "Nikon" => "Nikon Corp.",
		   "Plustek" => "Plustek, Inc.",
		   "Primax" => "Primax Electronics",
		   "Siemens" => "Siemens Information and Communication Products",
		   "Trust" => "Trust Technologies",
		   "UMAX" => "Umax",
		   "Vobis/Highscreen" => "Vobis",
		  };

    foreach my $f (glob_("$_sanesrcdir/*.desc")) {
	my $F = common::openFileMaybeCompressed($f);
	$to_add .= "\n# from $f";
	my ($lineno, $cmd, $val) = 0;
	my ($name, $intf, $comment, $mfg, $backend);
	my $fs = {
		  backend => sub { $backend = $val },
		  mfg => sub { $mfg = $val; $name = undef },#bug when a new mfg comes. should called $fs->{ $name }(); but ??
		  model => sub {
		      unless ($name) { $name = $val; next }
		      $name = member($mfg, keys %$sane2DB) ?
			(ref $sane2DB->{$mfg}) ? $sane2DB->{$mfg}($name) : "$sane2DB->{ $mfg }|$name" : "$mfg|$name";
		      if (member($name, keys %$scanner::scannerDB)) {
			  print "#[$name] already in ScannerDB!\n";
		      } else {
			  $to_add .= "\nNAME $name\nSERVER $backend\nDRIVER $intf\n";
			  $to_add .= "COMMENT $comment\n" if $comment;
			  $comment = undef; 
		      }
		      $name = $val;
		  },
		  interface => sub { $intf = $val },
		  comment => sub { $comment = $val },
		 };
	local $_;
	while (<$F>) { $lineno++;
		       s/\s+$//;
		       /^\;/ and next;
		       ($cmd, $val) = /:(\S+)\s*\"([^\;]*)\"/ or next; #log::l("bad line $lineno ($_)"), next;
		       my $f = $fs->{$cmd};
		       $f ? $f->() : log::l("unknown line $lineno ($_)");
		   }
	$fs->{model}(); # the last one
    }
    $to_add .= "\nEND\n";
    append_to_file("ScannerDB", $to_add);
}

1; #
