package install_any; # $Id$

use strict;

use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK $boot_medium $current_medium $asked_medium @advertising_images);

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    all => [ qw(getNextStep spawnShell addToBeDone) ],
);
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-######################################################################################
#- misc imports
#-######################################################################################
use MDK::Common::System;
use common;
use run_program;
use fs::type;
use partition_table;
use devices;
use fsedit;
use modules;
use detect_devices;
use lang;
use any;
use log;

#- boot medium (the first medium to take into account).
$boot_medium = 1;
$current_medium = $boot_medium;
$asked_medium = $boot_medium;

#-######################################################################################
#- Media change variables&functions
#-######################################################################################
my $postinstall_rpms = '';
my $cdrom;
my %iso_images;

sub mountCdrom {
    my ($mountpoint, $o_cdrom) = @_;
    $o_cdrom = $cdrom if !defined $o_cdrom;
    eval { fs::mount($o_cdrom, $mountpoint, "iso9660", 'readonly') };
}

sub useMedium($) {
    #- before ejecting the first CD, there are some files to copy!
    #- does nothing if the function has already been called.
    $_[0] > 1 and method_allows_medium_change($::o->{method}) and setup_postinstall_rpms($::prefix, $::o->{packages});

    $asked_medium eq $_[0] or log::l("selecting new medium '$_[0]'");
    $asked_medium = $_[0];
}
sub changeMedium($$) {
    my ($method, $medium_name) = @_;
    log::l("change to medium $medium_name for method $method (refused by default)");
    0;
}
sub relGetFile($) {
    local $_ = $_[0];
    if (my ($arch) = m|\.([^\.]*)\.rpm$|) {
	$_ = "$::o->{packages}{mediums}{$asked_medium}{rpmsdir}/$_";
	s/%{ARCH}/$arch/g;
	s,^/+,,g;
    }
    $_;
}
sub askChangeMedium($$) {
    my ($method, $medium_name) = @_;
    my $allow;
    do {
	local $::o->{method} = $method = 'cdrom' if $medium_name =~ /^\d+s$/; #- Suppl CD
	eval { $allow = changeMedium($method, $medium_name) };
    } while $@; #- really it is not allowed to die in changeMedium!!! or install will cores with rpmlib!!!
    log::l($allow ? "accepting medium $medium_name" : "refusing medium $medium_name");
    $allow;
}

sub method_is_from_ISO_images($) {
    my ($method) = @_;
    $method eq "disk-iso" || $method eq "nfs-iso";
}
sub method_allows_medium_change($) {
    my ($method) = @_;
    $method eq "cdrom" || method_is_from_ISO_images($method);
}

sub look_for_ISO_images() {
    $iso_images{media} = [];

    ($iso_images{loopdev}, $iso_images{mountpoint}) = cat_("/proc/mounts") =~ m|(/dev/loop\d+)\s+(/tmp/image) iso9660| or return;

    my $get_iso_ids = sub {
	my ($F) = @_;
	my ($vol_id, $app_id) = c::get_iso_volume_ids(fileno $F);
	#- the ISO volume names must end in -Disc\d+
	my ($cd_set) = $vol_id =~ /^(.*)-Disc\d+$/;
	$cd_set && { cd_set => $cd_set, app_id => $app_id };
    };

    sysopen(my $F, $iso_images{loopdev}, 0) or return;
    put_in_hash(\%iso_images, $get_iso_ids->($F));

    my $iso_dir = $ENV{ISOPATH};
    #- strip old root and remove iso file from path if present
    $iso_dir =~ s!^/sysroot!!; $iso_dir =~ s![^/]*\.iso$!!;

    foreach my $iso_file (glob("$iso_dir/*.iso")) {
	my $iso_dev = devices::set_loop($iso_file) or return;
	if (sysopen($F, $iso_dev, 0)) {
	    my $iso_ids = $get_iso_ids->($F);
	    push @{$iso_images{media}}, { file => $iso_file, %$iso_ids } if $iso_ids;
	    close($F); #- needed to delete loop device
	}
	devices::del_loop($iso_dev);
    }
    1;
}

sub find_ISO_image_labelled($) {
    %iso_images or look_for_ISO_images() or return;
    my ($iso_label) = @_;
    find { $_->{app_id} eq $iso_label && $_->{cd_set} eq $iso_images{cd_set} } @{$iso_images{media}};
}

sub changeIso($) {
    my ($iso_label) = @_;
    my $iso_info = find_ISO_image_labelled($iso_label) or return;

    eval { fs::umount($iso_images{mountpoint}) };
    $@ and warnAboutFilesStillOpen();
    devices::del_loop($iso_images{loopdev});

    $iso_images{loopdev} = devices::set_loop($iso_info->{file});
    eval { 
	fs::mount($iso_images{loopdev}, $iso_images{mountpoint}, "iso9660", 'readonly');
	log::l("using ISO image '$iso_label'");
	1;
    }
}

sub errorOpeningFile($) {
    my ($file) = @_;
    $file eq 'XXX' and return; #- special case to force closing file after rpmlib transaction.
    $current_medium eq $asked_medium and log::l("errorOpeningFile $file"), return; #- nothing to do in such case.
    $::o->{packages}{mediums}{$asked_medium}{selected} or return; #- not selected means no need to worry about.
    my $current_method = $::o->{packages}{mediums}{$asked_medium}{method} || $::o->{method};

    my $max = 32; #- always refuse after $max tries.
    if ($current_method eq "cdrom") {
	cat_("/proc/mounts") =~ m,(/(?:dev|tmp)/\S+)\s+(/mnt/cdrom|/tmp/image),
	    and ($cdrom, my $mountpoint) = ($1, $2);
	return unless $cdrom;
	ejectCdrom($cdrom, $mountpoint);
	while ($max > 0 && askChangeMedium($current_method, $asked_medium)) {
	    $current_medium = $asked_medium;
	    mountCdrom("/tmp/image");
	    my $getFile = getFile($file); 
	    $getFile && @advertising_images and copy_advertising($::o);
	    $getFile and return $getFile;
	    $current_medium = 'unknown'; #- don't know what CD is inserted now.
	    ejectCdrom($cdrom, $mountpoint);
	    --$max;
	}
    } else {
	while ($max > 0 && askChangeMedium($current_method, $asked_medium)) {
	    $current_medium = $asked_medium;
	    my $getFile = getFile($file); $getFile and return $getFile;
	    $current_medium = 'unknown'; #- don't know what CD image has been copied.
	    --$max;
	}
    }

    #- Don't unselect supplementary CDs.
    return if $asked_medium =~ /^\d+s$/;

    #- keep in mind the asked medium has been refused on this way.
    #- this means it is no more selected.
    $::o->{packages}{mediums}{$asked_medium}{selected} = undef;

    #- on cancel, we can expect the current medium to be undefined too,
    #- this enables remounting if selecting a package back.
    $current_medium = 'unknown';

    return;
}
sub getFile {
    my ($f, $o_method, $o_altroot) = @_;
    my $current_method = ($asked_medium ? $::o->{packages}{mediums}{$asked_medium}{method} : '') || $::o->{method};
    log::l("getFile $f:$o_method ($asked_medium:$current_method)");
    my $rel = relGetFile($f);
    do {
	if ($f =~ m|^http://|) {
	    require http;
	    http::getFile($f);
	} elsif ($o_method =~ /crypto|update/i) {
	    require crypto;
	    crypto::getFile($f);
	} elsif ($current_method eq "ftp") {
	    require ftp;
	    ftp::getFile($rel, @{ $::o->{packages}{mediums}{$asked_medium}{ftp_prefix} || [] });
	} elsif ($current_method eq "http") {
	    require http;
	    http::getFile(($ENV{URLPREFIX} || $o_altroot) . "/$rel");
	} else {
	    #- try to open the file, but examine if it is present in the repository,
	    #- this allows handling changing a media when some of the files on the
	    #- first CD have been copied to other to avoid media change...
	    my $f2 = "$postinstall_rpms/$f";
	    $o_altroot ||= '/tmp/image';
	    $f2 = "$o_altroot/$rel" if $rel !~ m,^/, && (!$postinstall_rpms || !-e $f2);
	    #- $f2 = "/$rel" if !$::o->{packages}{mediums}{$asked_medium}{rpmsdir} && !-e $f2; #- not a relative path, should not be necessary with new media layout
	    my $F; open($F, $f2) && $F or do { $f2 !~ /XXX/ and log::l("Can't open $f2: $!"); undef }
	}
    } || errorOpeningFile($f);
}
sub getAndSaveFile {
    my ($file, $local) = @_ == 1 ? ("install/stage2/live$_[0]", $_[0]) : @_;
    local $/ = \ (16 * 1024);
    my $f = ref($file) ? $file : getFile($file) or return;
    open(my $F, ">$local") or log::l("getAndSaveFile(opening $local): $!"), return;
    local $_;
    while (<$f>) { syswrite($F, $_) or die("getAndSaveFile($local): $!") }
    1;
}


#-######################################################################################
#- Post installation RPMS from cdrom only, functions
#-######################################################################################
sub setup_postinstall_rpms($$) {
    my ($prefix, $packages) = @_;

    $postinstall_rpms and return;
    $postinstall_rpms = "$prefix/usr/postinstall-rpm";

    require pkgs;

    log::l("postinstall rpms directory set to $postinstall_rpms");
    clean_postinstall_rpms(); #- make sure in case of previous upgrade problem.
    mkdir_p($postinstall_rpms);

    my %toCopy;
    #- compute closure of package that may be copied, use INSTALL category
    #- in rpmsrate.
    $packages->{rpmdb} ||= pkgs::rpmDbOpen($prefix);
    foreach (@{$packages->{needToCopy} || []}) {
	my $p = pkgs::packageByName($packages, $_) or next;
	pkgs::selectPackage($packages, $p, 0, \%toCopy);
    }
    delete $packages->{rpmdb};

    my @toCopy = grep { $_ && !$_->flag_selected } map { $packages->{depslist}[$_] } keys %toCopy;

    #- extract headers of package, this is necessary for getting
    #- the complete filename of each package.
    #- copy the package files in the postinstall RPMS directory.
    #- last arg is default medium '' known as the CD#1.
    #- cp_af doesn't handle correctly a missing file.
    eval { cp_af((grep { -r $_ } map { "/tmp/image/" . relGetFile($_->filename) } @toCopy), $postinstall_rpms) };

    log::l("copying Auto Install Floppy");
    getAndSaveInstallFloppies($::o, $postinstall_rpms, 'auto_install');
}

sub clean_postinstall_rpms() {
    $postinstall_rpms and -d $postinstall_rpms and rm_rf($postinstall_rpms);
}


#-######################################################################################
#- Functions
#-######################################################################################
sub getNextStep {
    my ($o) = @_;
    find { !$o->{steps}{$_}{done} && $o->{steps}{$_}{reachable} } @{$o->{orderedSteps}}
}

sub spawnShell() {
    return if $::o->{localInstall} || $::testing;

    if (my $shellpid = fork()) {
        output('/var/run/drakx_shell.pid', $shellpid);
        return;
    }

    $ENV{DISPLAY} ||= ":0"; #- why not :pp

    local *F;
    sysopen F, "/dev/tty2", 2 or log::l("cannot open /dev/tty2 -- no shell will be provided: $!"), goto cant_spawn;

    open STDIN, "<&F" or goto cant_spawn;
    open STDOUT, ">&F" or goto cant_spawn;
    open STDERR, ">&F" or goto cant_spawn;
    close F;

    print any::drakx_version(), "\n";

    c::setsid();

    ioctl(STDIN, c::TIOCSCTTY(), 0) or warn "could not set new controlling tty: $!";

    my @args; -e '/etc/bashrc' and @args = qw(--rcfile /etc/bashrc);
    foreach (qw(/bin/bash /usr/bin/busybox /bin/sh)) {
        -x $_ or next;
        my $program_name = /busybox/ ? "/bin/sh" : $_;  #- since perl_checker is too dumb
        exec { $_ } $program_name, @args or log::l("exec of $_ failed: $!");
    }

    log::l("cannot open any shell");
cant_spawn:
    c::_exit(1);
}

sub getAvailableSpace {
    my ($o) = @_;

    #- make sure of this place to be available for installation, this could help a lot.
    #- currently doing a very small install use 36Mb of postinstall-rpm, but installing
    #- these packages may eat up to 90Mb (of course not all the server may be installed!).
    #- 65mb may be a good choice to avoid almost all problem of insuficient space left...
    my $minAvailableSize = 65 * sqr(1024);

    my $n = !$::testing && getAvailableSpace_mounted($o->{prefix}) || 
            getAvailableSpace_raw($o->{fstab}) * 512 / 1.07;
    $n - max(0.1 * $n, $minAvailableSize);
}

sub getAvailableSpace_mounted {
    my ($prefix) = @_;
    my $dir = -d "$prefix/usr" ? "$prefix/usr" : $prefix;
    my (undef, $free) = MDK::Common::System::df($dir) or return;
    log::l("getAvailableSpace_mounted $free KB");
    $free * 1024 || 1;
}
sub getAvailableSpace_raw {
    my ($fstab) = @_;

    do { $_->{mntpoint} eq '/usr' and return $_->{size} } foreach @$fstab;
    do { $_->{mntpoint} eq '/'    and return $_->{size} } foreach @$fstab;

    if ($::testing) {
	my $nb = 450;
	log::l("taking ${nb}MB for testing");
	return $nb << 11;
    }
    die "missing root partition";
}

sub preConfigureTimezone {
    my ($o) = @_;
    require timezone;
   
    #- can't be done in install cuz' timeconfig %post creates funny things
    add2hash($o->{timezone}, timezone::read()) if $o->{isUpgrade};

    $o->{timezone}{timezone} ||= timezone::bestTimezone($o->{locale}{country});

    my $utc = every { !isFat_or_NTFS($_) } @{$o->{fstab}};
    my $ntp = timezone::ntp_server();
    add2hash_($o->{timezone}, { UTC => $utc, ntp => $ntp });
}

sub deselectFoundMedia {
    my ($o, $hdlists) = @_;
    my $l = $o->ask_many_from_list('',
N("The following installation media have been found.
If you want to skip some of them, you can unselect them now."),
	{
	    list => $hdlists,
	    value => sub { 1 },
	    label => sub { $_[0][3] },
	},
    );
    log::l("keeping media " . join ',', map { $_->[1] } @$l);
    @$l;
}

sub ask_if_suppl_media {
    my ($o) = @_;
    our $suppl_already_asked;
    my $msg = $suppl_already_asked
      ? N("Do you have further supplementary media?")
      : formatAlaTeX(
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
	    N("The following media have been found and will be used during install: %s.


Do you have a supplementary installation media to configure?",
	    join ", ", uniq(map { $_->{descr} } values %{$o->{packages}{mediums}})));
    my $suppl = $o->ask_from_list_(
	'', $msg, [ N_("None"), N_("CD-ROM"), N_("Network (http)"), N_("Network (ftp)") ], 'None'
    );
    $suppl_already_asked = 1;
    return $suppl;
}

sub selectSupplMedia {
    my ($o, $suppl_method) = @_;
    #- ask whether there are supplementary media
    my $prev_asked_medium = $asked_medium;
    if ($suppl_method && !$o->{isUpgrade}
	&& (my $suppl = ask_if_suppl_media($o)) ne 'None')
    {
	#- translate to method name
	$suppl_method = {
	    'CD-ROM' => 'cdrom',
	    'Network (http)' => 'http',
	    'Network (ftp)' => 'ftp',
	}->{$suppl};
	#- by convention, the media names for suppl. CDs match /^\d+s$/
	my $medium_name = $suppl_method eq 'cdrom'
	    ? (max(map { $_->{medium} =~ /^(\d+)s$/ ? $1 : 0 } values %{$o->{packages}{mediums}}) + 1) . "s"
	    : int(keys %{$o->{packages}{mediums}}) + 1;
	local $::isWizard = 0;
	#- configure network if needed
	if (!(our $asked) && !scalar keys %{$o->{intf}} && $suppl_method !~ /^(?:cdrom|disk)/) {
	    $asked = 1;
	    #- install basesystem now
	    $::o->do_pkgs->ensure_is_installed('basesystem', undef, 1);
	    #- from install_steps_interactive:
	    local $::expert = $::expert;
	    require network::netconnect;
	    network::netconnect::main($o->{prefix}, $o->{netcnx} ||= {}, $o, $o->{modules_conf}, $o->{netc}, $o->{mouse}, $o->{intf}, 0, 1);
	    require install_interactive;
	    install_interactive::upNetwork($o);
	}
	my $main_method = $o->{method};
	local $o->{method} = $suppl_method;
	if ($suppl_method eq 'cdrom') {
	    (my $cdromdev) = detect_devices::cdroms();
	    $o->ask_warn('', N("No device found")), return 'error' if !$cdromdev;
	    $cdrom = $cdromdev->{device};
	    devices::make($cdrom);
	    ejectCdrom($cdrom);
	    if ($o->ask_okcancel('', N("Insert the CD"), 1)) {
		#- mount suppl CD in /mnt/cdrom to avoid umounting /tmp/image
		mountCdrom("/mnt/cdrom", $cdrom);
		log::l($@) if $@;
		useMedium($medium_name);

		#- probe for an hdlists file and then look for all hdlists listed herein
		eval { pkgs::psUsingHdlists($o, $suppl_method, "/mnt/cdrom/", $o->{packages}, $medium_name) };
		log::l("psUsingHdlists failed: $@") if $@;

		#- copy latest compssUsers.pl and rpmsrate somewhere locally
		getAndSaveFile("/mnt/cdrom/media/media_info/compssUsers.pl", "/tmp/compssUsers.pl");
		getAndSaveFile("/mnt/cdrom/media/media_info/rpmsrate", "/tmp/rpmsrate");

		#- umount supplementary CD. Will re-ask for it later
		getFile("XXX"); #- close still opened filehandles
		log::l("Umounting suppl. CD, back to medium 1");
		eval { fs::umount("/mnt/cdrom") };
		#- re-mount CD 1 if this was a cdrom install
		if ($main_method eq 'cdrom') {
		    eval { 
			my $dev = detect_devices::tryOpen($cdrom);	    
			ioctl($dev, c::CDROMEJECT(), 1);
		    };
		    $o->ask_warn('', N("Insert the CD 1 again"));
		    mountCdrom("/tmp/image", $cdrom);
		    log::l($@) if $@;
		    $asked_medium = 1;
		}
	    }
	} else {
	    my $url = $o->ask_from_entry('', N("URL of the mirror?")) or return '';
	    useMedium($medium_name);
	    require "$suppl_method.pm";
	    #- first, try to find an hdlists file
	    eval { pkgs::psUsingHdlists($o, $suppl_method, "$url/", $o->{packages}, $medium_name) };
	    if ($@) {
		log::l("psUsingHdlists failed: $@");
	    } else {
		#- copy latest compssUsers.pl and rpmsrate somewhere locally
		getAndSaveFile("$url/media/media_info/compssUsers.pl", "/tmp/compssUsers.pl");
		getAndSaveFile("$url/media/media_info/rpmsrate", "/tmp/rpmsrate");
		useMedium($prev_asked_medium); #- back to main medium
		return $suppl_method;
	    }
	    #- then probe for an hdlist.cz
	    my $f = eval {
		if ($suppl_method eq 'http') {
		    http::getFile("$url/media_info/hdlist.cz");
		} elsif ($suppl_method eq 'ftp') {
		    my ($login, $pass, $host, $prefix) = $url =~ m!^ftp://(?:(.*?)(?::(.*?))?@)?([^/]+)/(.*)!;
		    ftp::getFile("media_info/hdlist.cz", $host, $prefix, $login, $pass);
		} else { undef }
	    };
	    if (!defined $f) {
		log::l($@) if $@;
		$o->ask_warn('', N("Can't find hdlist file on this mirror"));
		useMedium($prev_asked_medium);
		return 'error';
	    }
	    my $supplmedium = pkgs::psUsingHdlist(
		$o->{prefix},
		$suppl_method,
		$o->{packages},
		"hdlist$medium_name.cz", #- hdlist
		$medium_name,
		'', #- rpmsdir
		"Supplementary media $medium_name", #- description
		1, # selected
		$f,
	    );
	    close $f;
	    if ($supplmedium) {
		log::l("read suppl hdlist (via $suppl_method)");
		$supplmedium->{prefix} = $url; #- for install_urpmi
		if ($suppl_method eq 'ftp') {
		    $url =~ m!^ftp://(?:(.*?)(?::(.*?))?@)?([^/]+)/(.*)!
			and $supplmedium->{ftp_prefix} = [ $3, $4, $1, $2 ]; #- for getFile
		}
		$supplmedium->{selected} = 1;
		$supplmedium->{method} = $suppl_method;
		$supplmedium->{with_hdlist} = 'media_info/hdlist.cz'; #- for install_urpmi
	    } else {
		log::l("no suppl hdlist");
	    }
	}
    } else {
	$suppl_method = '';
    }
    useMedium($prev_asked_medium); #- back to main medium
    return $suppl_method;
}

sub setPackages {
    my ($o, $rebuild_needed) = @_;

    require pkgs;
    if (!$o->{packages} || is_empty_array_ref($o->{packages}{depslist})) {
	($o->{packages}, my $suppl_method) = pkgs::psUsingHdlists($o, $o->{method});

	1 while
	$suppl_method = $o->selectSupplMedia($suppl_method);

	#- open rpm db according to right mode needed.
	$o->{packages}{rpmdb} ||= pkgs::rpmDbOpen($o->{prefix}, $rebuild_needed);

	#- always try to select basic kernel (else on upgrade, kernel will never be updated provided a kernel is already
	#- installed and provides what is necessary).
	pkgs::selectPackage($o->{packages},
			    pkgs::bestKernelPackage($o->{packages}) || die("missing kernel package"), 1);

	pkgs::selectPackage($o->{packages},
			    pkgs::packageByName($o->{packages}, 'basesystem') || die("missing basesystem package"), 1);

	#- must be done after getProvides
	#- if there is a supplementary media, the rpmsrate/compssUsers are overridable
	pkgs::read_rpmsrate(
	    $o->{packages},
	    getFile(-e "/tmp/rpmsrate" ? "/tmp/rpmsrate" : "media/media_info/rpmsrate")
	);
	($o->{compssUsers}, $o->{gtk_display_compssUsers}) = pkgs::readCompssUsers(
	    $o->{meta_class},
	    -e '/tmp/compssUsers.pl' ? '/tmp/compssUsers.pl' : 'media/media_info/compssUsers.pl'
	);

	#- preselect default_packages and compssUsers selected.
	setDefaultPackages($o);
	pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};

    } else {
	#- this has to be done to make sure necessary files for urpmi are
	#- present.
	pkgs::psUpdateHdlistsDeps($o->{prefix}, $o->{method}, $o->{packages});

	#- open rpm db (always without rebuilding db, it should be false at this point).
	$o->{packages}{rpmdb} ||= pkgs::rpmDbOpen($o->{prefix});
    }
}

sub setDefaultPackages {
    my ($o, $b_clean) = @_;

    if ($b_clean) {
	delete $o->{default_packages}; #- clean modified variables.
    }

    push @{$o->{default_packages}}, "brltty" if cat_("/proc/cmdline") =~ /brltty=/;
    push @{$o->{default_packages}}, "nfs-utils-clients" if $o->{method} eq "nfs";
    push @{$o->{default_packages}}, "numlock" if $o->{miscellaneous}{numlock};
    push @{$o->{default_packages}}, "mdadm" if !is_empty_array_ref($o->{all_hds}{raids});
    push @{$o->{default_packages}}, "lvm2" if !is_empty_array_ref($o->{all_hds}{lvms});
    push @{$o->{default_packages}}, "alsa", "alsa-utils" if any { $o->{modules_conf}->get_alias("sound-slot-$_") =~ /^snd-/ } 0 .. 4;
    push @{$o->{default_packages}}, "grub" if isLoopback(fs::get::root($o->{fstab}));
    push @{$o->{default_packages}}, uniq(grep { $_ } map { fs::format::package_needed_for_partition_type($_) } @{$o->{fstab}});

    #- if no cleaning needed, populate by default, clean is used for second or more call to this function.
    unless ($b_clean) {
	if ($::auto_install && ($o->{rpmsrate_flags_chosen} || {})->{ALL}) {
	    $o->{rpmsrate_flags_chosen}{$_} = 1 foreach map { @{$_->{flags}} } @{$o->{compssUsers}};
	}
	if (!$o->{rpmsrate_flags_chosen} && !$o->{isUpgrade}) {
	    #- use default selection seen in compssUsers directly.
	    foreach (@{$o->{compssUsers}}) {
		$_->{selected} = $_->{default_selected} or next;
		$o->{rpmsrate_flags_chosen}{$_} = 1 foreach @{$_->{flags}};
	    }
	}
    }
    $o->{rpmsrate_flags_chosen}{uc($_)} = 1 foreach grep { modules::probe_category("multimedia/$_") } modules::sub_categories('multimedia');
    $o->{rpmsrate_flags_chosen}{uc($_)} = 1 foreach map { $_->{driver} =~ /Flag:(.*)/ } detect_devices::probeall();
    $o->{rpmsrate_flags_chosen}{SYSTEM} = 1;
    $o->{rpmsrate_flags_chosen}{DOCS} = !$o->{excludedocs};
    $o->{rpmsrate_flags_chosen}{UTF8} = $o->{locale}{utf8};
    $o->{rpmsrate_flags_chosen}{BURNER} = 1 if detect_devices::burners();
    $o->{rpmsrate_flags_chosen}{DVD} = 1 if detect_devices::dvdroms();
    $o->{rpmsrate_flags_chosen}{USB} = 1 if $o->{modules_conf}->get_probeall("usb-interface");
    $o->{rpmsrate_flags_chosen}{PCMCIA} = 1 if detect_devices::hasPCMCIA();
    $o->{rpmsrate_flags_chosen}{HIGH_SECURITY} = 1 if $o->{security} > 3;
    $o->{rpmsrate_flags_chosen}{BIGMEM} = 1 if !$::oem && availableRamMB() > 800 && arch() !~ /ia64|x86_64/;
    $o->{rpmsrate_flags_chosen}{SMP} = 1 if detect_devices::hasSMP();
    $o->{rpmsrate_flags_chosen}{CDCOM} = 1 if any { $_->{descr} =~ /commercial/i } values %{$o->{packages}{mediums}};
    $o->{rpmsrate_flags_chosen}{TV} = 1 if detect_devices::getTVcards();
    $o->{rpmsrate_flags_chosen}{'3D'} = 1 if 
      detect_devices::matching_desc__regexp('Matrox.* G[245][05]0') ||
      detect_devices::matching_desc__regexp('Rage X[CL]') ||
      detect_devices::matching_desc__regexp('3D Rage (?:LT|Pro)') ||
      detect_devices::matching_desc__regexp('Voodoo [35]') ||
      detect_devices::matching_desc__regexp('Voodoo Banshee') ||
      detect_devices::matching_desc__regexp('8281[05].* CGC') ||
      detect_devices::matching_desc__regexp('Rage 128') ||
      detect_devices::matching_desc__regexp('Radeon ') || #- all Radeon card are now 3D with 4.3.0
      detect_devices::matching_desc__regexp('[nN]Vidia.*T[nN]T2') || #- TNT2 cards
      detect_devices::matching_desc__regexp('[nN][vV]idia.*NV[56]') ||
      detect_devices::matching_desc__regexp('[nN][vV]idia.*Vanta') ||
      detect_devices::matching_desc__regexp('[nN][vV]idia.*[gG]e[fF]orce') || #- GeForce cards
      detect_devices::matching_desc__regexp('[nN][vV]idia.*NV1[15]') ||
      detect_devices::matching_desc__regexp('[nN][vV]idia.*Quadro');


    my @locale_pkgs = map { pkgs::packagesProviding($o->{packages}, 'locales-' . $_) } lang::langsLANGUAGE($o->{locale}{langs});
    unshift @{$o->{default_packages}}, uniq(map { $_->name } @locale_pkgs);

    foreach (lang::langsLANGUAGE($o->{locale}{langs})) {
	$o->{rpmsrate_flags_chosen}{qq(LOCALES"$_")} = 1;
    }
    $o->{rpmsrate_flags_chosen}{'CHARSET"' . lang::l2charset($o->{locale}{lang}) . '"'} = 1;
}

sub unselectMostPackages {
    my ($o) = @_;
    pkgs::unselectAllPackages($o->{packages});
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};
}

sub warnAboutNaughtyServers {
    my ($o) = @_;
    my @naughtyServers = pkgs::naughtyServers($o->{packages}) or return 1;
    my $r = $o->ask_from_list_('', 
formatAlaTeX(
             #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
             N("You have selected the following server(s): %s


These servers are activated by default. They don't have any known security
issues, but some new ones could be found. In that case, you must make sure
to upgrade as soon as possible.


Do you really want to install these servers?
", join(", ", @naughtyServers))), [ N_("Yes"), N_("No") ], 'Yes') or return;
    if ($r ne 'Yes') {
	log::l("unselecting naughty servers");
	pkgs::unselectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_)) foreach @naughtyServers;
    }
    1;
}

sub warnAboutRemovedPackages {
    my ($o, $packages) = @_;
    my @removedPackages = keys %{$packages->{state}{ask_remove} || {}} or return;
    if (!$o->ask_yesorno('', 
formatAlaTeX(
             #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
             N("The following packages will be removed to allow upgrading your system: %s


Do you really want to remove these packages?
", join(", ", @removedPackages))), 1)) {
	$packages->{state}{ask_remove} = {};
    }
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub set_authentication {
    my ($o) = @_;

    my $when_network_is_up = sub {
	my ($f) = @_;
	#- defer running xxx - no network yet
	addToBeDone {
	    require install_steps;
	    install_steps::upNetwork($o, 'pppAvoided');
	    $f->();
	} 'configureNetwork';
    };
    require authentication;
    authentication::set($o, $o->{netc}, $o->{authentication} ||= {}, $when_network_is_up);
}

sub killCardServices() {
    my $pid = chomp_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

sub unlockCdrom() {
    my $cdrom = cat_("/proc/mounts") =~ m!(/(?:dev|tmp)/\S+)\s+(?:/mnt/cdrom|/tmp/image)! && $1 or return;
    eval { ioctl(detect_devices::tryOpen($cdrom), c::CDROM_LOCKDOOR(), 0) };
}

sub ejectCdrom {
    my ($o_cdrom, $o_mountpoint) = @_;
    getFile("XXX"); #- close still opened filehandle
    my $cdrom = $o_cdrom || cat_("/proc/mounts") =~ m!(/(?:dev|tmp)/\S+)\s+(/mnt/cdrom|/tmp/image)! && $1 or return;
    $o_mountpoint ||= $2 || '/tmp/image';

    #- umount BEFORE opening the cdrom device otherwise the umount will
    #- D state if the cdrom is already removed
    eval { fs::umount($o_mountpoint) };
    $@ and warnAboutFilesStillOpen();
    eval { 
	my $dev = detect_devices::tryOpen($cdrom);
	ioctl($dev, c::CDROMEJECT(), 1) if ioctl($dev, c::CDROM_DRIVE_STATUS(), 0) == c::CDS_DISC_OK();
    };
}

sub warnAboutFilesStillOpen() {
    log::l("files still open: ", readlink($_)) foreach map { glob_("$_/fd/*") } glob_("/proc/*");
  }

sub setupFB {
    my ($o, $vga) = @_;

    $vga ||= 785; #- assume at least 640x480x16.

    require bootloader;
    foreach (@{$o->{bootloader}{entries}}) {
	$_->{vga} = $vga if $_->{vga}; #- replace existing vga= with
    }
    bootloader::install($o->{bootloader}, $o->{all_hds});
    1;
}

sub install_urpmi {
    my ($prefix, $method, $packages, $mediums) = @_;

    #- rare case where urpmi cannot be installed (no hd install path).
    $method eq 'disk' && !any::hdInstallPath() and return;

    #- clean to avoid opening twice the rpm db.
    delete $packages->{rpmdb};

    #- import pubkey in rpmdb.
    my $db = pkgs::rpmDbOpenForInstall($prefix);
    $packages->parse_pubkeys(db => $db);
    foreach my $medium (values %$mediums) {
	$packages->import_needed_pubkeys($medium->{pubkey}, db => $db, callback => sub {
					     my (undef, undef, $_k, $id, $imported) = @_;
					     if ($id) {
						 log::l(($imported ? "imported" : "found") . " key=$id for medium $medium->{descr}");
						 $medium->{key_ids}{$id} = undef;
					     }
					 });
    }

    my @cfg;
    foreach (sort { $a->{medium} <=> $b->{medium} } values %$mediums) {
	my $name = $_->{fakemedium};
	if ($_->{ignored} || $_->{selected}) {
	    my $curmethod = $_->{method} || $::o->{method};
	    my $dir = ($_->{prefix} || ${{ nfs => "file://mnt/nfs", 
					   disk => "file:/" . any::hdInstallPath(),
					   ftp => $ENV{URLPREFIX},
					   http => $ENV{URLPREFIX},
					   cdrom => "removable://mnt/cdrom" }}{$curmethod} ||
		       #- for live_update or live_install script.
		       readlink("/tmp/image/media") =~ m,^(/.*)/media/*$, && "removable:/$1") . "/$_->{rpmsdir}";
	    #- use list file only if visible password or macro.
	    my $need_list = $dir =~ m,^(?:[^:]*://[^/:\@]*:[^/:\@]+\@|.*%{),; #- }

	    #- build a list file if needed.
	    if ($need_list) {
		my $mask = umask 077;
		open(my $LIST, ">$prefix/var/lib/urpmi/list.$name") or log::l("failed to write list.$name");
		umask $mask;

		#- build list file using internal data, synthesis file should exist.
		if ($_->{end} > $_->{start}) {
		    #- WARNING this method of build only works because synthesis (or hdlist)
		    #-         has been read.
		    foreach (@{$packages->{depslist}}[$_->{start} .. $_->{end}]) {
			my $arch = $_->arch;
			my $ldir = $dir;
			$ldir =~ s|/([^/]*)%{ARCH}|/./$1$arch|; $ldir =~ s|%{ARCH}|$arch|g;
			print $LIST "$ldir/" . $_->filename . "\n";
		    }
		} else {
		    #- need to use another method here to build list file.
		    open(my $F, "parsehdlist '$prefix/var/lib/urpmi/hdlist.$name.cz' |");
		    local $_; 
		    while (<$F>) {
                        my ($arch) = /\.([^\.]+)\.rpm$/;
			my $ldir = $dir;
			$ldir =~ s|/([^/]*)%{ARCH}|/./$1$arch|; $ldir =~ s|%{ARCH}|$arch|g;
			print $LIST "$ldir/$_";
		    }
		    close $F;
		}
		close $LIST;
	    }

	    #- build synthesis file if there are still not existing (ie not copied from mirror).
	    if (-s "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz" <= 32) {
		unlink "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";
		run_program::rooted($prefix, "parsehdlist", ">", "/var/lib/urpmi/synthesis.hdlist.$name",
				    "--synthesis", "/var/lib/urpmi/hdlist.$name.cz");
		run_program::rooted($prefix, "gzip", "-S", ".cz", "/var/lib/urpmi/synthesis.hdlist.$name");
	    }

	    my ($qname, $qdir) = ($name, $dir);
	    $qname =~ s/(\s)/\\$1/g; $qdir =~ s/(\s)/\\$1/g;

	    #- compute correctly reference to media/media_info
	    my $with;
	    if ($_->{update}) {
		$with = "media_info/hdlist.cz";
	    } elsif ($_->{with_hdlist}) {
		$with = $_->{with_hdlist};
	    } else {
		$with = $_->{rpmsdir};
		$with =~ s|/[^/]*%{ARCH}.*||;
		$with =~ s|/+|/|g; $with =~ s|/$||; $with =~ s|[^/]||g; $with =~ s!/!../!g;
		$with .= "../media/media_info/$_->{hdlist}";
	    }

	    #- output new urpmi.cfg format here.
	    push @cfg, "$qname " . ($need_list ? "" : $qdir) . " {
  hdlist: hdlist.$name.cz
  with_hdlist: $with" . ($need_list ? "
  list: list.$name" : "") . (keys(%{$_->{key_ids}}) ? "
  key-ids: " . join(',', keys(%{$_->{key_ids}})) : "") . ($dir =~ /removable:/ && "
  removable: /dev/cdrom") . ($_->{update} ? "
  update" : "") . "
}

";
	} else {
	    #- remove not selected media by removing hdlist and synthesis files copied.
	    log::l("removing media $name");
	    unlink "$prefix/var/lib/urpmi/hdlist.$name.cz";
	    unlink "$prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";
	}
    }
    eval { output "$prefix/etc/urpmi/urpmi.cfg", @cfg };
}


#-###############################################################################
#- kde stuff
#-###############################################################################
sub kderc_largedisplay {
    my ($prefix) = @_;

    update_gnomekderc($_, 'KDE', 
		     Contrast => 7,
		     kfmIconStyle => "Large",
		     kpanelIconStyle => "Normal", #- to change to Large when icons looks better
		     KDEIconStyle => "Large") foreach list_skels($prefix, '.kderc');

    substInFile {
	s/^(GridWidth)=85/$1=100/;
	s/^(GridHeight)=70/$1=75/;
    } $_ foreach list_skels($prefix, '.kde/share/config/kfmrc');
}

sub kdemove_desktop_file {
    my ($prefix) = @_;
    my @toMove = qw(doc.kdelnk news.kdelnk updates.kdelnk home.kdelnk printer.kdelnk floppy.kdelnk cdrom.kdelnk FLOPPY.kdelnk CDROM.kdelnk);

    #- remove any existing save in Trash of each user and
    #- move appropriate file there after an upgrade.
    foreach my $dir (grep { -d $_ } list_skels($prefix, 'Desktop')) {
	renamef("$dir/$_", "$dir/Trash/$_") 
	  foreach grep { -e "$dir/$_" } @toMove, grep { /\.rpmorig$/ } all($dir)
    }
}


#-###############################################################################
#- auto_install stuff
#-###############################################################################
sub auto_inst_file() { "$::prefix/root/drakx/auto_inst.cfg.pl" }

sub report_bug {
    my ($prefix) = @_;
    any::report_bug($prefix, 'auto_inst' => g_auto_install('', 1));
}

sub g_auto_install {
    my ($b_replay, $b_respect_privacy) = @_;
    my $o = {};

    require pkgs;
    $o->{default_packages} = pkgs::selected_leaves($::o->{packages});

    my @fields = qw(mntpoint fs_type size);
    $o->{partitions} = [ map { my %l; @l{@fields} = @$_{@fields}; \%l } grep { $_->{mntpoint} } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(locale authentication mouse netc timezone superuser intf keyboard users partitioning isUpgrade manualFstab nomouseprobe crypto security security_user libsafe netcnx useSupermount autoExitInstall X services); #- TODO modules bootloader 

    if ($::o->{printer}) {
	$o->{printer}{$_} = $::o->{printer}{$_} foreach qw(SPOOLER DEFAULT BROWSEPOLLADDR BROWSEPOLLPORT MANUALCUPSCONFIG);
	$o->{printer}{configured} = {};
	foreach my $queue (keys %{$::o->{printer}{configured}}) {
	    my $val = $::o->{printer}{configured}{$queue}{queuedata};
	    exists $val->{$_} and $o->{printer}{configured}{$queue}{queuedata}{$_} = $val->{$_} foreach keys %{$val || {}};
	}
    }

    local $o->{partitioning}{auto_allocate} = !$b_replay;
    $o->{autoExitInstall} = !$b_replay;
    $o->{interactiveSteps} = [ 'doPartitionDisks', 'formatPartitions' ] if $b_replay;

    #- deep copy because we're modifying it below
    $o->{users} = [ @{$o->{users} || []} ];

    my @user_info_to_remove = (
	if_($b_respect_privacy, qw(name realname home pw)), 
	qw(oldu oldg password password2),
    );
    $_ = { %{$_ || {}} }, delete @$_{@user_info_to_remove} foreach $o->{superuser}, @{$o->{users} || []};

    if ($b_respect_privacy && $o->{netcnx}) {
	if (my $type = $o->{netcnx}{type}) {
	    my @netcnx_type_to_remove = qw(passwd passwd2 login phone_in phone_out);
	    $_ = { %{$_ || {}} }, delete @$_{@netcnx_type_to_remove} foreach $o->{netcnx}{$type};
	}
    }
    
    require Data::Dumper;
    my $str = join('', 
"#!/usr/bin/perl -cw
#
# You should check the syntax of this file before using it in an auto-install.
# You can do this with 'perl -cw auto_inst.cfg.pl' or by executing this file
# (note the '#!/usr/bin/perl -cw' on the first line).
", Data::Dumper->Dump([$o], ['$o']), "\0");
    $str =~ s/ {8}/\t/g; #- replace all 8 space char by only one tabulation, this reduces file size so much :-)
    $str;
}

sub getAndSaveInstallFloppies {
    my ($o, $dest_dir, $name) = @_;    

    if ($postinstall_rpms && -d $postinstall_rpms && -r "$postinstall_rpms/auto_install.img") {
	log::l("getAndSaveInstallFloppies: using file saved as $postinstall_rpms/auto_install.img");
	cp_af("$postinstall_rpms/auto_install.img", "$dest_dir/$name.img");
	"$dest_dir/$name.img";
    } else {
	my $image = cat_("/proc/cmdline") =~ /pcmcia/ ? "pcmcia" :
	  arch() =~ /ia64|ppc/ ? "all"  : #- we only use all.img there
	  ${{ disk => 'hd_grub', 'disk-iso' => 'hd_grub', cdrom => 'cdrom', ftp => 'network', nfs => 'network', http => 'network' }}{$o->{method}};
	my $have_drivers = $image eq 'network';
	$image .= arch() =~ /sparc64/ && "64"; #- for sparc64 there are a specific set of image.

	if ($have_drivers) {
	    getAndSaveFile("install/images/${image}_drivers.img", "$dest_dir/${name}_drivers.img") or log::l("failed to write Install Floppy (${image}_drivers.img) to $dest_dir/${name}_drivers.img"), return;
	}
	getAndSaveFile("install/images/$image.img", "$dest_dir/$name.img") or log::l("failed to write Install Floppy ($image.img) to $dest_dir/$name.img"), return;

	"$dest_dir/$name.img", if_($have_drivers, "$dest_dir/${name}_drivers.img");
    }
}

sub getAndSaveAutoInstallFloppies {
    my ($o, $replay) = @_;
    my $name = ($replay ? 'replay' : 'auto') . '_install';
    my $dest_dir = "$o->{prefix}/root/drakx";

    eval { modules::load('loop') };

    if (arch() =~ /ia64/) {
	#- nothing yet
    } else {
	my $mountdir = "$o->{prefix}/root/aif-mount"; -d $mountdir or mkdir $mountdir, 0755;
	my $param = 'kickstart=floppy ' . generate_automatic_stage1_params($o);

	my @imgs = getAndSaveInstallFloppies($o, $dest_dir, $name) or return;

	foreach my $img (@imgs) {
	    my $dev = devices::set_loop($img) or log::l("couldn't set loopback device"), return;
	    find { eval { fs::mount($dev, $mountdir, $_, 0); 1 } } qw(ext2 vfat) or return;

	    if (-e "$mountdir/menu.lst") {
		# hd_grub boot disk is different than others
		substInFile {
		    s/^(\s*timeout.*)/timeout 1/;
		    s/\bautomatic=method:disk/$param/;
		} "$mountdir/menu.lst";
	    } elsif (-e "$mountdir/syslinux.cfg") {
		#- make room first
		unlink "$mountdir/help.msg", "$mountdir/boot.msg";

		substInFile { 
		    s/timeout.*/$replay ? 'timeout 1' : ''/e;
		    s/^(\s*append)/$1 $param/ 
		} "$mountdir/syslinux.cfg";

		output "$mountdir/boot.msg", $replay ? '' : "\n0c" .
"!! If you press enter, an auto-install is going to start.
   All data on this computer is going to be lost,
   including any Windows partitions !!
" . "07\n";
	    }

	    if (@imgs == 1 || $img =~ /drivers/) {
		local $o->{partitioning}{clearall} = !$replay;
		eval { output("$mountdir/auto_inst.cfg", g_auto_install($replay)) };
		$@ and log::l("Warning: <", formatError($@), ">");
	    }
	
	    fs::umount($mountdir);
	    devices::del_loop($dev);
	}
	rmdir $mountdir;
	@imgs;
    }
}


sub g_default_packages {
    my ($o, $b_quiet) = @_;

    my $floppy = detect_devices::floppy();

    while (1) {
	$o->ask_okcancel('', N("Insert a FAT formatted floppy in drive %s", $floppy), 1) or return;

	eval { fs::mount(devices::make($floppy), "/floppy", "vfat", 0) };
	last if !$@;
	$o->ask_warn('', N("This floppy is not FAT formatted"));
    }

    require Data::Dumper;
    my $str = Data::Dumper->Dump([ { default_packages => pkgs::selected_leaves($o->{packages}) } ], ['$o']);
    $str =~ s/ {8}/\t/g;
    output('/floppy/auto_inst.cfg', 
	   "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl'\n",
	   "# before testing.  To use it, boot with ``linux defcfg=floppy''\n",
	   $str, "\0");
    fs::umount("/floppy");

    $b_quiet or $o->ask_warn('', N("To use this saved packages selection, boot installation with ``linux defcfg=floppy''"));
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file();
    my $o;
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? 'auto_inst.cfg' : "patch";
	unless ($::testing) {
            my $dev = devices::make(detect_devices::floppy());
            foreach my $fs (arch() =~ /sparc/ ? 'romfs' : ('ext2', 'vfat')) {
                eval { fs::mount($dev, '/mnt', $fs, 'readonly'); 1 } and goto mount_ok;
            }
            die "Couldn't mount floppy [$dev]";
          mount_ok:
	    $f = "/mnt/$f";
	}
	-e $f or $f .= '.pl';

	my $_b = before_leaving {
	    fs::umount("/mnt") unless $::testing;
	    modules::unload(qw(vfat fat));
	};
	$o = loadO($O, $f);
    } else {
	-e "$f.pl" and $f .= ".pl" unless -e $f;

	my $fh;
	if (-e $f) { open $fh, $f } else { $fh = getFile($f) or die N("Error reading file %s", $f) }
	{
	    local $/ = "\0";
	    no strict;
	    eval <$fh>;
	    close $fh;
	    $@ and die;
	}
	$O and add2hash_($o ||= {}, $O);
    }
    $O and bless $o, ref $O;

    #- handle backward compatibility for things that changed
    foreach (@{$o->{partitions} || []}, @{$o->{manualFstab} || []}) {
	if (my $type = delete $_->{type}) {
	    if ($type =~ /^(0x)?(\d*)$/) {
		fs::type::set_pt_type($_, $type);
	    } else {
		fs::type::set_fs_type($_, $type);
	    }
	}
    }
    if (my $rpmsrate_flags_chosen = delete $o->{compssUsersChoice}) {
	$o->{rpmsrate_flags_chosen} = $rpmsrate_flags_chosen;
    }

    $o;
}

sub generate_automatic_stage1_params {
    my ($o) = @_;

    my $method = $o->{method};
    my @ks;

    if ($o->{method} eq 'http') {
	$ENV{URLPREFIX} =~ m!(http|ftp)://([^/:]+)(.*)! or die;
	$method = $1; #- in stage1, FTP via HTTP proxy is available through FTP config, not HTTP
	@ks = (server => $2, directory => $3);
    } elsif ($o->{method} eq 'ftp') {
	@ks = (server => $ENV{HOST}, directory => $ENV{PREFIX}, user => $ENV{LOGIN}, pass => $ENV{PASSWORD});
    } elsif ($o->{method} eq 'nfs') {
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/nfsimage| or internal_error("can't find nfsimage");
	@ks = (server => $1, directory => $2);
    }
    @ks = (method => $method, @ks);

    if (member($o->{method}, qw(http ftp nfs))) {
	if ($ENV{PROXY}) {
	    push @ks, proxy_host => $ENV{PROXY}, proxy_port => $ENV{PROXYPORT};
	}
	my ($intf) = values %{$o->{intf}};
	push @ks, interface => $intf->{DEVICE};
	if ($intf->{BOOTPROTO} eq 'dhcp') {
	    push @ks, network => 'dhcp';
	} else {
	    push @ks, network => 'static', ip => $intf->{IPADDR}, netmask => $intf->{NETMASK}, gateway => $o->{netc}{GATEWAY};
	    require network::network;
	    if (my @dnss = network::network::dnsServers($o->{netc})) {
		push @ks, dns => $dnss[0];
	    }
	}
    }

    #- sync it with ../mdk-stage1/automatic.c
    my %aliases = (method => 'met', network => 'netw', interface => 'int', gateway => 'gat', netmask => 'netm',
		   adsluser => 'adslu', adslpass => 'adslp', hostname => 'hos', domain => 'dom', server => 'ser',
		   directory => 'dir', user => 'use', pass => 'pas', disk => 'dis', partition => 'par');
    
    'automatic=' . join(',', map { ($aliases{$_->[0]} || $_->[0]) . ':' . $_->[1] } group_by2(@ks));
}

sub guess_mount_point {
    my ($part, $prefix, $user) = @_;

    my %l = (
	     '/'     => 'etc/fstab',
	     '/boot' => 'vmlinuz',
	     '/tmp'  => '.X11-unix',
	     '/usr'  => 'X11R6',
	     '/var'  => 'catman',
	    );

    my $handle = any::inspect($part, $prefix) or return;
    my $d = $handle->{dir};
    my $mnt = find { -e "$d/$l{$_}" } keys %l;
    $mnt ||= (stat("$d/.bashrc"))[4] ? '/root' : '/home/user' . ++$$user if -e "$d/.bashrc";
    $mnt ||= (any { -d $_ && (stat($_))[4] >= 500 && -e "$_/.bashrc" } glob_($d)) ? '/home' : '';
    ($mnt, $handle);
}

sub suggest_mount_points {
    my ($fstab, $prefix, $uniq) = @_;

    my $user;
    foreach my $part (grep { isTrueFS($_) } @$fstab) {
	$part->{mntpoint} && !$part->{unsafeMntpoint} and next; #- if already found via an fstab

	my ($mnt, $handle) = guess_mount_point($part, $prefix, \$user) or next;

	next if $uniq && fs::get::mntpoint2part($mnt, $fstab);
	$part->{mntpoint} = $mnt; delete $part->{unsafeMntpoint};

	#- try to find other mount points via fstab
	fs::merge_info_from_fstab($fstab, $handle->{dir}, $uniq, 'loose') if $mnt eq '/';
    }
    $_->{mntpoint} and log::l("suggest_mount_points: $_->{device} -> $_->{mntpoint}") foreach @$fstab;
}

sub find_root_parts {
    my ($fstab, $prefix) = @_;
    map { 
	my $handle = any::inspect($_, $prefix);
	my $f = $handle && (find { -f $_ } map { "$handle->{dir}/etc/$_" } 'mandrakelinux-release', 'mandrake-release', 'redhat-release');
	if ($f) {
	    my $s = cat_($f);
	    chomp($s);
	    $s =~ s/\s+for\s+\S+//;
	    log::l("find_root_parts found $_->{device}: $s");
	    { release => $s, part => $_, release_file => $f };
	} else { () }
    } @$fstab;
}
sub use_root_part {
    my ($all_hds, $part, $prefix) = @_;
    {
	my $handle = any::inspect($part, $prefix) or die;
	fs::get_info_from_fstab($all_hds, $handle->{dir});
    }
    isSwap($_) and $_->{mntpoint} = 'swap' foreach fs::get::really_all_fstab($all_hds); #- use all available swap.
}

sub getHds {
    my ($o, $o_in) = @_;

  getHds: 
    my $all_hds = fsedit::get_hds($o->{partitioning}, $o_in);
    my $hds = $all_hds->{hds};

    if (is_empty_array_ref($hds) && !$::move) { #- no way
	die N("An error occurred - no valid devices were found on which to create new filesystems. Please check your hardware for the cause of this problem");
    }

    #- try to figure out if the same number of hds is available, use them if ok.
    @{$o->{all_hds}{hds} || []} == @$hds and return 1;

    fs::get_raw_hds('', $all_hds);
    fs::add2all_hds($all_hds, @{$o->{manualFstab}});

    $o->{all_hds} = $all_hds;
    $o->{fstab} = [ fs::get::really_all_fstab($all_hds) ];
    fs::merge_info_from_mtab($o->{fstab});

    my @win = grep { isFat_or_NTFS($_) && maybeFormatted($_) && !$_->{is_removable} } @{$o->{fstab}};
    log::l("win parts: ", join ",", map { $_->{device} } @win) if @win;
    if (@win == 1) {
	#- Suggest /boot/efi on ia64.
	$win[0]{mntpoint} = arch() =~ /ia64/ ? "/boot/efi" : "/mnt/windows";
    } else {
	my %w; foreach (@win) {
	    my $v = $w{$_->{device_windobe}}++;
	    $_->{mntpoint} = $_->{unsafeMntpoint} = "/mnt/win_" . lc($_->{device_windobe}) . ($v ? $v+1 : ''); #- lc cuz of StartOffice(!) cf dadou
	}
    }

    my @sunos = grep { $_->{pt_type} == 2 } @{$o->{fstab}}; #- take only into account root partitions.
    if (@sunos) {
	my $v = '';
	map { $_->{mntpoint} = $_->{unsafeMntpoint} = "/mnt/sunos" . ($v && ++$v) } @sunos;
    }
    #- a good job is to mount SunOS root partition, and to use mount point described here in /etc/vfstab.

    1;
}

sub log_sizes {
    my ($o) = @_;
    my @df = MDK::Common::System::df($o->{prefix});
    log::l(sprintf "Installed: %s(df), %s(rpm)",
	   formatXiB($df[0] - $df[1], 1024),
	   formatXiB(sum(run_program::rooted_get_stdout($o->{prefix}, 'rpm', '-qa', '--queryformat', '%{size}\n')))) if -x "$o->{prefix}/bin/rpm";
}

sub X_options_from_o {
    my ($o) = @_;
    { 
	freedriver => $o->{freedriver},
	allowFB => $o->{allowFB},
    };
}

sub copy_advertising {
    my ($o) = @_;

    return if $::rootwidth < 800;

    my $f;
    my $source_dir = "install/extra/advertising";
    foreach ("." . $o->{locale}{lang}, "." . substr($o->{locale}{lang},0,2), '') {
	$f = getFile("$source_dir$_/list") or next;
	$source_dir = "$source_dir$_";
    }
    if (my @files = <$f>) {
	my $dir = "$o->{prefix}/tmp/drakx-images";
	mkdir $dir;
	unlink glob_("$dir/*");
	foreach (@files) {
	    chomp;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/\.png/.pl/;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/\.pl/_icon.png/;
	    getAndSaveFile("$source_dir/$_", "$dir/$_");
	    s/_icon\.png/.png/;
	}
	@advertising_images = map { "$dir/$_" } @files;
    }
}

sub remove_advertising {
    my ($o) = @_;
    eval { rm_rf("$o->{prefix}/tmp/drakx-images") };
    @advertising_images = ();
}

sub disable_user_view() {
    substInFile { s/^UserView=.*/UserView=true/ } "$::prefix/usr/share/config/kdm/kdmrc";
    substInFile { s/^Browser=.*/Browser=0/ } "$::prefix/etc/X11/gdm/gdm.conf";
}

sub set_security {
    my ($o) = @_;
    {
	local $ENV{DRAKX_PASSWORD} = $o->{bootloader}{password};
	local $ENV{DURING_INSTALL} = 1;
	security::level::set($o->{security});
    }
    require security::various;
    security::various::config_libsafe($::prefix, $o->{libsafe});
    security::various::config_security_user($::prefix, $o->{security_user});
}

sub write_fstab {
    my ($o) = @_;
    fs::write_fstab($o->{all_hds}, $o->{prefix}) if !$o->{isUpgrade};
}

my @bigseldom_used_groups = (
);

sub check_prog {
    my ($f) = @_;

    return if $f =~ m|^/| ? -x $f : whereis_binary($f);

    common::usingRamdisk() or log::l("ERROR: check_prog can't find the program $f and we're not using ramdisk"), return;

    my ($f_) = map { m|^/| ? $_ : "/usr/bin/$_" } $f;
    remove_bigseldom_used();
    foreach (@bigseldom_used_groups) {
	my (@l) = map { m|^/| ? $_ : "/usr/bin/$_" } @$_;
	if (member($f_, @l)) {
	    foreach (@l) {
		getAndSaveFile($_);
		chmod 0755, $_;
	    }
	    return;
	}
    }
    getAndSaveFile($f_);
    chmod 0755, $f_;
}

sub remove_unused {
    $::testing and return;
    if (@_ ? $_[0] : $::o->isa('interactive::gtk')) {
	unlink glob_("/lib/lib$_*") foreach qw(slang newt);
	unlink "/usr/bin/perl-install/auto/Newt/Newt.so";
    } else {
	unlink glob_("/usr/X11R6/bin/XF*");
    }
}

sub remove_bigseldom_used() {
    log::l("remove_bigseldom_used");
    $::testing and return;
    remove_unused();
    unlink "/usr/X11R6/lib/modules/xf86Wacom.so";
    unlink glob_("/usr/share/gtk/themes/$_*") foreach qw(marble3d);
    unlink(m|^/| ? $_ : "/usr/bin/$_") foreach 
      (map { @$_ } @bigseldom_used_groups),
      qw(lvm2),
      qw(mkreiserfs resize_reiserfs mkfs.xfs fsck.jfs);
}


#-###############################################################################
#- pcmcia various
#-###############################################################################
sub configure_pcmcia {
    my ($modules_conf, $pcic) = @_;

    #- try to setup pcmcia if cardmgr is not running.
    my $running if 0;
    return if $running;
    $running = 1;

    log::l("i try to configure pcmcia services");

    symlink "/tmp/stage2/$_", $_ foreach "/etc/pcmcia";

    eval { modules::load('pcmcia_core', $pcic, 'ds') };

    #- run cardmgr in foreground while it is configuring the card.
    run_program::run("cardmgr", "-f", "-m", "/modules");
    sleep(3);
    
    #- make sure to be aware of loaded module by cardmgr.
    modules::read_already_loaded($modules_conf);
}

sub write_pcmcia {
    my ($pcic) = @_;

    #- should be set after installing the package above otherwise the file will be renamed.
    setVarsInSh("$::prefix/etc/sysconfig/pcmcia", {
	PCMCIA    => bool2yesno($pcic),
	PCIC      => $pcic,
	PCIC_OPTS => "",
        CORE_OPTS => "",
    });
}


1;
