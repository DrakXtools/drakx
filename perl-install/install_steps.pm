package install_steps;

use diagnostics;
use strict;

use common qw(:file :system);
use install_any qw(:all);
use partition_table qw(:types);
use run_program;
use lilo;
use lang;
use keyboard;
use pkgs;
use cpio;
use log;
use fsedit;
use commands;


my $o;

1;


sub new($$) {
    my ($type, $o_) = @_;

    $o = bless $o_, ref $type || $type;
}

sub chooseLanguage($) {
#    eval { run_program::run('loadkeys', "/tmp/$o->{default}->{lang}) }; $@ and log::l("loadkeys failed");
    $o->{default}->{lang};
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
sub rebootNeeded($) {
    my ($o) = @_;
    log::l("Rebooting...");
    exit(0);
}

sub choosePartitionsToFormat($$) {
    my ($o, $fstab) = @_;

    foreach (@$fstab) { 
	$_->{toFormat} = $_->{mntpoint} && (isExt2($_) || isSwap($_)) &&
	  ($_->{notFormatted} || $o->{default}->{partitionning}->{autoformat});
    }
}

sub choosePackages($$$) {
    my ($o, $packages, $comps) = @_;

    foreach (@{$o->{default}->{comps}}) { $comps->{$_}->{selected} = 1; }
    foreach (@{$o->{default}->{packages}}) { $packages->{$_}->{selected} = 1; }
}

sub beforeInstallPackages($) {

    $o->{method}->prepareMedia($o->{prefix}, $o->{fstab}) unless $::testing;

    foreach (qw(dev etc home mnt tmp var var/tmp var/lib var/lib/rpm)) {
	mkdir "$o->{prefix}/$_", 0755;
    }

    unless ($o->{isUpgrade}) {
	local *F;
	open F, "> $o->{prefix}/etc/hosts" or die "Failed to create etc/hosts: $!";
	print F "127.0.0.1		localhost localhost.localdomain\n";
    }

    pkgs::init_db($o->{prefix}, $o->{isUpgrade});
}

sub installPackages($$) {
    my ($o, $packages) = @_;
    my $toInstall = [ grep { $_->{selected} } values %$packages ];
    pkgs::install($o->{prefix}, $o->{method}, $toInstall, $o->{isUpgrade}, 0);
}

sub afterInstallPackages($) {
    my ($o) = @_;

    unless ($o->{isUpgrade}) {
        keyboard::write($o->{prefix}, $o->{keyboard});
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

sub setRootPassword($) {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $pw = $o->{default}->{rootPassword};
    $pw = crypt_($pw);

    my $f = "$p/etc/passwd";
    my @lines = cat_($f, "failed to open file $f");

    local *F;
    open F, "> $f" or die "failed to write file $f: $!\n";
    foreach (@lines) {
	s/^root:.*?:/root:$pw:/;
	print F $_;
    }
}

sub addUser($) {
    my ($o) = @_;
    my %u = %{$o->{default}->{user}};
    my $p = $o->{prefix};

    my $new_uid;
    #my @uids = map { (split)[2] } cat__("$p/etc/passwd");
    #for ($new_uid = 500; member($new_uid, @uids); $new_uid++) {}
    for ($new_uid = 500; getpwuid($new_uid); $new_uid++) {}

    my $new_gid;
    #my @gids = map { (split)[2] } cat__("$p/etc/group");
    #for ($new_gid = 500; member($new_gid, @gids); $new_gid++) {}
    for ($new_gid = 500; getgrgid($new_gid); $new_gid++) {}

    my $homedir = "$p/home/$u{name}";

    my $pw = crypt_($u{password});

    local *F;
    open F, ">> $p/etc/passwd" or die "can't append to passwd file: $!";
    print F "$u{name}:$pw:$new_uid:$new_gid:$u{realname}:/home/$u{name}:$u{shell}\n";
	    
    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$u{name}::$new_gid:\n";

    eval { commands::cp("-f", "$p/etc/skel", $homedir) }; $@ and log::l("copying of skel failed: $@"), mkdir($homedir, 0750);
    commands::chown_("-r", "$new_uid.$new_gid", $homedir);
}

sub createBootdisk($) {
    lilo::mkbootdisk($o->{prefix}, versionString()) if $o->{default}->{mkbootdisk};
}

sub setupBootloader($) {
    my ($o) = @_;
    my $versionString = versionString();
    lilo::install($o->{prefix}, $o->{hds}, $o->{fstab}, $versionString, $o->{default}->{bootloader});
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
