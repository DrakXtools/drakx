package install_steps;

use diagnostics;
use strict;

use common qw(:file :system);
use lang;
use keyboard;
use pkgs;
use cpio;
use log;
use fsedit;
use commands;
use smp;


1;


sub new($$) {
    my ($type, $o) = @_;

    bless $o, ref $type || $type;
}

sub selectInstallOrUpgrade($) {
    my ($o) = @_;
    $o->{isUpgrade} || $o->{default}->{isUpgrade} || 0;
}
sub selectInstallClass($) {
    my ($o) = @_;
    $o->{installClass} || $o->{default}->{installClass} || 'Custom';
}
sub setupSCSIInterfaces {
    die "TODO";
}

sub doPartitionDisks($$$) {
    my ($o, $hds) = @_;
    fsedit::auto_allocate($hds, $o->{partitions});
}

sub choosePackages($$$) {
    my ($o, $packages, $comps) = @_;

    foreach ('base', @{$o->{comps}}) {
	$comps->{$_}->{selected} = 1;
	foreach (@{$_->{packages}}) { $_->{selected} = 1; }
    }
    foreach (@{$o->{packages}}) { $_->{selected} = 1; }

    smp::detect() and $packages->{"kernel-smp"}->{selected} = 1;
}

sub beforeInstallPackages($$) {
    my ($o, $fstab) = @_;

    $o->{method}->prepareMedia($fstab);

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

sub afterInstallPackages($$) {
    my ($o, $keymap) = @_;

    unless ($o->{isUpgrade}) {
        keyboard::write($o->{prefix}, $keymap);
        lang::write($o->{prefix});
    }
    #  why not? 
    sync(); sync();

#    configPCMCIA($o->{rootPath}, $o->{pcmcia});
}

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

    local *F;
    open F, ">> $p/etc/passwd" or die "can't append to passwd file: $!";
    print F "$o->{user}->{name}:$pw:$new_uid:$new_gid:$o->{user}->{realname}:/home/$o->{user}->{name}:$o->{user}->{shell}\n";
	    
    open F, ">> $p/etc/group" or die "can't append to group file: $!";
    print F "$o->{user}->{name}::$new_gid:\n";

    eval { commands::cp("-f", "$p/etc/skel", $homedir) }; $@ and log::l("copying of skel failed: $@"), mkdir($homedir, 0750);
    commands::chown_("-r", "$new_uid.$new_gid", $homedir);
}

sub setRootPassword($$) {
    my ($o) = @_;
    my $p = $o->{prefix};
    my $pw = $o->{rootPassword};
    $pw = crypt_($pw);

    my @lines = cat_("$p/etc/passwd", 'die');
    local *F;
    open F, "> $p/etc/passwd" or die "can't write in passwd: $!\n";
    foreach (@lines) {
	s/^root:.*?:/root:$pw:/;
	print F $_;
    }
}


sub setupXfree {

    if (rpmdbOpen(prefix, &db, O_RDWR | O_CREAT, 0644)) {
	 errorWindow(_("Fatal error reopening RPM database"));
	 return INST_ERROR;
    }
    log::l("reopened rpm database");
    
    sprintf(path, "%s/tmp/SERVER", prefix);
    if ((fd = open(path, O_RDONLY)) < 0) {
	 log::l("failed to open %s: %s", path, strerror(errno));
	 return INST_ERROR;
    }
 
    buf[0] = '\0';
    read(fd, buf, sizeof(buf));
    close(fd);
    chptr = buf;
    while (chptr < (buf + sizeof(buf) - 1) && *chptr && *chptr != ' ')
	 chptr++;

    if (chptr >= (buf + sizeof(buf) - 1) || *chptr != ' ') {
	 log::l("couldn't find ' ' in %s", path);
	 return INST_ERROR;
    }

    *chptr = '\0';
    strcpy(server, "XFree86-");
    strcat(server, buf);

    log::l("I will install the %s package", server);

    for (i = 0; i < psp->numPackages; i++) {
	 if (!strcmp(psp->packages[i]->name, server)) {
	     log::l("\tfound package: %s", psp->packages[i]->name);
	     swOpen(1, psp->packages[i]->size);
	     trans = rpmtransCreateSet(db, prefix);
	     rpmtransAddPackage(trans, psp->packages[i]->h, NULL,
				psp->packages[i], 0, NULL);
	     
	     cbi.method = method;
	     cbi.upgrade = 0;
	     
	     rpmRunTransactions(trans, swCallback, &cbi, NULL, &probs, 0, 
				 0xffffffff);
	     
	     swClose();
	     break;
	 }
    }

    # this handles kickstart and normal/expert modes 
    if ((rc=xfree86Config(prefix, "--continue")))
	 return INST_ERROR;

    # done with proc now 
    umount(procPath);

    rpmdbClose(db);

    log::l("rpm database closed");

    return INST_OKAY;
}

sub exitInstall {}
