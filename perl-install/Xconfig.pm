package Xconfig; # $Id$

use diagnostics;
use strict;

use common;
use mouse;
use devices;
use Xconfigurator;

# otherwise uses the rule substr($keymap, 0, 2)
my %keymap_translate = (
    cf => "ca_enhanced",
    uk => "gb",
);


sub keymap_translate {
    $keymap_translate{$_[0]} || substr($_[0], 0, 2);
}


sub getinfo {
    my $o = shift || {};
    getinfoFromDDC($o);
    getinfoFromSysconfig($o);

    my ($mouse) = mouse::detect();
    add2hash($o->{mouse}, $mouse) unless $o->{mouse}{XMOUSETYPE};
    add2hash($o->{mouse}{auxmouse}, $mouse->{auxmouse}) unless $o->{mouse}{auxmouse}{XMOUSETYPE};
    $o->{mouse}{auxmouse}{XMOUSETYPE} or delete $o->{mouse}{auxmouse};

    $o->{mouse}{device} ||= "mouse" if -e "/dev/mouse";
    $o;
}

sub getinfoFromXF86Config {
    my $o = shift || {}; #- original $::o->{X} which must be changed only if sure!
    my $prefix = shift || "";
    my (%keyboard, %mouse, %wacom, %card, %monitor);
    my (%c, $depth, $driver);

    local $_;
    local *G; open G, "$prefix/etc/X11/XF86Config-4";
    while (<G>) {
	if (my $i = /^Section "InputDevice"/ .. /^EndSection/) {
	    %c = () if $i == 1;

	    $c{driver} = $1 if /^\s*Driver\s+"(.*?)"/;
	    $c{id} = $1 if /^\s*Identifier\s+"[^\d"]*(\d*)"/;
	    $c{xkb_model} ||= $1 if /^\s*Option\s+"XkbModel"\s+"(.*?)"/;
	    $c{xkb_keymap} ||= $1 if /^\s*Option\s+"XkbLayout"\s+"(.*?)"/;
	    $c{XMOUSETYPE} ||= $1 if /^\s*Option\s+"Protocol"\s+"(.*?)"/;
	    $c{device} ||= $1 if /^\s*Option\s+"Device"\s+"\/dev\/(.*?)"/;
	    $c{chordmiddle} ||= $1 if /^\s*Option\s+"ChordMiddle"\s+"\/dev\/(.*?)"/;
	    $c{nbuttons}   = 2 if /^\s*Option\s+"Emulate3Buttons"\s+/;
	    $c{nbuttons} ||= 5 if /^\s*#\s*Option\s+"ZAxisMapping"\s.*5/;
	    $c{nbuttons}   = 7 if /^\s*#\s*Option\s+"ZAxisMapping"\s.*7/;

	    if ($i =~ /E0/) {
		@keyboard{qw(xkb_keymap)} = @c{qw(xkb_keymap)}
		  if $c{driver} =~ /keyboard/i;
		@{$mouse{auxmouse}}{qw(XMOUSETYPE device chordmiddle nbuttons)} = @c{qw(XMOUSETYPE device chordmiddle nbuttons)}
		  if $c{driver} =~ /mouse/i && $c{id} > 1;
		@mouse{qw(XMOUSETYPE device chordmiddle nbuttons)} = @c{qw(XMOUSETYPE device chordmiddle nbuttons)}
		  if $c{driver} =~ /mouse/i && $c{id} < 1;
		$wacom{$c{device}} = undef
		  if $c{driver} =~ /wacom/i;
	    }
	} elsif (/^Section "Monitor"/ .. /^EndSection/) {
	    $monitor{type} ||= $1 if /^\s*Identifier\s+"(.*?)"/;
	    $monitor{hsyncrange} ||= $1 if /^\s*HorizSync\s+(.*)/;
	    $monitor{vsyncrange} ||= $1 if /^\s*VertRefresh\s+(.*)/;
	    $monitor{vendor} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $monitor{model} ||= $1 if /^\s*ModelName\s+"(.*?)"/;
	    $monitor{modelines_}{"$1_$2"} = $_ if /^\s*Mode[lL]ine\s+(\S+)\s+(\S+)\s+/;
	} elsif (my $s = /^Section "Screen"/ .. /^EndSection/) {
	    $card{default_depth} ||= $1 if /^\s*DefaultColorDepth\s+(\d+)/;
	    if (my $i = /^\s*Subsection\s+"Display"/ .. /^\s*EndSubsection/) {
		undef $depth if $i == 1;
		$depth = $1 if /^\s*Depth\s+(\d*)/;
		if (/^\s*Modes\s+(.*)/) {
		    my $a = 0;
		    unshift @{$card{depth}{$depth || 8} ||= []}, #- insert at the beginning for resolution_wanted!
		      grep { $_->[0] >= 640 } map { [ /"(\d+)x(\d+)"/ ] } split ' ', $1;
		}
	    }
	}
    }
    close G;
    local *F; open F, "$prefix/etc/X11/XF86Config";
    while (<F>) {
	if (/^Section "Keyboard"/ .. /^EndSection/) {
	    $keyboard{xkb_model} ||= $1 if /^\s*XkbModel\s+"(.*?)"/;
	    $keyboard{xkb_keymap} ||= $1 if /^\s*XkbLayout\s+"(.*?)"/;
	} elsif (/^Section "Pointer"/ .. /^EndSection/) {
	    $mouse{XMOUSETYPE} ||= $1 if /^\s*Protocol\s+"(.*?)"/;
	    $mouse{device} ||= $1 if m|^\s*Device\s+"/dev/(.*?)"|;
	    $mouse{cleardtrrts} ||= 1 if m/^\s*ClearDTR\s+/;
	    $mouse{cleardtrrts} ||= 1 if m/^\s*ClearRTS\s+/;
	    $mouse{chordmiddle} ||= 1 if m/^\s*ChordMiddle\s+/;
	    $mouse{nbuttons}   = 2 if m/^\s*Emulate3Buttons\s+/;
	    $mouse{nbuttons} ||= 5 if m/^\s*ZAxisMapping\s.*5/;
	    $mouse{nbuttons}   = 7 if m/^\s*ZAxisMapping\s.*7/;
	} elsif (/^Section "XInput"/ .. /^EndSection/) {
	    if (/^\s*SubSection "Wacom/ .. /^\s*EndSubSection/) {
		$wacom{$1} = undef if /^\s*Port\s+"\/dev\/(.*?)"/;
	    }
	} elsif (/^Section "Monitor"/ .. /^EndSection/) {
	    $monitor{type} ||= $1 if /^\s*Identifier\s+"(.*?)"/;
	    $monitor{hsyncrange} ||= $1 if /^\s*HorizSync\s+(.*)/;
	    $monitor{vsyncrange} ||= $1 if /^\s*VertRefresh\s+(.*)/;
	    $monitor{vendor} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $monitor{model} ||= $1 if /^\s*ModelName\s+"(.*?)"/;
	    $monitor{modelines_}{"$1_$2"} = $_ if /^\s*Mode[lL]ine\s+(\S+)\s+(\S+)\s+/;
	} elsif (my $i = /^Section "Device"/ .. /^EndSection/) {
	    %c = () if $i == 1;

	    $c{type} ||= $1 if /^\s*Identifier\s+"(.*?)"/;
	    $c{memory} ||= $1 if /VideoRam\s+(\d+)/;
	    $c{flags}{needVideoRam} ||= 1 if /^\s*VideoRam\s+/;
	    $c{vendor} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $c{board} ||= $1 if /^\s*BoardName\s+"(.*?)"/;
	    $c{driver} ||= $1 if /^\s*Driver\s+"(.*?)"/;
	    $c{options_xf3}{$1} ||= 1 if /^\s*Option\s+"(.*?)"/;
	    $c{options_xf3}{$1} ||= 0 if /^\s*#\s*Option\s+"(.*?)"/;

	    add2hash(\%card, \%c) if ($i =~ /E0/ && $c{type} && $c{type} ne "Generic VGA");
	} elsif (my $s = /^Section "Screen"/ .. /^EndSection/) {
	    undef $driver if $s == 1;
	    $driver = $1 if /^\s*Driver\s+"(.*?)"/;
	    if ($driver eq $Xconfigurator::serversdriver{$card{server}}) {
		$card{default_depth} ||= $1 if /^\s*DefaultColorDepth\s+(\d+)/;
		if (my $i = /^\s*Subsection\s+"Display"/ .. /^\s*EndSubsection/) {
		    undef $depth if $i == 1;
		    $depth = $1 if /^\s*Depth\s+(\d*)/;
		    if (/^\s*Modes\s+(.*)/) {
			my $a = 0;
			unshift @{$card{depth}{$depth || 8} ||= []}, #- insert at the beginning for resolution_wanted!
		            grep { $_->[0] >= 640 } map { [ /"(\d+)x(\d+)"/ ] } split ' ', $1;
		    }
		}
	    }
	}
    }
    close F;

    #- clean up modeline by those automatically given by $modelines_text.
    foreach (split /\n/, $Xconfigurator::modelines_text) {
	delete $monitor{modelines_}{"$1_$2"} if /^\s*Mode[lL]ine\s+(\S+)\s+(\S+)\s+(.*)/;
    }
    $monitor{modelines} .= $_ foreach values %{$monitor{modelines_}}; delete $monitor{modelines_};

    #- get the default resolution according the the current file.
    #- suggestion to take into account, but that have to be checked.
    $o->{card}{suggest_depth} = $card{default_depth};
    if (my @depth = keys %{$card{depth}}) {
	$o->{card}{suggest_wres} = ($card{depth}{$o->{card}{suggest_depth} || $depth[0]}[0][0]);
    }

    #- final clean-up.
    $mouse{nbuttons} ||= 3; #- when no tag found, this is because there is 3 buttons.
    $mouse{auxmouse}{nbuttons} ||= 3;
    mouse::update_type_name(\%mouse); #- allow getting fullname (type|name).
    mouse::update_type_name($mouse{auxmouse});
    delete $mouse{auxmouse} unless $mouse{auxmouse}{XMOUSETYPE}; #- only take care of a true mouse.

    #- try to merge with $o, the previous has been obtained by ddcxinfos.
    add2hash($o->{keyboard} ||= {}, \%keyboard);
    add2hash($o->{mouse} ||= {}, \%mouse);
    @{$o->{wacom} || []} > 0 or $o->{wacom} = [ keys %wacom ];
    add2hash($o->{monitor} ||= {}, \%monitor);

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

    $O->{hsyncrange} ||= first($h =~ /^(\S*)/);
    $O->{vsyncrange} ||= first($v =~ /^(\S*)/);
    $O->{size} ||= to_float($size);
    $O->{EISA_ID} = lc($1) if $size =~ /EISA ID=(\S*)/;
    $O->{modelines} ||= join '', @m;
    $o;
}

1;
