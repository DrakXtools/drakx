#!/usr/bin/perl

use lib "..";
use common qw(:common :file);
use modules;

my $all = $ARGV[0] eq '-a';

my %modules = map {
    chomp;
    my @l = split "\t";
    my $mod = $l[-2];
    $mod =~ s/"(.*)"/$1/;
    if_(!/^\s*#/ && $mod !~ /:/ && $mod ne 'unknown', $mod => $l[-1])
} map { cat_("/usr/share/ldetect-lst/$_") } 'pcitable', 'usbtable';

my %l;
my $kernel = $all ? '/lib/modules' : '../../kernel';
foreach (`find $kernel -name "*.o" -o -name "*.o.gz"`) {
    s|.*/lib/modules/.*?/||;
    s|kernel/drivers/||;
    m|(.*)/(.*)\.o(\.gz)?$|;
    $l{$2} = $1;
}

foreach (keys %modules) {
    my $ktype = $l{$_};
    my $dtype = $modules::drivers{$_};
    if (!$ktype && !$dtype) {
	print "unused module $_ (descr $modules{$_}) (not in modules.pm nor in the kernel)\n";
    } elsif (!$dtype) {
	$missing{$_} = $ktype;
    } elsif (!$ktype) {
	$unused{$_} = $dtype->{type} 
	  if !member($dtype->{type}, 'sound');
    }
}

foreach (sort keys %missing) {
    print "missing $_ in modules.pm (type $missing{$_}, descr $modules{$_})\n";
}
foreach (sort keys %unused) {
    print "unused module $_ (type $unused{$_}) (not in the kernel)\n";
}

__END__
my %m = %l;
my (%missing, %missing2);
while (my ($k, $v) = each %pci_probing::pcitable::ids) {
    next if $v->[1] =~ /^(unknown$|ignore$|Card:|Server:|Bad:)/;

    $l{$v->[1]} or $missing{$v->[1]} = 1;
    $modules::drivers{$v->[1]} or push @{$missing2{$v->[1]}}, $v->[0];
    delete $m{$v->[1]};
}
print "W: unused entry in modules.pm $_\n" 
  foreach grep { !$l{$_} && !$missing{$_} #- will be reported below
	     } keys %modules::drivers;

print qq|W: missing entry in modules.pm for $l{$_} "$_"\n| foreach grep { !$modules::drivers{$_} } keys %l;

my %known; @known{qw(net scsi misc)} = ();
if ($ARGV[0] eq "-v") {
    print "W: has no pci entry: $_ \n" foreach grep { exists $known{$m{$_}} } keys %m;
}

print "E: missing module $_\n" 
  foreach grep { $modules::drivers{$_}{type} ne "sound" #- don't care about sound modules
	     } keys %missing;

foreach (keys %missing2) {
    print qq|E: missing entry in modules.pm for $l{$_} "$_"|;
    print qq| => "|, join("<>", @{$missing2{$_}}), '"';
    print "\n";
}

#exit;

my %devices_c = (
  net => "checkEthernetDev, DRIVER_NET, DRIVER_MINOR_ETHERNET",
  scsi => "checkSCSIDev, DRIVER_SCSI, DRIVER_MINOR_NONE",
  disk => "checkSCSIDev, DRIVER_SCSI, DRIVER_MINOR_NONE",
  pcmcia => "NULL, DRIVER_PCMCIA, DRIVER_MINOR_NONE",
  paride => "NULL, DRIVER_PARIDE, DRIVER_MINOR_NONE",
  cdrom => "NULL, DRIVER_CDROM, DRIVER_MINOR_NONE",
);
my $devices_c = join "|", keys %devices_c;

my %drivers = %modules::drivers;
$drivers{$_}{type} =~ /$devices_c/ or delete $drivers{$_} foreach keys %drivers;
foreach (cat_("../../install/devices.c")) {
    if (/static struct driver drivers/ .. /^};/) {
	/\s*{\s*"[^"]*"\s*,\s*"(.*)"/ or next;
	delete $drivers{$1} or print qq|W: unused entry in devices.c $1\n|;
    }
}
foreach (sort { $drivers{$a}{type} cmp $drivers{$b}{type} } keys %drivers) {
    my ($m, $v) = ($_, $drivers{$_});
    /^(8390|sunrpc|lockd|dummy|st)$/ and next;

    print qq|E: missing entry in devices.c { "$v->{text}", "$m", 0, $devices_c{$v->{type}} }\n|;
}
