use strict;


BEGIN {
    #- for testing purpose
    (my $f = __FILE__) =~ s|/[^/]*$||;
    push @INC, $f;
}

use MDK::Common;
use list_modules;

#- seldom used modules
#- we don't bother making a special floppy for those
my %modules_only_for_all_img = (

  'network/main' => [
    qw(olympic acenic),
    qw(aironet4500_card com20020-pci hamachi starfire winbond-840),

    # token ring
    qw(tmspci ibmtr abyss),

    if_(arch() =~ /x86_64/, qw(orinoco_plx)), # don't support laptop for now
    if_(arch() =~ /x86_64/, qw(hp100 epic100)), # old (nico)
    if_(arch() =~ /alpha|ppc/, qw(sb1000)),
    qw(iph5526),

    qw(ac3200 at1700 atp ni5010 ni52 ni65),  #- unused from Jeff
  ],

  'bus/pcmcia' => [
    if_(arch() =~ /x86_64/, qw(pcmcia_core ds tcic yenta_socket)), # don't support laptop for now
    if_(arch() =~ /x86_64/, qw(i82092 i82365)), # doco says "older laptops"
  ],

  'disk/scsi' => [
    # ISA cards:
    qw(NCR53c406a aha152x psi240i qlogicfas qlogicfc wd7000 sim710 t128 ultrastor), '53c7,8xx',
    qw(qla2x00 in2000 pas16 a100u2w seagate g_NCR5380),
    if_(arch() =~ /x86_64/, qw(53c7,8xx nsp32 initio advansys atp870u)), #- old
    qw(AM53C974), # deprecated by tmscsim
    qw(u14-34f), #- duplicate from ultrastor.o
    #- still used, keeping them: qw(aha1542 sym53c416),
    qw(lpfcdd), #- HUGE!!

    qw(dc395x_trm mptscsih BusLogic fdomain),
    qw(pci2220i eata eata_pio eata_dma),
    'aic7xxx_old', 'qlogicisp',
    'dtc',
  ],

  'disk/hardware_raid' => [
    if_(arch() =~ /x86_64/, qw(ataraid)), #- old
    qw(i2o_block qla2200 qla2300 cpqfc DAC960 gdth pdc-ultra),
  ],
);

#- modules that will only be available in stage2
#-   those modules are NOT in all.img, network.img...
#-   there should only be modules that can't be used on stage1
#-   completly unused modules should be removed directly from the kernel
#-     (and so be removed from stage2 too)
my %modules_removed_from_stage1 = (
  'network/main' => [
     'plip'
  ],

  'disk/hardware_raid' => [
    qw(imm ppa),
  ],
);

my @modules_always_on_stage1 = qw(floppy);


sub flatten_and_check {
    my ($h) = @_;
    map { 
	my $category = $_;
	my @l = @{$h->{$category}};
	if (my @bad = difference2(\@l, [ category2modules($category) ])) {
	    foreach (@bad) {
		if (my $cat = module2category($_)) {
		    warn "ERROR in modules.pl: module $_ is in category $cat, not in $category\n";
		} else {
		    warn "ERROR in modules.pl: unknown module $_\n";
		}
	    }
	    exit 1;
	}
	@l;
    } keys %$h;
}

my @modules_only_for_all_img    = flatten_and_check(\%modules_only_for_all_img);
my @modules_removed_from_stage1 = flatten_and_check(\%modules_removed_from_stage1);


my %images = (
    pcmcia  => 'fs/cdrom disk/cdrom|raw|pcmcia bus/pcmcia',
    cdrom   => 'fs/cdrom disk/cdrom|raw|scsi',
    network  => 'bus/usb|usb_keyboard|pcmcia disk/raw|usb',
    network_drivers => 'fs/network network/main|pcmcia|usb|raw|gigabit',
    all     => 'fs/cdrom disk/cdrom|raw bus/usb|usb_keyboard disk/usb|scsi fs/loopback|local bus/pcmcia disk/pcmcia|hardware_raid fs/network network/main|pcmcia|usb|raw|gigabit bus/firewire disk/firewire',
);

my $verbose = "@ARGV" =~ /-v/;
images() if "@ARGV" =~ /images/;
check() if "@ARGV" =~ /check/;
pci_modules4stage1($1) if "@ARGV" =~ /pci_modules4stage1:(.*)/;

sub images() {
    while (my ($image, $l) = each %images) {
	my @modules = if_($image !~ /drivers/, @modules_always_on_stage1);
	push @modules, map { category2modules($_) } split(' ', $l);
	
	@modules = difference2(\@modules, \@modules_removed_from_stage1);

	if ($image !~ /all/) {
	    @modules = difference2(\@modules, \@modules_only_for_all_img);
	}
	printf qq(%s_modules_raw="%s"\n), $image, join ' ', @modules;
    }
    printf qq(images="%s"\n), join(' ', keys %images);
}

sub pci_modules4stage1 {
    print "$_\n" foreach uniq(map { dependencies_closure($_) } difference2([ category2modules($_[0]) ], \@modules_removed_from_stage1));
}

sub check() {
    my $error;
    my %listed;
    while (my ($t1, $l) = each %list_modules::l) {
	while (my ($t2, $l) = each %$l) {
	    ref $l or die "bad $l in $t1/$t2";
	    foreach (@$l) {
		$listed{$_} = "$t1/$t2"; 
	    }
	}
    }

    my %module2category;
    my %deprecated_modules = %listed;
    my $not_listed = sub {
	my ($msg, $verbose, @l) = @_;
	my %not_listed;
	foreach (@l) {
	    my ($mod) = m|([^/]*)\.k?o(\.gz)?$| or next;
	    delete $deprecated_modules{$mod};
	    next if $listed{$mod};
	    s|.*?mdk(BOOT)?/||;
	    s|kernel/||; s|drivers/||; s|3rdparty/||;
	    $_ = dirname $_;
	    $_ = dirname $_ if $mod eq basename($_);
	    $module2category{$mod} = $_;
	    push @{$not_listed{$_}}, $mod;
	}
	if ($verbose) {
	    print "$msg $_: ", join(" ", @{$not_listed{$_}}), "\n" foreach sort keys %not_listed;
	}
    };
    $not_listed->('NOT LISTED', 1, `cd all.kernels/2.6* ; find -name "*.k?o" -o -name "*.k?o.gz"`);
    $not_listed->('not listed', $verbose, `rpm -qpl /RPMS/kernel-2.6*`);
    if (%deprecated_modules) {
	my %per_cat;
	push @{$per_cat{$listed{$_}}}, $_ foreach keys %deprecated_modules;
	foreach my $cat (sort keys %per_cat) {
	    print "bad/old modules ($cat) : ", join(" ", sort @{$per_cat{$cat}}), "\n";
	}
    }

    {
	require '/usr/bin/merge2pcitable.pl';
	my $pcitable = read_pcitable("/usr/share/ldetect-lst/pcitable");
	my $usbtable = read_pcitable("/usr/share/ldetect-lst/usbtable");

	my @l1 = uniq grep { !/:/ && $_ ne 'unknown' } map { $_->[0] } values %$pcitable;
	if (my @l = difference2(\@l1, [ keys %listed ])) {
	    my %not_listed;
	    push @{$not_listed{$module2category{$_}}}, $_ foreach @l;
	    if (my $l = delete $not_listed{''}) {
		print "bad/old pcitable modules : ", join(" ", @$l), "\n";
	    }
	    print STDERR "PCITABLE MODULES NOT LISTED $_: ", join(" ", @{$not_listed{$_}}), "\n" foreach sort keys %not_listed;
	    #$error = 1;
	}

	my @l2 = uniq grep { !/:/ && $_ ne 'unknown' } map { $_->[0] } values %$usbtable;
	if (my @l = difference2(\@l2, [ keys %listed ])) {
	    my %not_listed;
	    push @{$not_listed{$module2category{$_}}}, $_ foreach @l;
	    if ($verbose) {
		print "usbtable modules not listed $_: ", join(" ", @{$not_listed{$_}}), "\n" foreach sort keys %not_listed;
	    }
	}
    }

    exit $error;
}
