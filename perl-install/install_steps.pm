package install_steps;

use diagnostics;
use strict;

use common qw(:file :system);
use install_any qw(:all);
use lilo;
use lang;
use keyboard;
use pkgs;
use cpio;
use log;
use fsedit;
use commands;
use smp;


my $o;

1;


sub new($$) {
    my ($type, $o_) = @_;

    $o = bless $o_, ref $type || $type;
}

sub chooseLanguage($) {
    $o->{default}->{lang}
}

sub selectInstallOrUpgrade($) {
    $o->{default}->{isUpgrade} || 0;
}
sub selectInstallClass($) {
    $o->{default}->{installClass} || 'Custom';
}
sub setupSCSIInterfaces {
    die "TODO";
}

sub doPartitionDisks($$) {
    my ($o, $hds) = @_;
    fsedit::auto_allocate($hds, $o->{default}->{partitions});
}

sub choosePackages($$$) {
    my ($o, $packages, $comps) = @_;

    foreach ('base', @{$o->{default}->{comps}}) {
	$comps->{$_}->{selected} = 1;
	foreach (@{$comps->{$_}->{packages}}) { $_->{selected} = 1; }
    }
    foreach (@{$o->{default}->{packages}}) { $packages->{$_}->{selected} = 1; }

    smp::detect() and $packages->{"kernel-smp"}->{selected} = 1;
}

sub beforeInstallPackages($) {
    $o->{method}->prepareMedia($o->{fstab});

    foreach (qw(dev etc home mnt tmp var var/tmp var/lib var/lib/rpm)) {
	mkdir "$o->{prefix}/$_", 0755;
    }

    unless ($o->{isUpgrade}) {
	local *F;
	open F, "> $o->{prefix}/etc/hosts" or die "Failed to create etc/hosts: $!";
	print F "127.0.0.1		localhost localhost.localdomain\n";
    }
}

sub installPackages($$) {
    my ($o, $packages) = @_;
    my $toInstall = [ $packages->{basesystem}, 
		      grep { $_->{selected} && $_->{name} ne "basesystem" } values %$packages ];
    pkgs::install($o->{prefix}, $o->{method}, $toInstall, $o->{isUpgrade}, 0);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    unless ($o->{isUpgrade}) {
        keyboard::write($o->{prefix}, $o->{keymap});
        lang::write($o->{prefix});
    }
    #  why not? 
    sync(); sync();

#    configPCMCIA($o->{rootPath}, $o->{pcmcia});
}

sub mouseConfig($) { 
    #TODO
}

sub finishNetworking($) {
    my ($o) = @_;
#
#    rc = checkNetConfig(&$o->{intf}, &$o->{netc}, &$o->{intfFinal},
#			 &$o->{netcFinal}, &$o->{driversLoaded}, $o->{direction});
#
#    if (rc) return rc;
#
#    sprintf(path, "%s/etc/sysconfig", $o->{rootPath});
#    writeNetConfig(path, &$o->{netcFinal}, 
#		    &$o->{intfFinal}, 0);
#    strcat(path, "/network-scripts");
#    writeNetInterfaceConfig(path, &$o->{intfFinal});
#    sprintf(path, "%s/etc", $o->{rootPath});
#    writeResolvConf(path, &$o->{netcFinal});
#
#    #  this is a bit of a hack 
#    writeHosts(path, &$o->{netcFinal}, 
#		&$o->{intfFinal}, !$o->{isUpgrade});
#
#    return 0;
}

sub timeConfig {}
sub servicesConfig {}

sub addUser($) {
    my ($o) = @_;
    my $p = $o->{prefix};

    my $new_uid;
    #my @uids = map { (split)[2] } cat__("$p/etc/passwd");
    #for ($new_uid = 500; member($new_uid, @uids); $new_uid++) {}
    for ($new_uid = 500; getpwuid($new_uid); $new_uid++) {}

    my $new_gid;
    #my @gids = map { (split)[2] } cat__("$p/etc/group");
    #for ($new_gid = 500; member($new_gid, @gids); $new_gid++) {}
    for ($new_gid = 500; getgrgid($new_gid); $new_gid++) {}

    my $homedir = "$p/home/$o->{user}->{name}";

    my $pw = crypt_($o->{user}->{password});

    $::testing and return;
    local *F;
    open F, ">> $p/etc/passwd" or die "can't append to passwd file: $!";
    print F "$o->{user}->{name}:$pw:$new_uid:$new_gid:$o->{user}->{realname}:/home/$o->{user}->{name}:$o->{user}->{shell}\n";
	    
    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$o->{user}->{name}::$new_gid:\n";

    eval { commands::cp("-f", "$p/etc/skel", $homedir) }; $@ and log::l("copying of skel failed: $@"), mkdir($homedir, 0750);
    commands::chown_("-r", "$new_uid.$new_gid", $homedir);
}

sub createBootdisk($) {
    lilo::mkbootdisk("/mnt", versionString()) if $o->{mkbootdisk} || $o->{default}->{mkbootdisk};
}

sub setupBootloader($) {
    my ($o) = @_;
    my $versionString = versionString();
    log::l("installed kernel version $versionString");    
    lilo::install($o->{prefix}, $o->{hds}, $o->{fstab}, $versionString, $o->{bootloader} || $o->{default}->{bootloader});
}

sub setRootPassword($) {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $pw = $o->{rootPassword};
    $pw = crypt_($pw);

    my @lines = cat_("$p/etc/passwd", 'die');
    $::testing and return;
    local *F;
    open F, "> $p/etc/passwd" or die "can't write in passwd: $!\n";
    foreach (@lines) {
	s/^root:.*?:/root:$pw:/;
	print F $_;
    }
}


sub setupXfree {
    my ($o) = @_;
    my $x = $o->{default}->{Xserver} or return;
    $o->{packages}->{$x} or die "can't find X server $x";

    log::l("I will install the $x package");
    pkgs::install($o->{prefix}, $o->{method}, $o->{packages}->{$x}, $o->{isUpgrade}, 0);

    #TODO
}

sub exitInstall {}
