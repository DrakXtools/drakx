package install_steps;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:file :system :common);
use install_any qw(:all);
use partition_table qw(:types);
use detect_devices;
use timezone;
use modules;
use run_program;
use lilo;
use lang;
use keyboard;
use printer;
use pkgs;
use log;
use fsedit;
use commands;
use network;
use fs;


#-######################################################################################
#- OO Stuff
#-######################################################################################
sub new($$) {
    my ($type, $o) = @_;

    bless $o, ref $type || $type;
    return $o;
}

#-######################################################################################
#- In/Out Steps Functions
#-######################################################################################
sub enteringStep($$) {
    my ($o, $step) = @_;
    log::l("starting step `$step'");

    for (my $s = $o->{steps}{first}; $s; $s = $o->{steps}{$s}{next}) {

	next if $o->{steps}{$s}{done} && !$o->{steps}{$s}{redoable};
	next if $o->{steps}{$s}{reachable};

	my $reachable = 1;
	if (my $needs = $o->{steps}{$s}{needs}) {
	    my @l = ref $needs ? @$needs : $needs;
	    $reachable = min(map { $o->{steps}{$_}{done} || 0 } @l);
	}
	$o->{steps}{$s}{reachable} = 1 if $reachable;
    }
}
sub leavingStep($$) {
    my ($o, $step) = @_;
    log::l("step `$step' finished");

    $o->{steps}{$step}{reachable} = $o->{steps}{$step}{redoable};

    while (my $f = shift @{$o->{steps}{$step}{toBeDone} || []}) {
	eval { &$f() };
	$o->ask_warn(_("Error"), [
_("An error occurred, but I don't know how to handle it nicely,
so continue at your own risk :("), $@ ]) if $@;
    }
}

sub errorInStep($$) { print "error :(\n"; exit 1 }
sub kill_action {}


#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;
    lang::set($o->{lang});

    unless ($o->{keyboard_force}) {
	$o->{keyboard} = keyboard::lang2keyboard($o->{lang});
	selectKeyboard($o);
    }
}
#------------------------------------------------------------------------------
sub selectKeyboard {
    my ($o) = @_;
    keyboard::setup($o->{keyboard})
}
#------------------------------------------------------------------------------
sub selectPath {}
#------------------------------------------------------------------------------
sub selectInstallClass($@) {}
#------------------------------------------------------------------------------
sub setupSCSI { modules::load_thiskind('scsi') }
#------------------------------------------------------------------------------
sub doPartitionDisks($$) {
    my ($o, $hds) = @_;
    return if $::testing;
    partition_table::write($_) foreach @$hds;
}

#------------------------------------------------------------------------------
sub rebootNeeded($) {
    my ($o) = @_;
    log::l("Rebooting...");
    exec "true";
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    $_->{mntpoint} = "swap" foreach grep { isSwap($_) } @$fstab;
    $_->{toFormat} = $_->{mntpoint} &&
      ($_->{notFormatted} || $o->{partitioning}{autoformat}) foreach @$fstab;
}

sub formatPartitions {
    my $o = shift;
    foreach (@_) {
	fs::format_part($_) if $_->{toFormat};
    }
}

#------------------------------------------------------------------------------
sub setPackages {
    my ($o, $install_classes) = @_;
    install_any::setPackages($o, $install_classes);
}
sub findPackagesToUpgrade {
    my ($o) = @_;
    install_any::findPackagesToUpgrade($o);
}

sub choosePackages($$$) {
    my ($o, $packages, $compss) = @_;
}

sub beforeInstallPackages {
    my ($o) = @_;

    network::add2hosts("$o->{prefix}/etc/hosts", "localhost.localdomain", "127.0.0.1");
    pkgs::init_db($o->{prefix}, $o->{isUpgrade});
}

sub installPackages($$) {
    my ($o, $packages) = @_;
    my $toInstall = [ grep { $_->{selected} && !$_->{installed} } values %$packages ];
    pkgs::install($o->{prefix}, $toInstall);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    #-  why not? cuz weather is nice today :-) [pixel]
    sync(); sync();

    $o->pcmciaConfig();
}

#------------------------------------------------------------------------------
sub selectMouse($) {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub configureNetwork($) {
    my ($o) = @_;
    my $etc = "$o->{prefix}/etc";

    network::write_conf("$etc/sysconfig/network", $o->{netc});
    network::write_resolv_conf("$etc/resolv.conf", $o->{netc});
    network::write_interface_conf("$etc/sysconfig/network-scripts/ifcfg-$_->{DEVICE}", $_) foreach @{$o->{intf}};
    network::add2hosts("$etc/hosts", $o->{netc}{HOSTNAME}, map { $_->{IPADDR} } @{$o->{intf}});
    network::sethostname($o->{netc}) unless $::testing;
    network::addDefaultRoute($o->{netc}) unless $::testing;
    #-res_init();		#- reinit the resolver so DNS changes take affect
}

#------------------------------------------------------------------------------
sub pcmciaConfig($) {
    my ($o) = @_;
    my $t = $o->{pcmcia};
    my $f = "$o->{prefix}/etc/sysconfig/pcmcia";

    #- should be set after installing the package above else the file will be renamed.
    setVarsInSh($f, {
	PCMCIA    => $t ? "yes" : "no",
	PCIC      => $t,
	PCIC_OPTS => "",
        CORE_OPTS => "",
    });
}

#------------------------------------------------------------------------------
sub timeConfig {
    my ($o, $f) = @_;
    timezone::write($o->{prefix}, $o->{timezone}, $f);
}

#------------------------------------------------------------------------------
sub servicesConfig {}
#------------------------------------------------------------------------------
sub printerConfig {
    my($o) = @_;
    if ($o->{printer}{complete}) {

	pkgs::select($o->{packages}, $o->{packages}{'rhs-printfilters'});
	$o->installPackages($o->{packages});

	printer::configure_queue($o->{printer});
    }
}

#------------------------------------------------------------------------------
my @etc_pass_fields = qw(name password uid gid realname home shell);
sub setRootPassword($) {
    my ($o) = @_;
    my %u = %{$o->{superuser}};
    my $p = $o->{prefix};

    $u{password} = crypt_($u{password}) if $u{password};

    my @lines = cat_(my $f = "$p/etc/passwd") or log::l("missing passwd file"), return;

    local *F;
    open F, "> $f" or die "failed to write file $f: $!\n";
    foreach (@lines) {
	if (/^root:/) {
	    chomp;
	    my %l; @l{@etc_pass_fields} = split ':';
	    add2hash(\%u, \%l);
	    $_ = join(':', @u{@etc_pass_fields}) . "\n";
	}
	print F $_;
    }
}

#------------------------------------------------------------------------------
sub addUser($) {
    my ($o) = @_;
    my %u = %{$o->{user}};
    my $p = $o->{prefix};
    my @passwd = cat_("$p/etc/passwd");;

    !$u{name} || getpwnam($u{name}) and return;

    for ($u{uid} = 500; getpwuid($u{uid}); $u{uid}++) {}
    for ($u{gid} = 500; getgrgid($u{gid}); $u{gid}++) {}
    $u{home} ||= "/home/$u{name}";

    $u{password} = crypt_($u{password}) if $u{password};

    return if $::testing;

    local *F;
    open F, ">> $p/etc/passwd" or die "can't append to passwd file: $!";
    print F join(':', @u{@etc_pass_fields}), "\n";

    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$u{name}::$u{gid}:\n";

    eval { commands::cp("-f", "$p/etc/skel", "$p$u{home}") }; $@ and log::l("copying of skel failed: $@"), mkdir("$p$u{home}", 0750);
    commands::chown_("-r", "$u{uid}.$u{gid}", "$p$u{home}");
}

#------------------------------------------------------------------------------
sub createBootdisk($) {
    my ($o) = @_;
    my $dev = $o->{mkbootdisk} or return;

    my @l = detect_devices::floppies();

    $dev = shift @l || die _("No floppy drive available")
      if $dev eq "1"; #- special case meaning autochoose

    return if $::testing;

    lilo::mkbootdisk($o->{prefix}, install_any::kernelVersion(), $dev);
    $o->{mkbootdisk} = $dev;
}

#------------------------------------------------------------------------------
sub setupBootloaderBefore {
    my ($o) = @_;
    add2hash($o->{bootloader} ||= {}, lilo::read($o->{prefix}, "/etc/lilo.conf"));
    lilo::suggest($o->{prefix}, $o->{bootloader}, $o->{hds}, $o->{fstab}, install_any::kernelVersion());
    $o->{bootloader}{keytable} ||= keyboard::kmap($o->{keyboard});
}

sub setupBootloader($) {
    my ($o) = @_;
    return if $::g_auto_install;
    lilo::install($o->{prefix}, $o->{bootloader});
}

#------------------------------------------------------------------------------
sub setupXfree {
    my ($o) = @_;
}

#------------------------------------------------------------------------------
sub exitInstall {}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1;
