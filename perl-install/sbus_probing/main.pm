package sbus_probing::main; # $Id$

use c;
use log;
use common;
use modules;

my %sbus_table_network = (
			  hme    => [ "Sun Happy Meal Ethernet", "sunhme" ],
			  le     => [ "Sun Lance Ethernet", "ignore:lance" ],
			  qe     => [ "Sun Quad Ethernet", "sunqe" ],
			  mlanai => [ "MyriCOM MyriNET Gigabit Ethernet", "myri_sbus" ],
			  myri   => [ "MyriCOM MyriNET Gigabit Ethernet", "myri_sbus" ],
			 );
my %sbus_table_scsi =    (
			  soc   => [ "Sun SPARCStorage Array", "fc4:soc:pluto" ],
			  socal => [ "Sun Enterprise Network Array", "fc4:socal:fcal" ],
			  esp   => [ "Sun Enhanced SCSI Processor (ESP)", "ignore:esp" ],
			  fas   => [ "Sun Swift (ESP)", "ignore:esp" ],
			  ptisp => [ "Performance Technologies ISP", "qlogicpti" ],
			  isp   => [ "QLogic ISP", "qlogicpti" ],
			 );
my %sbus_table_audio =   (
			  audio      => [ "AMD7930", "amd7930" ],
			  CS4231     => [ "CS4231 APC DMA (SBUS)", "cs4231" ],
			  CS4231_PCI => [ "CS4231 EB2 DMA (PCI)", "cs4231" ],
			 );
my %sbus_table_video =   (
			  bwtwo         => [ "Sun|Monochrome (bwtwo)", "Server:SunMono" ],
			  cgthree       => [ "Sun|Color3 (cgthree)", "Server:Sun" ],
			  cgeight       => [ "Sun|CG8/RasterOps", "Server:Sun" ],
			  cgtwelve      => [ "Sun|GS (cgtwelve)", "Server:Sun24" ],
			  gt            => [ "Sun|Graphics Tower", "Server:Sun24" ],
			  mgx           => [ "Sun|Quantum 3D MGXplus", "Server:Sun24" ],
			  mgx_4M        => [ "Sun|Quantum 3D MGXplus with 4M VRAM", "Server:Sun24" ],
			  cgsix         => [ "Sun|Unknown GX", "Server:Sun" ],
			  cgsix_dbl     => [ "Sun|Double Width GX", "Server:Sun" ],
			  cgsix_sgl     => [ "Sun|Single Width GX", "Server:Sun" ],
			  cgsix_t1M     => [ "Sun|Turbo GX with 1M VSIMM", "Server:Sun" ],
			  cgsix_tp      => [ "Sun|Turbo GX Plus", "Server:Sun" ],
			  cgsix_t       => [ "Sun|Turbo GX", "Server:Sun" ],
			  cgfourteen    => [ "Sun|SX", "Server:Sun24" ],
			  cgfourteen_4M => [ "Sun|SX with 4M VSIMM", "Server:Sun24" ],
			  cgfourteen_8M => [ "Sun|SX with 8M VSIMM", "Server:Sun24" ],
			  leo           => [ "Sun|ZX or Turbo ZX", "Server:Sun24" ],
			  leo_t         => [ "Sun|Turbo ZX", "Server:Sun24" ],
			  tcx           => [ "Sun|TCX (S24)", "Server:Sun24" ],
			  tcx_8b        => [ "Sun|TCX (8bit)", "Server:Sun" ],
			  afb           => [ "Sun|Elite3D", "Server:Sun24" ],
			  afb_btx03     => [ "Sun|Elite3D-M6 Horizontal", "Server:Sun24" ],
			  ffb           => [ "Sun|FFB", "Server:Sun24" ],
			  ffb_btx08     => [ "Sun|FFB 67Mhz Creator", "Server:Sun24" ],
			  ffb_btx0b     => [ "Sun|FFB 67Mhz Creator 3D", "Server:Sun24" ],
			  ffb_btx1b     => [ "Sun|FFB 75Mhz Creator 3D", "Server:Sun24" ],
			  ffb_btx20     => [ "Sun|FFB2 Vertical Creator", "Server:Sun24" ],
			  ffb_btx28     => [ "Sun|FFB2 Vertical Creator", "Server:Sun24" ],
			  ffb_btx23     => [ "Sun|FFB2 Vertical Creator 3D", "Server:Sun24" ],
			  ffb_btx2b     => [ "Sun|FFB2 Vertical Creator 3D", "Server:Sun24" ],
			  ffb_btx30     => [ "Sun|FFB2+ Vertical Creator", "Server:Sun24" ],
			  ffb_btx33     => [ "Sun|FFB2+ Vertical Creator 3D", "Server:Sun24" ],
			  ffb_btx40     => [ "Sun|FFB2 Horizontal Creator", "Server:Sun24" ],
			  ffb_btx48     => [ "Sun|FFB2 Horizontal Creator", "Server:Sun24" ],
			  ffb_btx43     => [ "Sun|FFB2 Horizontal Creator 3D", "Server:Sun24" ],
			  ffb_btx4b     => [ "Sun|FFB2 Horizontal Creator 3D", "Server:Sun24" ],
			 );

1;

sub prom_getint { unpack "I", c::prom_getproperty($_[0]) }

#- update $@sbus_probed according to SBUS detection.
sub prom_walk {
    my ($sbus_probed, $node, $sbus, $ebus) = @_;
    my ($prob_name, $prob_type) = (c::prom_getstring("name"), c::prom_getstring("device_type"));
    my ($nextnode, $nsbus, $nebus) = (undef, $sbus, $ebus);

    #- probe for network devices.
    if ($sbus && $prob_type eq 'network') {
	$prob_name =~ s/[A-Z,]*(.*)/$1/;
	$sbus_table_network{$prob_name} and push @$sbus_probed, [ "NETWORK", @{$sbus_table_network{$prob_name}} ];
	#- TODO for Sun Quad Ethernet (qe)
    }

    #- probe for scsi devices.
    if ($sbus && ($prob_type eq 'scsi' || $prob_name =~ /^(soc|socal)$/)) {
	$prob_name =~ s/[A-Z,]*(.*)/$1/;
	$sbus_table_scsi{$prob_name} and push @$sbus_probed, [ "SCSI", @{$sbus_table_scsi{$prob_name}} ];
    }

    #- probe for audio devices, there are no type to check here.
    if ($sbus_table_audio{$prob_name}) {
	$prob_name =~ /,/ and $prob_name =~ s/[A-Z,]*(.*)/$1/;
	my $ext = $prob_name eq 'CS4231' && $ebus && "_PCI";
	$sbus_table_audio{$prob_name . $ext} ?
	    push @$sbus_probed, [ "AUDIO", @{$sbus_table_audio{$prob_name . $ext}} ] :
	    push @$sbus_probed, [ "AUDIO", @{$sbus_table_audio{$prob_name}} ];
    }

    #- probe for video devices.
    if ($prob_type eq 'display' && ($sbus || $prob_name =~ /^(ffb|afb|cgfourteen)$/)) {
	$prob_name =~ s/[A-Z,]*(.*)/$1/;
	my $ext = ($prob_name eq 'mgx' && prom_getint('fb_size') == 0x400000 && '_4M' ||
		   $prob_name eq 'cgsix' && do {
		       my ($chiprev, $vmsize) = (prom_getint('chiprev'), prom_getint('vmsize'));
		       my $result = '';
		       $chiprev >= 1 && $chiprev <= 4 and $result = '_dbl';
		       $chiprev >= 5 && $chiprev <= 9 and $result = '_sgl';
		       $chiprev == 11 && $vmsize == 2 and $result = '_t1M';
		       $chiprev == 11 && $vmsize == 4 and $result = '_tp';
		       $chiprev == 11 && !$result and $result = '_t';
		       $result;
		   } ||
		   $prob_name eq 'leo' && c::prom_getstring('model') =~ /501-2503/ && '_t' ||
		   $prob_name eq 'tcx' && c::prom_getbool('tcx-8-bit') && '_8b' ||
		   $prob_name eq 'afb' && sprintf "_btx%x", prom_getint('board_type') ||
		   $prob_name eq 'ffb' && sprintf "_btx%x", prom_getint('board_type'));

	$sbus_table_video{$prob_name . $ext} ?
	    push @$sbus_probed, [ "VIDEO", @{$sbus_table_video{$prob_name . $ext}} ] :
	    push @$sbus_probed, [ "VIDEO", @{$sbus_table_video{$prob_name}} ];
    }

    #- parse prom tree.
    $prob_name eq 'sbus' || $prob_name eq 'sbi' and $nsbus = 1;
    $prob_name eq 'ebus' and $nebus = 1;
    $nextnode = c::prom_getchild($node) and prom_walk($sbus_probed, $nextnode, $nsbus, $nebus);
    $nextnode = c::prom_getsibling($node) and prom_walk($sbus_probed, $nextnode, $sbus, $ebus);
}

sub probe {
    eval { modules::load("openprom") } if arch() =~ /sparc/;
    my $root_node = c::prom_open() or return;
    my @l;

    prom_walk(\@l, $root_node, 0, 0);
    c::prom_close();
    map { my %l; @l{qw(type description drivers)} = @$_; \%l } @l;
}
