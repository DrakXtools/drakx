package Xconfig; # $Id$

use diagnostics;
use strict;

use any;
use log;
use common;
use mouse;
use devices;
use keyboard;
use Xconfigurator_consts;


sub keyboard_from_kmap {
    my ($loadkey) = @_;
    foreach (keyboard::keyboards()) {
	keyboard::keyboard2kmap($_) eq $loadkey and return keyboard::keyboard2xkb($_);
    }
    '';
}


sub info {
    my ($X) = @_;
    my $info;
    my $xf_ver = $X->{card}{driver} && !$X->{card}{prefer_xf3} ? "4.2.0" : "3.3.6";
    my $title = ($X->{card}{use_DRI_GLX} || $X->{card}{use_UTAH_GLX} ?
		 _("XFree %s with 3D hardware acceleration", $xf_ver) : _("XFree %s", $xf_ver));

    $info .= _("Keyboard layout: %s\n", $X->{keyboard}{XkbLayout});
    $info .= _("Mouse type: %s\n", $X->{mouse}{XMOUSETYPE});
    $info .= _("Mouse device: %s\n", $X->{mouse}{device}) if $::expert;
    $info .= _("Monitor: %s\n", $X->{monitor}{ModelName});
    $info .= _("Monitor HorizSync: %s\n", $X->{monitor}{hsyncrange}) if $::expert;
    $info .= _("Monitor VertRefresh: %s\n", $X->{monitor}{vsyncrange}) if $::expert;
    $info .= _("Graphics card: %s\n", $X->{card}{VendorName} . ' '. $X->{card}{BoardName});
    $info .= _("Graphics card identification: %s\n", $X->{card}{identifier}) if $::expert;
    $info .= _("Graphics memory: %s kB\n", $X->{card}{VideoRam}) if $X->{card}{VideoRam};
    if ($X->{default_depth} and my $depth = $X->{card}{depth}{$X->{default_depth}}) {
	$info .= _("Color depth: %s\n", translate($Xconfigurator_consts::depths{$X->{default_depth}}));
	$info .= _("Resolution: %s\n", join "x", @{$depth->[0]}) if $depth && !is_empty_array_ref($depth->[0]);
    }
    $info .= _("XFree86 server: %s\n", $X->{card}{server}) if $X->{card}{server};
    $info .= _("XFree86 driver: %s\n", $X->{card}{driver}) if $X->{card}{driver};
    "$title\n\n$info";
}

sub getinfo {
    my $X = shift || {};
    getinfoFromDDC($X);
    getinfoFromSysconfig($X);

    my ($mouse) = mouse::detect();
    add2hash($X->{mouse}, $mouse) if !$X->{mouse}{XMOUSETYPE};
    add2hash($X->{mouse}{auxmouse}, $mouse->{auxmouse}) if !$X->{mouse}{auxmouse}{XMOUSETYPE};
    $X->{mouse}{auxmouse}{XMOUSETYPE} or delete $X->{mouse}{auxmouse};

    $X->{mouse}{device} ||= "mouse" if -e "/dev/mouse";
    $X;
}

sub getinfoFromXF86Config {
    my ($X, $prefix) = @_; #- original $::o->{X} which must be changed only if sure!
    $X ||= {};

    #- don't keep the preference on upgrades??
    $X->{card}{prefer_xf3} = readlink("$::prefix/etc/X11/X") =~ /XF86_/ if $::isStandalone;

    my (%keyboard, %mouse, %wacom, %card, %monitor);
    my (%c, $depth);

    foreach (cat_("$prefix/etc/X11/XF86Config-4")) {
	if (my $i = /^Section "InputDevice"/ .. /^EndSection/) {
	    %c = () if $i == 1;

	    $c{driver} = $1 if /^\s*Driver\s+"(.*?)"/;
	    $c{id} = $1 if /^\s*Identifier\s+"[^\d"]*(\d*)"/;
	    $c{XkbModel} ||= $1 if /^\s*Option\s+"XkbModel"\s+"(.*?)"/;
	    $c{XkbLayout} ||= $1 if /^\s*Option\s+"XkbLayout"\s+"(.*?)"/;
	    $c{XMOUSETYPE} ||= $1 if /^\s*Option\s+"Protocol"\s+"(.*?)"/;
	    $c{device} ||= $1 if /^\s*Option\s+"Device"\s+"\/dev\/(.*?)"/;
	    $c{nbuttons}   = 2 if /^\s*Option\s+"Emulate3Buttons"\s+/;
	    $c{nbuttons} ||= 5 if /^\s*#\s*Option\s+"ZAxisMapping"\s.*5/;
	    $c{nbuttons}   = 7 if /^\s*#\s*Option\s+"ZAxisMapping"\s.*7/;

	    if ($i =~ /E0/) {
		@keyboard{qw(XkbLayout)} = @c{qw(XkbLayout)}
		  if $c{driver} =~ /keyboard/i;
		@{$mouse{auxmouse}}{qw(XMOUSETYPE device nbuttons)} = @c{qw(XMOUSETYPE device nbuttons)}
		  if $c{driver} =~ /mouse/i && $c{id} > 1;
		@mouse{qw(XMOUSETYPE device nbuttons)} = @c{qw(XMOUSETYPE device nbuttons)}
		  if $c{driver} =~ /mouse/i && $c{id} < 1;
		$wacom{$c{device}} = undef
		  if $c{driver} =~ /wacom/i;
	    }
	} elsif (/^Section "Monitor"/ .. /^EndSection/) {
	    $monitor{hsyncrange} ||= $1 if /^\s*HorizSync\s+(.*)/;
	    $monitor{vsyncrange} ||= $1 if /^\s*VertRefresh\s+(.*)/;
	    $monitor{VendorName} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $monitor{ModelName} ||= $1 if /^\s*ModelName\s+"(.*?)"/;
	    $monitor{ModeLines} .= $_ if /^\s*Mode[lL]ine\s+(\S+)\s+(\S+)\s+/;
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
    my $first_screen_section;
    foreach (cat_("$prefix/etc/X11/XF86Config")) {
	if (/^Section "Keyboard"/ .. /^EndSection/) {
	    $keyboard{XkbModel} ||= $1 if /^\s*XkbModel\s+"(.*?)"/;
	    $keyboard{XkbLayout} ||= $1 if /^\s*XkbLayout\s+"(.*?)"/;
	} elsif (/^Section "Pointer"/ .. /^EndSection/) {
	    $mouse{XMOUSETYPE} ||= $1 if /^\s*Protocol\s+"(.*?)"/;
	    $mouse{device} ||= $1 if m|^\s*Device\s+"/dev/(.*?)"|;
	    $mouse{nbuttons}   = 2 if m/^\s*Emulate3Buttons\s+/;
	    $mouse{nbuttons} ||= 5 if m/^\s*ZAxisMapping\s.*5/;
	    $mouse{nbuttons}   = 7 if m/^\s*ZAxisMapping\s.*7/;
	} elsif (/^Section "XInput"/ .. /^EndSection/) {
	    if (/^\s*SubSection "Wacom/ .. /^\s*EndSubSection/) {
		$wacom{$1} = undef if /^\s*Port\s+"\/dev\/(.*?)"/;
	    }
	} elsif (/^Section "Monitor"/ .. /^EndSection/) {
	    $monitor{hsyncrange} ||= $1 if /^\s*HorizSync\s+(.*)/;
	    $monitor{vsyncrange} ||= $1 if /^\s*VertRefresh\s+(.*)/;
	    $monitor{VendorName} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $monitor{ModelName} ||= $1 if /^\s*ModelName\s+"(.*?)"/;
	    $monitor{ModeLines_xf3} .= $_ if /^\s*Mode[lL]ine\s+(\S+)\s+(\S+)\s+/;
	} elsif (my $i = /^Section "Device"/ .. /^EndSection/) {
	    %c = () if $i == 1;

	    $c{indentifier} ||= $1 if /^\s*Identifier\s+"(.*?)"/;
	    $c{VideoRam} ||= $1 if /VideoRam\s+(\d+)/;
	    $c{needVideoRam} ||= 1 if /^\s*VideoRam\s+/;
	    $c{driver} ||= $1 if /^\s*Driver\s+"(.*?)"/;
	    $c{VendorName} ||= $1 if /^\s*VendorName\s+"(.*?)"/;
	    $c{BoardName} ||= $1 if /^\s*BoardName\s+"(.*?)"/;
	    $c{Chipset} ||= $1 if /^\s*Chipset\s+"(.*?)"/;
	    $c{options_xf3}{$1} ||= 0 if /^\s*#\s*Option\s+"(.*?)"/;
	    $c{options_xf3}{$1} ||= 1 if /^\s*Option\s+"(.*?)"/;

	    add2hash(\%card, \%c) if ($i =~ /E0/ && $c{identifier} && $c{identifier} ne "Generic VGA");
	} elsif (my $s = /^Section "Screen"/ .. /^EndSection/) {
	    $first_screen_section++ if $s =~ /E0/;
	    $first_screen_section or next;

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

    #- get the default resolution according the the current file.
    #- suggestion to take into account, but that have to be checked.
    $X->{card}{suggest_depth} = $card{default_depth};
    if (my @depth = keys %{$card{depth}}) {
	$X->{card}{suggest_x_res} = ($card{depth}{$X->{card}{suggest_depth} || $depth[0]}[0][0]);
    }

    #- final clean-up.
    $mouse{nbuttons} ||= 3; #- when no tag found, this is because there is 3 buttons.
    $mouse{auxmouse}{nbuttons} ||= 3;
    mouse::update_type_name(\%mouse); #- allow getting fullname (type|name).
    mouse::update_type_name($mouse{auxmouse});
    delete $mouse{auxmouse} if !$mouse{auxmouse}{XMOUSETYPE}; #- only take care of a true mouse.

    #- try to merge with $X, the previous has been obtained by ddcxinfos.
    put_in_hash($X->{keyboard} ||= {}, \%keyboard);
    add2hash($X->{mouse} ||= {}, \%mouse);
    @{$X->{wacom} || []} > 0 or $X->{wacom} = [ keys %wacom ];
    add2hash($X->{monitor} ||= {}, \%monitor);

    $X;
}

sub getinfoFromSysconfig {
    my $X = shift || {};
    my $prefix = shift || "";

    add2hash($X->{mouse} ||= {}, { getVarsFromSh("$prefix/etc/sysconfig/mouse") });

    if (my %keyboard = getVarsFromSh "$prefix/etc/sysconfig/keyboard") {
	$X->{keyboard}{XkbLayout} ||= keyboard_from_kmap($keyboard{KEYTABLE}) if $keyboard{KEYTABLE};
    }
    $X;
}

sub getinfoFromDDC {
    my $X = shift || {};
    my $O = $X->{monitor} ||= {};
    #- return $X if $O->{hsyncrange} && $O->{vsyncrange} && $O->{ModeLines};
    my ($m, @l) = any::ddcxinfos();
    $? == 0 or return $X;

    $X->{card}{VideoRam} ||= to_int($m);
    local $_;
    while (($_ = shift @l) ne "\n") {
	my ($depth, $x, $y) = split;
	$depth = int(log($depth) / log(2));
	if ($depth >= 8 && $x >= 640) {
	    push @{$X->{card}{depth}{$depth}}, [ $x, $y ] 
	      if ! grep { $_->[0] == $x && $_->[1] == $y } @{$X->{card}{depth}{$depth}};
	    push @{$X->{card}{depth}{32}}, [ $x, $y ] 
	      if $depth == 24 && ! grep { $_->[0] == $x && $_->[1] == $y } @{$X->{card}{depth}{32}};
	}
    }
    my ($h, $v, $size, @m) = @l;

    $O->{hsyncrange} ||= first($h =~ /^(\S*)/);
    $O->{vsyncrange} ||= first($v =~ /^(\S*)/);
    $O->{size} ||= to_float($size);
    $O->{EISA_ID} = lc($1) if $size =~ /EISA ID=(\S*)/;
    $O->{ModeLines_xf3} ||= join '', map { "    $_" } @m;
    $X;
}


sub XF86check_link {
    my ($prefix, $ext) = @_;

    my $f = "$prefix/etc/X11/XF86Config$ext";
    touch($f);

    my $l = "$prefix/usr/X11R6/lib/X11/XF86Config$ext";

    if (-e $l && (stat($f))[1] != (stat($l))[1]) { #- compare the inode, must be the sames
	-e $l and unlink($l) || die "can't remove bad $l";
	symlinkf "../../../../etc/X11/XF86Config$ext", $l;
    }
}

sub add2card {
    my ($card, $other_card) = @_;

    push @{$card->{lines}}, @{$other_card->{lines} || []};
    add2hash($card, $other_card);
}

sub readCardsDB {
    my ($file) = @_;
    my ($card, %cards);

    my $F = common::openFileMaybeCompressed($file);

    my ($lineno, $cmd, $val) = 0;
    my $fs = {
	NAME => sub {
	    $cards{$card->{card_name}} = $card if $card;
	    $card = { card_name => $val };
	},
	SEE => sub {
	    my $c = $cards{$val} or die "Error in database, invalid reference $val at line $lineno";
	    add2card($card, $c);
	},
        LINE => sub { push @{$card->{lines}}, $val },
	CHIPSET => sub { $card->{Chipset} = $val },
	SERVER => sub { $card->{server} = $val },
	DRIVER => sub { $card->{driver} = $val },
	DRIVER2 => sub { $card->{driver2} = $val },
	NEEDVIDEORAM => sub { $card->{needVideoRam} = 1 },
	DRI_GLX => sub { $card->{DRI_GLX} = 1 if $card->{driver} },
	UTAH_GLX => sub { $card->{UTAH_GLX} = 1 if $card->{server} },
	DRI_GLX_EXPERIMENTAL => sub { $card->{DRI_GLX_EXPERIMENTAL} = 1 if $card->{driver} },
	UTAH_GLX_EXPERIMENTAL => sub { $card->{UTAH_GLX_EXPERIMENTAL} = 1 if $card->{server} },
	MULTI_HEAD => sub { $card->{MULTI_HEAD} = $val if $card->{driver} },
	BAD_FB_RESTORE => sub { $card->{BAD_FB_RESTORE} = 1 },
	BAD_FB_RESTORE_XF3 => sub { $card->{BAD_FB_RESTORE_XF3} = 1 },
	UNSUPPORTED => sub { delete $card->{driver} },

	COMMENT => sub {},
    };

    local $_;
    while (<$F>) { $lineno++;
	s/\s+$//;
	/^#/ and next;
	/^$/ and next;
	/^END/ and do { $cards{$card->{card_name}} = $card if $card; last };

	($cmd, $val) = /(\S+)\s*(.*)/ or next;

	my $f = $fs->{$cmd};

	$f ? $f->() : log::l("unknown line $lineno ($_)");
    }
    \%cards;
}

sub install_matrox_proprietary_hal {
    my ($prefix) = @_;
    my $tmpdir = "$prefix/root/tmp";

    my $tar = "mgadrivers-2.0.tgz";
    my $dir_in_tar = "mgadrivers";
    my $dest_dir = "$prefix/usr/X11R6/lib/modules/drivers";

    #- already installed
    return if -e "$dest_dir/mga_hal_drv.o";

    system("wget -O $tmpdir/$tar ftp://ftp.matrox.com/pub/mga/archive/linux/2002/$tar") if !-e "$tmpdir/$tar";
    system("tar xzC $tmpdir -f $tmpdir/$tar");

    my $src_dir = "$tmpdir/$dir_in_tar/xfree86/4.2.0/drivers";
    foreach (all($src_dir)) {
	my $src = "$src_dir/$_";
	my $dest = "$dest_dir/$_";
	rename $dest, "$dest.non_hal";
	cp_af($src, $dest_dir);
    }
    rm_rf("$tmpdir/$tar");
    rm_rf("$tmpdir/$dir_in_tar");
}

1;
