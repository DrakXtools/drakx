package common; # $Id$

use MDK::Common;
use MDK::Common::System;
use diagnostics;
use strict;
use vars qw(@ISA @EXPORT $SECTORSIZE);

@ISA = qw(Exporter);
# no need to export ``_''
@EXPORT = qw(arch $SECTORSIZE __ translate untranslate formatXiB removeXiBSuffix formatTime setVirtual makedev unmakedev salt isCdNotEjectable compat_arch better_arch);

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

sub arch() {
    require c;
    c::kernel_arch();
}
sub better_arch {
    my ($new, $old) = @_;
    while ($new && $new ne $old) { $new = $compat_arch{$new} }
    $new;
}
sub compat_arch { better_arch(arch(), $_[0]) }



sub salt {
    my ($nb) = @_;
    require devices;
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
    c::dgettext('libDrakX', $s);
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

sub isCdNotEjectable { scalar(grep { /ram3/ } cat_("/proc/mounts")) == 0 }

sub sync { &MDK::Common::System::sync }

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
