package common; # $Id$

use MDK::Common;
use MDK::Common::System;
use diagnostics;
use strict;
use vars qw(@ISA @EXPORT $SECTORSIZE);

@ISA = qw(Exporter);
# no need to export ``_''
@EXPORT = qw($SECTORSIZE __ translate untranslate formatXiB removeXiBSuffix formatTime setVirtual makedev unmakedev salt internal_error);

# perl_checker: RE-EXPORT-ALL
push @EXPORT, @MDK::Common::EXPORT;


#-#####################################################################################
#- Globals
#-#####################################################################################
$SECTORSIZE      = 512;

#-#####################################################################################
#- Functions
#-#####################################################################################


sub _ {
    my $s = shift @_; my $t = translate($s);
    sprintf $t, @_;
}
sub __ { $_[0] }

sub salt {
    my ($nb) = @_;
    require devices;
    local *F;
    open F, devices::make("random") or die "missing random";
    my $s; read F, $s, $nb;
    local $_ = pack "b8" x $nb, unpack "b6" x $nb, $s;
    tr [\0-\x3f] [0-9a-zA-Z./];
    $_;
}

sub makedev { ($_[0] << 8) | $_[1] }
sub unmakedev { $_[0] >> 8, $_[0] & 0xff }

sub translate {
    my ($s) = @_;
    $s ? c::dgettext('libDrakX', $s) : '';
}

sub untranslate {
    my $s = shift || return;
    foreach (@_) { translate($_) eq $s and return $_ }
    die "untranslate failed";
}

BEGIN { undef *availableRamMB }
sub availableRamMB()  { 
    my $s = MDK::Common::System::availableRamMB();
    #- HACK HACK: if i810 and memsize
    require detect_devices;
    return $s - 1 if $s == 128 && grep { $_->{driver} =~ /i810/ } detect_devices::probeall();
    $s;
}

sub setVirtual {
    my $vt = '';
    local *C;
    sysopen C, "/dev/console", 2 or die "failed to open /dev/console: $!";
    ioctl(C, c::VT_GETSTATE(), $vt) or die "ioctl VT_GETSTATE failed";
    ioctl(C, c::VT_ACTIVATE(), $_[0]) or die "ioctl VT_ACTIVATE failed";
    ioctl(C, c::VT_WAITACTIVE(), $_[0]) or die "ioctl VT_WAITACTIVE failed";
    unpack "S", $vt;
}


sub removeXiBSuffix {
    local $_ = shift;

    /(\d+)\s*kB?$/i and return $1 * 1024;
    /(\d+)\s*MB?$/i and return $1 * 1024 * 1024;
    /(\d+)\s*GB?$/i and return $1 * 1024 * 1024 * 1024;
    /(\d+)\s*TB?$/i and return $1 * 1024 * 1024 * 1024 * 1024;
    $_;
}
sub formatXiB {
    my ($newnb, $newbase) = (@_, 1);
    my ($nb, $base);
    my $decr = sub { 
	($nb, $base) = ($newnb, $newbase);
	$base >= 1024 ? ($newbase = $base / 1024) : ($newnb = $nb / 1024);
    };
    foreach ('', _("KB"), _("MB"), _("GB")) {
	$decr->(); 
	if ($newnb < 1 && $newnb * $newbase < 1) {
	    my $v = $nb * $base;
	    my $s = $v < 10 && int(10 * $v - 10 * int($v));
	    return int($v) . ($s ? ".$s" : '') . $_;
	}
    }
    int($newnb * $newbase) . _("TB");
}

sub formatTime {
    my ($s, $m, $h) = gmtime($_[0]);
    if ($h) {
	sprintf "%02d:%02d", $h, $m;
    } elsif ($m > 1) {
	_("%d minutes", $m);
    } elsif ($m == 1) {
	_("1 minute");
    } else {
	_("%d seconds", $s);
    }
}

sub usingRamdisk { scalar(grep { /ram3/ } cat_("/proc/mounts")) }

sub expand_symlinks_but_simple {
    my ($f) = @_;
    my $link = readlink($f);
    my $f2 = expand_symlinks($f);
    if ($link && $link !~ m|/|) {
	# put back the last simple symlink
	$f2 =~ s|\Q$link\E$|basename($f)|e;
    }
    $f2
}

sub sync { &MDK::Common::System::sync }

# Group the list by n. Returns a reference of lists of length n
sub group_n_lm {
    my $n = shift;
    my @l;
    push @l, [ splice(@_, 0, $n) ] while (@_);
    @l
}

sub screenshot_dir__and_move {
    my ($dir1, $dir2) = ("$::o->{prefix}/root", '/tmp/stage2');
    if (-e $dir1) {
	if (-e "$dir2/DrakX-screenshots") {
	    cp_af("$dir2/DrakX-screenshots", $dir1);
	    rm_rf("$dir2/DrakX-screenshots");
	}
	$dir1;
    } else {
	$dir2;
    }
}

sub take_screenshot {
    my ($in) = @_;
    my $dir = screenshot_dir__and_move() . '/DrakX-screenshots';
    my $warn;
    if (!-e $dir) {
	mkdir $dir or $in->ask_warn('', _("Can't make screenshots before partitioning")), return;
	$warn = 1;
    }
    my $nb = 1;
    $nb++ while -e "$dir/$nb.png";
    system("fb2png /dev/fb0 $dir/$nb.png 0");

    $in->ask_warn('', _("Screenshots will be available after install in %s", "/root/DrakX-screenshots")) if $warn;
}

sub join_lines {
    my @l;
    my $s;
    foreach (@_) {
	if (/^\s/) {
	    $s .= $_;
	} else {
	    push @l, $s if $s;
	    $s = $_;
	}
    }
    @l, if_($s, $s);
}

sub internal_error {
    die "INTERNAL ERROR: $_[0]\n" . backtrace();
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
