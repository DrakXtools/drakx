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
    $o->kill;

    for (my $s = $o->{steps}{first}; $s; $s = $o->{steps}{$s}{next}) {

	next if $o->{steps}{$s}{done} && !$o->{steps}{$s}{redoable};
	next if $o->{steps}{$s}{reachable};

	my $reachable = 1;
	if (my $needs = $o->{steps}{$s}{needs}) {
	    my @l = ref $needs ? @$needs : $needs;
	    $reachable = min(map { $o->{steps}{$_}{done} || 0 } @l);
	}
	$o->{steps}{$s}{reachable} = 1, $o->step_set_reachable($s) if $reachable; 
    }
}
sub leavingStep($$) {
    my ($o, $step) = @_;
    log::l("step `$step' finished");

    unless ($o->{steps}{$step}{redoable}) {
	$o->{steps}{$step}{reachable} = 0;
	$o->step_set_unreachable($step);
    }

    while (my $f = shift @{$o->{steps}{$step}{toBeDone} || []}) {
	eval { &$f() };
	$o->ask_warn(_("Error"), [ 
_("An error occurred, i don't know how to handle it nicely,
so continue at your own risk :("), $@ ]) if $@;
    }
}

sub errorInStep($$) {}


#-######################################################################################
#- Steps Functions
#-######################################################################################
#------------------------------------------------------------------------------
sub selectLanguage {
    my ($o) = @_;
    $o->{keyboard} ||= keyboard::lang2keyboard($o->{lang});
    selectKeyboard($o);
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
    fsedit::auto_allocate($hds, $o->{partitions});
}

#------------------------------------------------------------------------------
sub rebootNeeded($) {
    my ($o) = @_;
    log::l("Rebooting...");
    exit "true";
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    foreach (@$fstab) { 
	$_->{toFormat} = ($_->{mntpoint} && isExt2($_) || isSwap($_)) &&
	  ($_->{notFormatted} || $o->{partitioning}{autoformat});
    }
}

sub formatPartitions {
    my $o = shift;
    foreach (@_) {
	fs::format_part($_) if $_->{toFormat};
    }
}

#------------------------------------------------------------------------------
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
    pkgs::install($o->{prefix}, $toInstall, $o->{isUpgrade}, 0);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    #  why not? cuz weather is nice today :-) [pixel]
    sync(); sync();

#    configPCMCIA($o->{rootPath}, $o->{pcmcia});
}

#------------------------------------------------------------------------------
sub mouseConfig($) { 
    my ($o) = @_;
    setVarsInSh("$o->{prefix}/etc/sysconfig/mouse", $o->{mouse});
    symlink $o->{mouse}{DEVICE}, "$o->{prefix}/dev/mouse" or log::l("creating /dev/mouse symlink failed");
}

#------------------------------------------------------------------------------
sub configureNetwork($) {
    my ($o) = @_;
    my $etc = "$o->{prefix}/etc";
#
#    rc = checkNetConfig(&$o->{intf}, &$o->{netc}, &$o->{intfFinal},
#			 &$o->{netcFinal}, &$o->{driversLoaded}, $o->{direction});
    network::write_conf("$etc/sysconfig/network", $o->{netc});
    network::write_resolv_conf("$etc/resolv.conf", $o->{netc});
    network::write_interface_conf("$etc/sysconfig/network-scripts/ifcfg-$_->{DEVICE}", $_) foreach @{$o->{intf}};
    network::add2hosts("$etc/hosts", $o->{netc}{HOSTNAME}, map { $_->{IPADDR} } @{$o->{intf}});
    network::sethostname($o->{netc}) unless $::testing;
    network::addDefaultRoute($o->{netc}) unless $::testing;
    #res_init();		# reinit the resolver so DNS changes take affect     
}

#------------------------------------------------------------------------------
sub timeConfig {
    my ($o, $f) = @_;
    my $t = $o->{timezone};

    setVarsInSh($f, { 
	ZONE => $t->{timezone},
	GMT  => bool2text($t->{GMT}),
	ARC  => "false",
    });
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

    my $f = "$p/etc/passwd";
    my @lines = cat_($f, "failed to open file $f");

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

    $dev = shift @l || die _("no floppy available") 
      if $dev eq "1"; # special case meaning autochoose

    return if $::testing;

    lilo::mkbootdisk($o->{prefix}, versionString(), $dev);
    $o->{mkbootdisk} = $dev;
}

#------------------------------------------------------------------------------
sub setupBootloader($) {
    my ($o) = @_;
    my $versionString = versionString();
    lilo::install($o->{prefix}, $o->{hds}, $o->{fstab}, $versionString, $o->{bootloader});
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
1; # 
