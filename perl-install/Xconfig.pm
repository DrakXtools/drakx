package Xconfig;

use diagnostics;
use strict;

use common qw(:common :file :system);
use mouse;
use devices;
use Xconfigurator;

# otherwise uses the rule substr($keymap, 0, 2)
my %keymap_translate = (
    cf => "ca_enhanced",
    uk => "gb",
);


1;

sub keymap_translate {
    $keymap_translate{$_[0]} || substr($_[0], 0, 2);
}


sub getinfo {
    my $o = shift || {};
    getinfoFromDDC($o);
    getinfoFromSysconfig($o);

    add2hash($o->{mouse}, mouse::detect()) unless $o->{mouse}{XMOUSETYPE};

    $o->{mouse}{device} ||= "mouse" if -e "/dev/mouse";
    $o->{mouse}{nbuttons} ||= mouse::X2nbuttons($o->{mouse}{XMOUSETYPE});
    $o;
}

sub getinfoFromXF86Config {
    my $o = shift || {};
    my $prefix = shift || "";
    my (%c, $depth, $driver);

    $o->{card}{server} ||= $1 if readlink("$prefix/etc/X11/X") =~ /XF86_ (\w+)$/x; #- /x for perl2fcalls

    local *F;
    open F, "$prefix/etc/X11/XF86Config" or return {};
    foreach (<F>) {
	if (/^Section "Keyboard"/ .. /^EndSection/) {
	    $o->{keyboard}{xkb_keymap} ||= $1 if /^\s*XkbLayout\s+"(.*?)"/;
	} elsif (/^Section "Pointer"/ .. /^EndSection/) {
	    $o->{mouse}{XMOUSETYPE} ||= $1 if /^\s*Protocol\s+"(.*?)"/;
	    $o->{mouse}{device} ||= $1 if m|^\s*Device\s+"/dev/(.*?)"|;
	    $o->{mouse}{XEMU3} ||= 1 if m/^\s*Emulate3Buttons\s+/;
	    $o->{mouse}{cleardtrrts} ||= 1 if m/^\s*ClearDTR\s+/;
	    $o->{mouse}{cleardtrrts} ||= 1 if m/^\s*ClearRTS\s+/;
	} elsif (my $i = /^Section "Device"/ .. /^EndSection/) {
	    %c = () if $i == 1;

	    $c{type} ||= $1 if /^\s*Identifier\s+"(.*?)"/;
	    $c{memory} ||= $1 if /VideoRam\s+(\d+)/;
	    $c{flags}{needVideoRam} ||= 1 if /^\s*VideoRam\s+/;
	    $c{vendor} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $c{board} ||= $1 if /^\s*BoardName\s+"(.*?)"/;
	    $c{driver} ||= $1 if /^\s*Driver\s+"(.*?)"/;
	    $c{options}{$1} ||= 1 if /^\s*Option\s+"(.*?)"/;
	    $c{options}{$1} ||= 0 if /^\s*#\s*Option\s+"(.*?)"/;

	    #- clockchip, ramdac, dacspeed read with following line.
	    push @{$c{lines}}, $_ unless /(Section|Identifier|VideoRam|VendorName|BoardName|Option)/;

	    add2hash($o->{card} ||= {}, \%c) if ($i =~ /E0/ && $c{type} && $c{type} ne "Generic VGA");
	} elsif (/^Section "Monitor"/ .. /^EndSection/) {
	    $o->{monitor}{type} ||= $1 if /^\s*Identifier\s+"(.*?)"/;
	    $o->{monitor}{hsyncrange} ||= $1 if /^\s*HorizSync\s+(.*)/;
	    $o->{monitor}{vsyncrange} ||= $1 if /^\s*VertRefresh\s+(.*)/;
	    $o->{monitor}{vendor} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $o->{monitor}{model} ||= $1 if /^\s*ModelName\s+"(.*?)"/;
	    $o->{monitor}{modelines} .= $_ if /^\s*Mode[lL]ine\s+/;
	} elsif (my $s = /^Section "Screen"/ .. /^EndSection/) {
	    undef $driver if $s == 1;
	    $driver = $1 if /^\s*Driver\s+"(.*?)"/;
	    if ($driver eq $Xconfigurator::serversdriver{$o->{card}{server}}) {
		$o->{default_depth} ||= $1 if /^\s*DefaultColorDepth\s+(\d+)/;
		if (my $i = /^\s*Subsection\s+"Display"/ .. /^\s*EndSubsection/) {
		    undef $depth if $i == 1;
		    $depth = $1 if /^\s*Depth\s+(\d*)/;
		    if (/^\s*Modes\s+(.*)/) {
			my $a = 0;
			unshift @{$o->{card}{depth}{$depth || 8} ||= []}, #- insert at the beginning for resolution_wanted!
		            grep { $_->[0] >= 640 } map { [ /"(\d+)x(\d+)"/ ] } split ' ', $1;
		    }
		}
	    }
	}
    }
    #- get the default resolution according the the current file.
    if (my @depth = keys %{$o->{card}{depth}}) {
	$o->{resolution_wanted} ||=
	  ($o->{card}{depth}{$o->{default_depth} || $depth[0]}[0][0]) . "x" .
	    ($o->{card}{depth}{$o->{default_depth} || $depth[0]}[0][1]);
    }
    $o;
}

sub getinfoFromSysconfig {
    my $o = shift || {};
    my $prefix = shift || "";

    add2hash($o->{mouse} ||= {}, { getVarsFromSh("$prefix/etc/sysconfig/mouse") });

    if (my %keyboard = getVarsFromSh "$prefix/etc/sysconfig/keyboard") {
	$o->{keyboard}{xkb_keymap} ||= keymap_translate($keyboard{KEYTABLE}) if $keyboard{KEYTABLE};
    }
    $o;
}

sub getinfoFromDDC {
    my $o = shift || {};
    my $O = $o->{monitor} ||= {};
    #- return $o if $O->{hsyncrange} && $O->{vsyncrange} && $O->{modelines};
    devices::make("/dev/zero"); #- needed by ddcxinfos
    my ($m, @l) = `ddcxinfos`;
    $? == 0 or return $o;

    $o->{card}{memory} ||= to_int($m);
    local $_;
    while (($_ = shift @l) ne "\n") {
	my ($depth, $x, $y) = split;
	$depth = int(log($depth) / log(2));
	if ($depth >= 8 && $x >= 640) {
	    push @{$o->{card}{depth}{$depth}}, [ $x, $y ] unless scalar grep { $_->[0] == $x && $_->[1] == $y } @{$o->{card}{depth}{$depth}};
	    push @{$o->{card}{depth}{32}}, [ $x, $y ] if $depth == 24 && ! scalar grep { $_->[0] == $x && $_->[1] == $y } @{$o->{card}{depth}{32}};
	}
    }
    my ($h, $v, $size, @m) = @l;

    chop $h; chop $v;
    $O->{hsyncrange} ||= $h;
    $O->{vsyncrange} ||= $v;
    $O->{size} ||= to_float($size);
    $O->{modelines} ||= join '', @m;
    $o;
}
