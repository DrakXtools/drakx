package cpupower;

use common;
use detect_devices;

my %vendor_ids = (
    GenuineIntel => "Intel",
    AuthenticAMD => "AMD",
    CyrixInstead => "Cyrix",
    "Geode by NSC" => "NSC",
    TransmetaCPU => "Transmeta",
    GenuineTMx86 => "Transmeta",
    CentaurHauls => "Centaur",
);

sub get_vendor {
    my ($cpu) = @_;
    $vendor_ids{$cpu->{vendor_id}};
}

sub has_flag {
    my ($cpu, $flag) = @_;
    $cpu->{flags} =~ /\b$flag\b/;
}

my @cpus;
sub get_cpus() {
    @cpus ? @cpus : @cpus = detect_devices::getCPUs();
}

my @pci;
sub pci_probe() {
    @pci ? @pci : @pci = detect_devices::pci_probe();
}

sub find_pci_device {
    my (@devices) = @_;
    any { my $dev = $_; any { $_->{vendor} == $dev->[0] && $_->{id} == $dev->[1] } pci_probe() } @devices;
}

sub probe_acpi_cpufreq() {
    any {
        get_vendor($_) eq "Intel" &&
        $_->{'cpu family'} == 6 &&
        (
            has_flag($_, 'est') ||
            $_->{model} == 11
        );
    } get_cpus();
}

# see cpuid.c (from cpuid package) for a list of family/models
sub probe_centrino() {
    any {
        get_vendor($_) eq "Intel" &&
        has_flag($_, 'est') && (
            ($_->{'cpu family'} == 6 && $_->{model} == 9 && $_->{stepping} == 5 &&
             $_->{'model name'} =~ /^Intel\(R\) Pentium\(R\) M processor ( 900|1[0-7]00)MHz$/) ||
            ($_->{'cpu family'} == 6 && $_->{model} == 13 && member($_->{stepping}, 1, 2, 6)) ||
            ($_->{'cpu family'} == 15 && $_->{model} == 3 && $_->{stepping} == 4) ||
            ($_->{'cpu family'} == 15 && $_->{model} == 4 && $_->{stepping} == 1)
        );
    } get_cpus();
}

sub probe_ich() { find_pci_device([ 0x8086, 0x244c ], [ 0x8086, 0x24cc ], [ 0x8086, 0x248c ]) }

sub probe_smi() { find_pci_device([ 0x8086, 0x7190 ]) }

sub probe_nforce2() { find_pci_device([ 0x10de, 0x01e0 ]) }

sub probe_gsx() {
    (any { member(get_vendor($_), "Cyrix", "NSC") } get_cpus()) &&
    find_pci_device([ 0x1078, 0x0100 ], [ 0x1078, 0x0002 ], [ 0x1078, 0x0000 ]);
}

sub probe_p4() {
    any {
        get_vendor($_) eq "Intel" && (
            $_->{'cpu family'} == 15 ||
            ($_->{'cpu family'} == 6 && !has_flag($_, 'est') && member($_->{model}, 9, 13, 14, 15, 28))
        );
    } get_cpus();
}

sub probe_powernow_k6() {
    any {
        get_vendor($_) eq "AMD" &&
        $_->{'cpu family'} == 5 &&
        member($_->{model}, 12, 13);
    } get_cpus();
}

sub probe_powernow_k7() {
    any {
        get_vendor($_) eq "AMD" &&
        $_->{'cpu family'} == 6;
    } get_cpus();
}

sub probe_powernow_k8() {
    any {
        get_vendor($_) eq "AMD" && (
            ( $_->{'cpu family'} == 15 && ($_->{'power management'} =~ /\bfid\b/ || has_flag($_, 'fid')) ) # frequency ID control)
                ||
            ( $_->{'cpu family'} == 16 && ($_->{'power management'} =~ /\bhwpstate\b/ )) # support for Athlon/Phenom II processors (#58477))
        );
    } get_cpus();
}

sub probe_longhaul() {
    any {
        get_vendor($_) eq "Centaur" &&
        $_->{'cpu family'} == 6 &&
        member($_->{model}, 6, 7, 8, 9);
    } get_cpus();
}

sub probe_e_powersaver() {
    any {
        get_vendor($_) eq "Centaur" &&
        has_flag($_, 'est') &&
        $_->{'cpu family'} == 6 &&
        member($_->{model}, 10, 13);
    } get_cpus();
}

sub probe_longrun() {
    any {
        get_vendor($_) eq "Transmeta" &&
        has_flag($_, 'longrun');
    } get_cpus();
}

my @modules = (
    # probe centrino first, it will get detected on ICH chipset and
    # speedstep-ich doesn't work with it
    [ "speedstep-centrino", \&probe_centrino ],
    [ "acpi-cpufreq", \&probe_acpi_cpufreq ],
    # try to find cpufreq compliant northbridge
    [ "speedstep-ich", \&probe_ich ],
    [ "speedstep-smi", \&probe_smi ],
    [ "cpufreq-nforce2", \&probe_nforce2 ],
    [ "gsx-suspmod", \&probe_gsx ],
    # try to find a cpufreq compliant processor
    [ "p4-clockmod", \&probe_p4 ],
    [ "powernow-k6", \&probe_powernow_k6 ],
    [ "powernow-k7", \&probe_powernow_k7 ],
    [ "powernow-k8", \&probe_powernow_k8 ],
    [ "longhaul", \&probe_longhaul ],
    [ "e_powersaver", \&probe_e_powersaver ],
    [ "longrun", \&probe_longrun ],
);

sub find_driver() {
    my $m = find { $_->[1]->() } @modules;
    $m && $m->[0];
}

my @governor_modules = map { "cpufreq_$_" } qw(ondemand userspace performance conservative);

sub get_modules() {
    my $module;
    if ($module = find_driver()) {
        return if_($module, $module), @governor_modules;
    }
    ();
}

1;
