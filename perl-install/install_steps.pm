package install_steps;

use diagnostics;
use strict;

use lang;
use keyboard;
use pkgs;
use cpio;
use log;
use fsedit;



1;


sub new($) {
    my ($type, $I) = @_;

    bless $I, ref $type || $type;
}


sub doPartitionDisks($$$) {
    my ($I, $hds) = @_;
    fsedit::auto_allocate($hds, $I->{partitions});
}

sub choosePackages($$$$) {
    my ($I, $packages, $comps, $isUpgrade) = @_;

    foreach ('base', @{$I->{comps}}) {
	$comps->{$_}->{selected} = 1;
	foreach (@{$_->{packages}}) { $_->{selected} = 1; }
    }
    foreach (@{$I->{packages}}) { $_->{selected} = 1; }

    smp::detect() and $packages->{"kernel-smp"}->{selected} = 1;
}

sub beforeInstallPackages($$$) {
    my ($I, $method, $fstab, $isUpgrade) = @_;

    $method->prepareMedia($fstab);

    foreach (qw(dev etc home mnt tmp var var/tmp var/lib var/lib/rpm)) {
	mkdir "$prefix/$_", 0755;
    }

    unless ($isUpgrade) {
	local *F;
	open F, "> $prefix/etc/hosts" or die "Failed to create etc/hosts: $!";
	print F "127.0.0.1		localhost localhost.localdomain\n";
    }
}

sub installPackages($$$$$) {
    my ($I, $prefix, $method, $packages, $isUpgrade) = @_;

    pkgs::install($prefix, $method, $packages, $isUpgrade, 0);
}

sub afterInstallPackages($$$$) {
    my ($prefix, $keymap, $isUpgrade) = @_;

    unless ($isUpgrade) {
        keyboard::write($prefix, $keymap);
        lang::write($prefix);
    }
    #  why not? 
    sync(); sync();

#    configPCMCIA($o->{rootPath}, $o->{pcmcia});
}

sub addUser($$) {
    my ($I, $prefix) = @_;

    my $new_uid;
    #my @uids = map { (split)[2] } cat__("$prefix/etc/passwd");
    #for ($new_uid = 500; member($new_uid, @uids); $new_uid++) {}
    for ($new_uid = 500; getpwuid($new_uid); $new_uid++) {}

    my $new_gid;
    #my @gids = map { (split)[2] } cat__("$prefix/etc/group");
    #for ($new_gid = 500; member($new_gid, @gids); $new_gid++) {}
    for ($new_gid = 500; getgrgid($new_gid); $new_gid++) {}

    my $homedir = "$prefix/home/$default->{user}->{name}";

    my $pw = crypt_($default->{user}->{password});

    unless ($testing) {
	{
	    local *F;
	    open F, ">> $prefix/etc/passwd" or die "can't append to passwd file: $!";
	    print F "$default->{user}->{name}:$pw:$new_uid:$new_gid:$default->{user}->{realname}:/home/$default->{user}->{name}:$default->{user}->{shell}\n";
	    
	    open F, ">> $prefix/etc/group" or die "can't append to group file: $!";
	    print F "$default->{user}->{name}::$new_gid:\n";
	}
	eval { commands::cp("-f", "$prefix/etc/skel", $homedir) }; $@ and log::l("copying of skel failed: $@"), mkdir($homedir, 0750);
	commands::chown_("-r", "$new_uid.$new_gid", $homedir);
    }
}

sub setRootPassword($$) {
    my ($I, $prefix) = @_;

    my $pw = $default->{rootPassword};
    $pw = crypt_($pw);

    my @lines = cat_("$prefix/etc/passwd", 'die');
    local *F;
    open F, "> $prefix/etc/passwd" or die "can't write in passwd: $!\n";
    foreach (@lines) {
	s/^root:.*?:/root:$pw:/;
	print F $_;
    }
}


sub setupXfree {
#    my ($method, $prefix, $psp) = @_;
#    int fd, i;
#    char buf[200], * chptr;
#    char server[50];
#    int rc;
#    char * path;
#    char * procPath;
#    rpmdb db;
#    rpmTransactionSet trans;
#    struct callbackInfo cbi;
#    rpmProblemSet probs;
#
#    if (rpmdbOpen(prefix, &db, O_RDWR | O_CREAT, 0644)) {
#	 errorWindow(_("Fatal error reopening RPM database"));
#	 return INST_ERROR;
#    }
#    log::l("reopened rpm database");
#
#    path = alloca(strlen(prefix) + 200);
#    procPath = alloca(strlen(prefix) + 50);
#    sprintf(path, "%s/usr/X11R6/bin/Xconfigurator", prefix);
#
#    # This is a cheap trick to see if our X component was installed 
#    if (access(path, X_OK)) {
#	 log::l("%s cannot be run", path);
#	 return INST_OKAY;
#    }
#
#    # need proc to do pci probing 
#    sprintf(procPath, "%s/proc", prefix);
#    umount(procPath);
#    if ((rc = doMount("/proc", procPath, "proc", 0, 0))) {
#	 return INST_ERROR;
#    }
#
#    # this handles kickstart and normal/expert modes 
#    if ((rc=xfree86Config(prefix, "--pick")))
#	 return INST_ERROR;
#    
#    sprintf(path, "%s/tmp/SERVER", prefix);
#    if ((fd = open(path, O_RDONLY)) < 0) {
#	 log::l("failed to open %s: %s", path, strerror(errno));
#	 return INST_ERROR;
#    }
# 
#    buf[0] = '\0';
#    read(fd, buf, sizeof(buf));
#    close(fd);
#    chptr = buf;
#    while (chptr < (buf + sizeof(buf) - 1) && *chptr && *chptr != ' ')
#	 chptr++;
#
#    if (chptr >= (buf + sizeof(buf) - 1) || *chptr != ' ') {
#	 log::l("couldn't find ' ' in %s", path);
#	 return INST_ERROR;
#    }
#
#    *chptr = '\0';
#    strcpy(server, "XFree86-");
#    strcat(server, buf);
#
#    log::l("I will install the %s package", server);
#
#    for (i = 0; i < psp->numPackages; i++) {
#	 if (!strcmp(psp->packages[i]->name, server)) {
#	     log::l("\tfound package: %s", psp->packages[i]->name);
#	     swOpen(1, psp->packages[i]->size);
#	     trans = rpmtransCreateSet(db, prefix);
#	     rpmtransAddPackage(trans, psp->packages[i]->h, NULL,
#				psp->packages[i], 0, NULL);
#	     
#	     cbi.method = method;
#	     cbi.upgrade = 0;
#	     
#	     rpmRunTransactions(trans, swCallback, &cbi, NULL, &probs, 0, 
#				 0xffffffff);
#	     
#	     swClose();
#	     break;
#	 }
#    }
#
#    # this handles kickstart and normal/expert modes 
#    if ((rc=xfree86Config(prefix, "--continue")))
#	 return INST_ERROR;
#
#    # done with proc now 
#    umount(procPath);
#
#    rpmdbClose(db);
#
#    log::l("rpm database closed");
#
#    return INST_OKAY;
}

