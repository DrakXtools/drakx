package install_any; # $Id$

use strict;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = (
    all => [ qw(getNextStep spawnShell addToBeDone) ],
);
our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use run_program;
use fs::type;
use fs::format;
use partition_table;
use devices;
use fsedit;
use modules;
use detect_devices;
use lang;
use any;
use log;
use pkgs;

#- boot medium (the first medium to take into account).
our $boot_medium = 1;
our $current_medium = $boot_medium;
our $asked_medium = $boot_medium;
our @advertising_images;

#- current ftp root (for getFile) -- XXX must store this per media
our $global_ftp_prefix;

sub drakx_version() { 
    $::move ? sprintf "DrakX-move v%s", cat_('/usr/bin/stage2/move.pm') =~ /move\.pm,v (\S+ \S+ \S+)/
	    : sprintf "DrakX v%s built %s", $::testing ? ('TEST', scalar gmtime()) : (split('/', cat__(getFile("install/stage2/VERSION"))))[2,3];
}

#-######################################################################################
#- Media change variables&functions
#-######################################################################################
my $postinstall_rpms = '';
my $cdrom;
my %iso_images;

sub mountCdrom {
    my ($mountpoint, $o_cdrom) = @_;
    $o_cdrom = $cdrom if !defined $o_cdrom;
    eval { fs::mount::mount($o_cdrom, $mountpoint, "iso9660", 'readonly') };
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
	$_ = install_medium::by_id($asked_medium)->{rpmsdir} . "/$_";
	s/%{ARCH}/$arch/g;
	s,^/+,,g;
    }
    $_;
}
sub askChangeMedium($$) {
    my ($method, $medium_name) = @_;
    my $allow;
    do {
	local $::o->{method} = $method = 'cdrom' if install_medium::by_id($medium_name)->is_suppl_cd;
	eval { $allow = changeMedium($method, $medium_name) };
    } while $@; #- really it is not allowed to die in changeMedium!!! or install will core with rpmlib!!!
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
	#- the ISO volume names must end in -Disc\d+ if they are belong (!) to a set
	my ($cd_set) = $vol_id =~ /^(.*)-disc\d+$/i;
	#- else use the full volume name as CD set identifier
	$cd_set ||= $vol_id;
	{ cd_set => $cd_set, app_id => $app_id };
    };

    sysopen(my $F, $iso_images{loopdev}, 0) or return;
    put_in_hash(\%iso_images, $get_iso_ids->($F));

    my $iso_dir = $ENV{ISOPATH};
    #- strip old root and remove iso file from path if present
    $iso_dir =~ s!^/sysroot!!; $iso_dir =~ s![^/]*\.iso$!!;

    foreach my $iso_file (glob("$iso_dir/*.iso")) {
	sysopen($F, $iso_file, 0) or next;
	my $iso_ids = $get_iso_ids->($F);
	$iso_ids->{file} = $iso_file;
	push @{$iso_images{media}}, $iso_ids;
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

    eval { fs::mount::umount($iso_images{mountpoint}) };
    $@ and warnAboutFilesStillOpen();
    devices::del_loop($iso_images{loopdev});

    $iso_images{loopdev} = devices::set_loop($iso_info->{file});
    eval { 
	fs::mount::mount($iso_images{loopdev}, $iso_images{mountpoint}, "iso9660", 'readonly');
	log::l("using ISO image '$iso_label'");
	1;
    };
}

sub errorOpeningFile($) {
    my ($file) = @_;
    $file eq 'XXX' and return; #- special case to force closing file after rpmlib transaction.
    $current_medium eq $asked_medium and log::l("errorOpeningFile $file"), return; #- nothing to do in such case.
    install_medium::by_id($asked_medium)->selected or return; #- not selected means no need to worry about.
    my $current_method = install_medium::by_id($asked_medium)->method || $::o->{method};

    my $max = 32; #- always refuse after $max tries.
    if ($current_method eq "cdrom") {
	cat_("/proc/mounts") =~ m,(/dev/\S+)\s+(/mnt/cdrom|/tmp/image),
	    and ($cdrom, my $mountpoint) = ($1, $2);
	return unless $cdrom;
	ejectCdrom($cdrom, $mountpoint);
	while ($max > 0 && askChangeMedium($current_method, $asked_medium)) {
	    $current_medium = $asked_medium;
	    mountCdrom("/tmp/image");
	    my $getFile = getFile($file); 
	    $getFile && @advertising_images and copy_advertising($::o);
	    $getFile and return $getFile;
	    $current_medium = 'unknown'; #- do not know what CD is inserted now.
	    ejectCdrom($cdrom, $mountpoint);
	    --$max;
	}
    } else {
	while ($max > 0 && askChangeMedium($current_method, $asked_medium)) {
	    $current_medium = $asked_medium;
	    my $getFile = getFile($file); $getFile and return $getFile;
	    $current_medium = 'unknown'; #- do not know what CD image has been copied.
	    --$max;
	}
    }

    #- Do not unselect supplementary CDs.
    return if install_medium::by_id($asked_medium)->is_suppl_cd;

    #- keep in mind the asked medium has been refused.
    #- this means it is no longer selected.
    install_medium::by_id($asked_medium)->refuse;

    #- on cancel, we can expect the current medium to be undefined too,
    #- this enables remounting if selecting a package back.
    $current_medium = 'unknown';

    return;
}
sub getFile {
    my ($f, $o_method, $o_altroot) = @_;
    my $current_method = ($asked_medium ? install_medium::by_id($asked_medium)->method : '') || $::o->{method};
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
	    ftp::getFile($rel, @{ install_medium::by_id($asked_medium)->{ftp_prefix} || $global_ftp_prefix || [] });
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
	    my $F; open($F, $f2) ? $F : do { $f2 !~ /XXX/ and log::l("Can not open $f2: $!"); undef };
	}
    } || errorOpeningFile($f);
}

sub getLocalFile {
    my ($file) = @_;
    my $F;
    open($F, $file) ? $F : do { log::l("Can not open $file: $!"); undef };
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
    $packages->{rpmdb} ||= pkgs::rpmDbOpen();
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
    #- cp_af does not handle correctly a missing file.
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
    find { !$o->{steps}{$_}{done} && $o->{steps}{$_}{reachable} } @{$o->{orderedSteps}};
}

sub dont_run_directly_stage2() {
    readlink("/usr/bin/runinstall2") eq "runinstall2.sh";
}


sub start_i810fb() {
    my ($vga) = cat_('/proc/cmdline') =~ /vga=(\S+)/;
    return if !$vga || listlength(cat_('/proc/fb'));

    my %vga_to_xres = (0x311 => '640', 0x314 => '800', 0x317 => '1024');
    my $xres = $vga_to_xres{$vga} || '800';

    log::l("trying to load i810fb module with xres <$xres> (vga was <$vga>)");
    eval { modules::load('intel-agp') };
    eval {
	my $opt = "xres=$xres hsync1=32 hsync2=48 vsync1=50 vsync2=70 vram=2 bpp=16 accel=1 mtrr=1"; #- this sucking i810fb does not accept floating point numbers in hsync!
	modules::load_with_options([ 'i810fb' ], { i810fb => $opt }); 
    };
}

sub spawnShell() {
    return if $::local_install || $::testing || dont_run_directly_stage2();

    my $shellpid_file = '/var/run/drakx_shell.pid';
    return if -e $shellpid_file && -d '/proc/' . chomp_(cat_($shellpid_file));

    if (my $shellpid = fork()) {
        output($shellpid_file, $shellpid);
        return;
    }

    $ENV{DISPLAY} ||= ":0"; #- why not :pp

    local *F;
    sysopen F, "/dev/tty2", 2 or log::l("cannot open /dev/tty2 -- no shell will be provided: $!"), goto cant_spawn;

    open STDIN, "<&F" or goto cant_spawn;
    open STDOUT, ">&F" or goto cant_spawn;
    open STDERR, ">&F" or goto cant_spawn;
    close F;

    print drakx_version(), "\n";

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
   
    #- can not be done in install cuz' timeconfig %post creates funny things
    add2hash($o->{timezone}, timezone::read()) if $o->{isUpgrade};

    $o->{timezone}{timezone} ||= timezone::bestTimezone($o->{locale}{country});

    my $utc = every { !isFat_or_NTFS($_) } @{$o->{fstab}};
    my $ntp = timezone::ntp_server();
    add2hash_($o->{timezone}, { UTC => $utc, ntp => $ntp });
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
	    join ", ", uniq(sort {
		    (my $x) = $a =~ /CD(\d+)/;
		    (my $y) = $b =~ /CD(\d+)/;
		    $x && $y ? $x <=> $y : $a cmp $b;
		} map { $_->{descr} } values %{$o->{packages}{mediums}})));
    $o->ask_from(
	'', $msg,
	[ {
	    val => \my $suppl,
	    list => [ N_("None"), N_("CD-ROM"), N_("Network (HTTP)"), N_("Network (FTP)"), N_("Network (NFS)") ],
	    type => 'list',
	    format => \&translate,
	} ],
    );
    $suppl_already_asked = 1;
    return $suppl;
}

#- if the supplementary media is networked, but not the main one, network
#- support must be installed and network started.
sub prep_net_suppl_media {
    return if our $net_suppl_media_configured;
    $net_suppl_media_configured = 1;
    my ($o) = @_;
    #- install basesystem now
    $::o->do_pkgs->ensure_is_installed('basesystem', undef, 1);
    #- from install_steps_interactive:
    local $::expert = $::expert;
    require network::netconnect;
    network::netconnect::real_main($o->{net}, $o, $o->{modules_conf});
    require install_interactive;
    install_interactive::upNetwork($o);
    sleep(3);
}

sub remountCD1 {
    my ($o, $cdrom) = @_;
    return if install_medium::by_id(1, $o->{packages})->method ne 'cdrom';
    openCdromTray($cdrom);
    $o->ask_warn('', N("Insert the CD 1 again"));
    mountCdrom("/tmp/image", $cdrom);
    log::l($@) if $@;
    $asked_medium = 1;
}

sub selectSupplMedia {
    my ($o, $suppl_method) = @_;
    #- ask whether there are supplementary media
    my $prev_asked_medium = $asked_medium;
    if ($suppl_method && (my $suppl = ask_if_suppl_media($o)) ne 'None') {
	#- translate to method name
	$suppl_method = {
	    'CD-ROM' => 'cdrom',
	    'Network (HTTP)' => 'http',
	    'Network (FTP)' => 'ftp',
	    'Network (NFS)' => 'nfs',
	}->{$suppl};
	my $medium_name = int(keys %{$o->{packages}{mediums}}) + 1;
	#- configure network if needed
	prep_net_suppl_media($o) if !scalar keys %{$o->{intf}} && $suppl_method !~ /^(?:cdrom|disk)/;
	local $::isWizard = 0;
	local $o->{method} = $suppl_method;
	if ($suppl_method eq 'cdrom') {
	    (my $cdromdev) = detect_devices::cdroms();
	    $o->ask_warn('', N("No device found")), return 'error' if !$cdromdev;
	    $cdrom = $cdromdev->{device};
	    $cdrom =~ m,^/, or $cdrom = "/dev/$cdrom";
	    devices::make($cdrom);
	    ejectCdrom($cdrom);
	    if ($o->ask_okcancel('', N("Insert the CD"), 1)) {
		#- mount suppl CD in /mnt/cdrom to avoid umounting /tmp/image
		mountCdrom("/mnt/cdrom", $cdrom);
		if ($@) {
		    log::l($@);
		    $o->ask_warn('', N("Unable to mount CD-ROM"));
		    return 'error';
		}
		useMedium($medium_name);

		#- probe for an hdlists file and then look for all hdlists listed herein
		eval {
		    pkgs::psUsingHdlists($o, $suppl_method, "/mnt/cdrom", $o->{packages}, $medium_name, sub {
			my ($supplmedium) = @_;
			$supplmedium->mark_suppl;
		    });
		};
		log::l("psUsingHdlists failed: $@") if $@;

		#- copy latest compssUsers.pl and rpmsrate somewhere locally
		getAndSaveFile("/mnt/cdrom/media/media_info/compssUsers.pl", "/tmp/compssUsers.pl");
		getAndSaveFile("/mnt/cdrom/media/media_info/rpmsrate", "/tmp/rpmsrate");

		#- umount supplementary CD. Will re-ask for it later
		getFile("XXX"); #- close still opened filehandles
		log::l("Umounting suppl. CD, back to medium 1");
		eval { fs::mount::umount("/mnt/cdrom") };
		#- re-mount CD 1 if this was a cdrom install
		remountCD1($o, $cdrom);
	    } else {
		remountCD1($o, $cdrom);
		return 'error';
	    }
	} else {
	    my $url;
	    local $global_ftp_prefix;
	    if ($suppl_method eq 'ftp') { #- mirrors are ftp only (currently)
		$url = $o->askSupplMirror(N("URL of the mirror?")) or return 'error';
		$url =~ m!^ftp://(?:(.*?)(?::(.*?))?\@)?([^/]+)/(.*)!
		    and $global_ftp_prefix = [ $3, $4, $1, $2 ]; #- for getFile
	    } elsif ($suppl_method eq 'nfs') {
		$o->ask_from_(
		    { title => N("NFS setup"), messages => N("Please enter the hostname and directory of your NFS media") },
		    [ { label => N("Hostname of the NFS mount ?"), val => \my $host }, { label => N("Directory"), val => \my $dir } ],
		) or return 'error';
		$dir =~ s!/+\z!!; $dir eq '' and $dir = '/';
		return 'error' if !$host || !$dir || substr($dir, 0, 1) ne '/';
		my $mediadir = '/mnt/nfsmedia' . $medium_name;
		$url = "$::prefix$mediadir";
		-d $url or mkdir_p($url);
		my $dev = "$host:$dir";
		eval { fs::mount::mount($dev, $url, 'nfs'); 1 }
		    or do { log::l("Mount failed: $@"); return 'error' };
		#- add $mediadir in fstab for post-installation
		push @{$o->{all_hds}{nfss}}, { fs_type => 'nfs', mntpoint => $mediadir, device => $dev, options => "noauto,ro,nosuid,soft,rsize=8192,wsize=8192" };
	    } else {
		$url = $o->ask_from_entry('', N("URL of the mirror?")) or return 'error';
		$url =~ s!/+\z!!;
	    }
	    useMedium($medium_name);
	    require http if $suppl_method eq 'http';
	    require ftp if $suppl_method eq 'ftp';
	    #- first, try to find an hdlists file
	    eval { pkgs::psUsingHdlists($o, $suppl_method, $url, $o->{packages}, $medium_name, \&setup_suppl_medium) };
	    if ($@) {
		log::l("psUsingHdlists failed: $@");
	    } else {
		#- copy latest compssUsers.pl and rpmsrate somewhere locally
		if ($suppl_method eq 'ftp') {
		    getAndSaveFile("media/media_info/compssUsers.pl", "/tmp/compssUsers.pl");
		    getAndSaveFile("media/media_info/rpmsrate", "/tmp/rpmsrate");
		} else {
		    getAndSaveFile("$url/media/media_info/compssUsers.pl", "/tmp/compssUsers.pl");
		    getAndSaveFile("$url/media/media_info/rpmsrate", "/tmp/rpmsrate");
		}
		useMedium($prev_asked_medium); #- back to main medium
		return $suppl_method;
	    }
	    #- then probe for an hdlist.cz
	    my $f = eval {
		if ($suppl_method eq 'http') {
		    http::getFile("$url/media_info/hdlist.cz");
		} elsif ($suppl_method eq 'ftp') {
		    getFile("media_info/hdlist.cz");
		} elsif ($suppl_method eq 'nfs') {
		    getFile("$url/media_info/hdlist.cz");
		} else { undef }
	    };
	    if (!defined $f) {
		log::l($@ || "hdlist.cz unavailable");
		#- no hdlist found
		$o->ask_warn('', N("Can't find a package list file on this mirror. Make sure the location is correct."));
		useMedium($prev_asked_medium);
		return 'error';
	    }
	    my $supplmedium = pkgs::psUsingHdlist(
		$suppl_method,
		$o->{packages},
		"hdlist$medium_name.cz", #- hdlist
		$medium_name,
		'', #- rpmsdir
		"Supplementary media $medium_name", #- description
		1, #- selected
		$f,
	    );
	    close $f;
	    if ($supplmedium) {
		log::l("read suppl hdlist (via $suppl_method)");
		setup_suppl_medium($supplmedium, $url, $suppl_method);
	    } else {
		log::l("no suppl hdlist");
		$suppl_method = 'error';
	    }
	}
    } else {
	$suppl_method = '';
    }
    useMedium($prev_asked_medium); #- back to main medium
    return $suppl_method;
}

sub setup_suppl_medium {
    my ($supplmedium, $url, $suppl_method) = @_;
    $supplmedium->{prefix} = $url;
    if ($suppl_method eq 'ftp') {
	$url =~ m!^ftp://(?:(.*?)(?::(.*?))?\@)?([^/]+)/(.*)!
	    and $supplmedium->{ftp_prefix} = [ $3, $4, $1, $2 ]; #- for getFile
    } elsif ($suppl_method eq 'nfs') { #- once installed, path changes
	$supplmedium->{finalprefix} = $supplmedium->{prefix};
	$supplmedium->{finalprefix} =~ s/^\Q$::prefix//;
    }
    $supplmedium->select;
    $supplmedium->{method} = $suppl_method;
    $supplmedium->{with_hdlist} = 'media_info/hdlist.cz'; #- for install_urpmi
    $supplmedium->mark_suppl;
}

sub load_rate_files {
    my ($o) = @_;
    #- must be done after getProvides
    #- if there is a supplementary media, the rpmsrate/compssUsers are overridable
    pkgs::read_rpmsrate(
	$o->{packages},
	$o->{rpmsrate_flags_chosen},
	-e "/tmp/rpmsrate" ? getLocalFile("/tmp/rpmsrate") : getFile("media/media_info/rpmsrate")
    );
    ($o->{compssUsers}, $o->{gtk_display_compssUsers}) = pkgs::readCompssUsers(
	-e '/tmp/compssUsers.pl' ? '/tmp/compssUsers.pl' : 'media/media_info/compssUsers.pl'
    );
    defined $o->{compssUsers} or die "Can't read compssUsers.pl file, aborting installation\n";
}

sub setPackages {
    my ($o) = @_;

    require pkgs;
    if (!$o->{packages} || is_empty_array_ref($o->{packages}{depslist})) {
	($o->{packages}, my $suppl_method, my $copy_rpms_on_disk) = pkgs::psUsingHdlists($o, $o->{method});

	1 while $suppl_method = $o->selectSupplMedia($suppl_method);

	#- open rpm db according to right mode needed (ie rebuilding database if upgrading)
	$o->{packages}{rpmdb} ||= pkgs::rpmDbOpen($o->{isUpgrade});

	#- always try to select basic kernel (else on upgrade, kernel will never be updated provided a kernel is already
	#- installed and provides what is necessary).
	pkgs::selectPackage($o->{packages},
			    pkgs::bestKernelPackage($o->{packages}) || die("missing kernel package"), 1);

	pkgs::selectPackage($o->{packages},
			    pkgs::packageByName($o->{packages}, 'basesystem') || die("missing basesystem package"), 1);

	my $rpmsrate_flags_was_chosen = $o->{rpmsrate_flags_chosen};

	put_in_hash($o->{rpmsrate_flags_chosen} ||= {}, rpmsrate_always_flags($o)); #- must be done before pkgs::read_rpmsrate()
	load_rate_files($o);

	copy_rpms_on_disk($o) if $copy_rpms_on_disk;

	set_rpmsrate_default_category_flags($o, $rpmsrate_flags_was_chosen);

	push @{$o->{default_packages}}, default_packages($o);
	select_default_packages($o);
    } else {
	#- this has to be done to make sure necessary files for urpmi are
	#- present.
	pkgs::psUpdateHdlistsDeps($o->{packages});

	#- open rpm db (always without rebuilding db, it should be false at this point).
	$o->{packages}{rpmdb} ||= pkgs::rpmDbOpen();
    }
}

sub count_files {
    my ($dir) = @_;
    -d $dir or return 0;
    opendir my $dh, $dir or return 0;
    my @list = grep { !/^\.\.?$/ } readdir $dh;
    closedir $dh;
    my $c = 0;
    foreach my $n (@list) {
	my $p = "$dir/$n";
	if (-d $p) { $c += count_files($p) } else { ++$c }
    }
    $c;
}

sub cp_with_progress {
    my $wait_message = shift;
    my $current = shift;
    my $total = shift;
    my $dest = pop @_;
    @_ or return;
    @_ == 1 || -d $dest or die "cp: copying multiple files, but last argument ($dest) is not a directory\n";

    foreach my $src (@_) {
	my $dest = $dest;
	-d $dest and $dest .= '/' . basename($src);

	unlink $dest;

	if (-l $src) {
	    unless (symlink(readlink($src) || die("readlink failed: $!"), $dest)) {
		warn "symlink: can't create symlink $dest: $!\n";
	    }
	} elsif (-d $src) {
	    -d $dest or mkdir $dest, (stat($src))[2] or die "mkdir: can't create directory $dest: $!\n";
	    cp_with_progress($wait_message, $current, $total, glob_($src), $dest);
	} else {
	    open(my $F, $src) or die "can't open $src for reading: $!\n";
	    open(my $G, ">", $dest) or die "can't cp to file $dest: $!\n";
	    local $/ = \4096;
	    local $_; while (<$F>) { print $G $_ }
	    chmod((stat($src))[2], $dest);
	    $wait_message->('', ++$current, $total);
	}
    }
    1;
}

sub copy_rpms_on_disk {
    my ($o) = @_;
    mkdir "$o->{prefix}/$_", 0755 foreach qw(var var/ftp var/ftp/pub var/ftp/pub/Mandrivalinux var/ftp/pub/Mandrivalinux/media);
    local *changeMedium = sub {
	my ($method, $medium) = @_;
	my $name = install_medium::by_id($medium, $o->{packages})->{descr};
	if (method_allows_medium_change($method)) {
	    my $r;
	    if ($method =~ /-iso$/) {
		$r = changeIso($name);
	    } else {
		cat_("/proc/mounts") =~ m,(/dev/\S+)\s+(/mnt/cdrom|/tmp/image),
		    and ($cdrom, my $mountpoint) = ($1, $2);
		ejectCdrom($cdrom, $mountpoint);
		$r = $o->ask_okcancel('', N("Change your Cd-Rom!
Please insert the Cd-Rom labelled \"%s\" in your drive and press Ok when done.", $name), 1);
	    }
	    return $r;
	} else {
	    return 1;
	}
    };
    foreach my $k (pkgs::allMediums($o->{packages})) {
	my $m = install_medium::by_id($k, $o->{packages});
	#- don't copy rpms of supplementary media
	next if $m->is_suppl;
	my ($wait_w, $wait_message) = fs::format::wait_message($o); #- nb, this is only called when interactive
	$wait_message->(N("Copying in progress") . "\n($m->{descr})"); #- XXX to be translated
	if ($k != $current_medium) {
	    my $cd_k = $m->get_cd_number;
	    my $cd_cur = install_medium::by_id($current_medium, $o->{packages})->get_cd_number;
	    $cd_k ne $cd_cur and do {
		askChangeMedium($o->{method}, $k)
		    or next;
		mountCdrom("/tmp/image", $cdrom) if $o->{method} eq 'cdrom';
	    } while !-d "/tmp/image/$m->{rpmsdir}";
	    $current_medium = $k;
	}
	log::l("copying /tmp/image/$m->{rpmsdir} to $o->{prefix}/var/ftp/pub/Mandrivalinux/media");
	my $total = count_files("/tmp/image/$m->{rpmsdir}");
	log::l("($total files)");
	eval {
	    cp_with_progress($wait_message, 0, $total, "/tmp/image/$m->{rpmsdir}", "$o->{prefix}/var/ftp/pub/Mandrivalinux/media");
	};
	log::l($@) if $@;
	$m->{prefix} = "$o->{prefix}/var/ftp/pub/Mandrivalinux";
	$m->{method} = 'disk';
	$m->{with_hdlist} = 'media_info/hdlist.cz'; #- for install_urpmi
	undef $wait_w;
    }
    ejectCdrom() if $o->{method} eq "cdrom";
    #- now the install will continue as 'disk'
    $o->{method} = 'disk';
    #- should be enough to fool errorOpeningFile
    $current_medium = 1;
    our $copied_rpms_on_disk = 1;
}

sub set_rpmsrate_default_category_flags {
    my ($o, $rpmsrate_flags_was_chosen) = @_;

    #- if no cleaning needed, populate by default, clean is used for second or more call to this function.
    if ($::auto_install && ($o->{rpmsrate_flags_chosen} || {})->{CAT_ALL}) {
	$o->{rpmsrate_flags_chosen}{"CAT_$_"} = 1 foreach map { @{$_->{flags}} } @{$o->{compssUsers}};
    }
    if (!$rpmsrate_flags_was_chosen && !$o->{isUpgrade}) {
	#- use default selection seen in compssUsers directly.
	$_->{selected} = $_->{default_selected} foreach @{$o->{compssUsers}};
	set_rpmsrate_category_flags($o, $o->{compssUsers});
    }
}

sub set_rpmsrate_category_flags {
    my ($o, $compssUsers) = @_;

    $o->{rpmsrate_flags_chosen}{$_} = 0 foreach grep { /^CAT_/ } keys %{$o->{rpmsrate_flags_chosen}};
    $o->{rpmsrate_flags_chosen}{"CAT_$_"} = 1 foreach map { @{$_->{flags}} } grep { $_->{selected} } @$compssUsers;
    $o->{rpmsrate_flags_chosen}{CAT_SYSTEM} = 1;
}


sub rpmsrate_always_flags {
    my ($o) = @_;

    my $rpmsrate_flags_chosen = {};
    $rpmsrate_flags_chosen->{uc($_)} = 1 foreach grep { modules::probe_category("multimedia/$_") } modules::sub_categories('multimedia');
    $rpmsrate_flags_chosen->{uc($_)} = 1 foreach detect_devices::probe_name('Flag');
    $rpmsrate_flags_chosen->{DOCS} = !$o->{excludedocs};
    $rpmsrate_flags_chosen->{UTF8} = $o->{locale}{utf8};
    $rpmsrate_flags_chosen->{BURNER} = 1 if detect_devices::burners();
    $rpmsrate_flags_chosen->{DVD} = 1 if detect_devices::dvdroms();
    $rpmsrate_flags_chosen->{USB} = 1 if $o->{modules_conf}->get_probeall("usb-interface");
    $rpmsrate_flags_chosen->{PCMCIA} = 1 if detect_devices::hasPCMCIA();
    $rpmsrate_flags_chosen->{HIGH_SECURITY} = 1 if $o->{security} > 3;
    $rpmsrate_flags_chosen->{BIGMEM} = 1 if detect_devices::BIGMEM();
    $rpmsrate_flags_chosen->{SMP} = 1 if detect_devices::hasSMP();
    $rpmsrate_flags_chosen->{CDCOM} = 1 if any { $_->{descr} =~ /commercial/i } values %{$o->{packages}{mediums}};
    $rpmsrate_flags_chosen->{TV} = 1 if detect_devices::getTVcards();
    $rpmsrate_flags_chosen->{'3D'} = 1 if 
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

    foreach (lang::langsLANGUAGE($o->{locale}{langs})) {
	$rpmsrate_flags_chosen->{qq(LOCALES"$_")} = 1;
    }
    $rpmsrate_flags_chosen->{'CHARSET"' . lang::l2charset($o->{locale}{lang}) . '"'} = 1;

    $rpmsrate_flags_chosen;
}

sub default_packages {
    my ($o) = @_;
    my @l;

    push @l, "brltty" if cat_("/proc/cmdline") =~ /brltty=/;
    push @l, "nfs-utils-clients" if $o->{method} eq "nfs";
    push @l, "numlock" if $o->{miscellaneous}{numlock};
    push @l, "mdadm" if !is_empty_array_ref($o->{all_hds}{raids});
    push @l, "lvm2" if !is_empty_array_ref($o->{all_hds}{lvms});
    push @l, "dmraid" if any { fs::type::is_dmraid($_) } @{$o->{all_hds}{hds}};
    push @l, "alsa", "alsa-utils" if any { $o->{modules_conf}->get_alias("sound-slot-$_") =~ /^snd-/ } 0 .. 4;
    push @l, detect_devices::probe_name('Pkg');

    my $dmi_BIOS = detect_devices::dmidecode_category('BIOS');
    my $dmi_Base_Board = detect_devices::dmidecode_category('Base Board');
    if ($dmi_BIOS->{Vendor} eq 'COMPAL' && $dmi_BIOS->{Characteristics} =~ /Function key-initiated network boot is supported/
          || $dmi_Base_Board->{Manufacturer} =~ /^ACER/ && $dmi_Base_Board->{'Product Name'} =~ /TravelMate 610/) {
	#- FIXME : append correct options (wireless, ...)
	modules::append_to_modules_loaded_at_startup_for_all_kernels('acerhk');
    }

    push @l, "grub" if isLoopback(fs::get::root($o->{fstab}));
    push @l, uniq(grep { $_ } map { fs::format::package_needed_for_partition_type($_) } @{$o->{fstab}});

    my @locale_pkgs = map { pkgs::packagesProviding($o->{packages}, 'locales-' . $_) } lang::langsLANGUAGE($o->{locale}{langs});
    unshift @l, uniq(map { $_->name } @locale_pkgs);

    @l;
}

sub select_default_packages {
    my ($o) = @_;
    pkgs::selectPackage($o->{packages}, pkgs::packageByName($o->{packages}, $_) || next) foreach @{$o->{default_packages}};
}

sub unselectMostPackages {
    my ($o) = @_;
    pkgs::unselectAllPackages($o->{packages});
    select_default_packages($o);
}

sub warnAboutNaughtyServers {
    my ($o) = @_;
    my @naughtyServers = pkgs::naughtyServers($o->{packages}) or return 1;
    my $r = $o->ask_from_list_('', 
formatAlaTeX(
             #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
             N("You have selected the following server(s): %s


These servers are activated by default. They do not have any known security
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
    authentication::set($o, $o->{net}, $o->{authentication} ||= {}, $when_network_is_up);
}

sub killCardServices() {
    my $pid = chomp_(cat_("/tmp/cardmgr.pid"));
    $pid and kill(15, $pid); #- send SIGTERM
}

sub unlockCdrom() {
    my $cdrom = cat_("/proc/mounts") =~ m!(/dev/\S+)\s+(?:/mnt/cdrom|/tmp/image)! && $1 or return;
    eval { ioctl(detect_devices::tryOpen($cdrom), c::CDROM_LOCKDOOR(), 0) };
    $@ and log::l("unlock cdrom ($cdrom) failed: $@");
}

sub openCdromTray {
    my ($cdrom) = @_;
    eval { ioctl(detect_devices::tryOpen($cdrom), c::CDROMEJECT(), 1) };
    $@ and log::l("ejection failed: $@");
}

sub ejectCdrom {
    my ($o_cdrom, $o_mountpoint) = @_;
    getFile("XXX"); #- close still opened filehandle
    my $cdrom;
    my $mounts = cat_("/proc/mounts");
    if ($o_mountpoint) {
	$cdrom = $o_cdrom || $mounts =~ m!(/dev/\S+)\s+(/mnt/cdrom|/tmp/image)! && $1;
    } else {
	my $mntpt;
	if ($o_cdrom) {
	    $cdrom = $mounts =~ m!((?:/dev/)?$o_cdrom)\s+(/mnt/cdrom|/tmp/image)! && $1;
	    $mntpt = $2;
	} else {
	    $cdrom = $mounts =~ m!(/dev/\S+)\s+(/mnt/cdrom|/tmp/image)! && $1;
	    $mntpt = $2;
	}
	$o_mountpoint ||= $cdrom ? $mntpt || '/tmp/image' : '';
    }
    $cdrom ||= $o_cdrom;

    #- umount BEFORE opening the cdrom device otherwise the umount will
    #- D state if the cdrom is already removed
    $o_mountpoint and eval { fs::mount::umount($o_mountpoint) };
    $@ and warnAboutFilesStillOpen();
    return if is_xbox();
    openCdromTray($cdrom);
}

sub warnAboutFilesStillOpen() {
    log::l("files still open: ", readlink($_)) foreach map { glob_("$_/fd/*") } glob_("/proc/*");
}

sub install_urpmi {
    my ($method, $packages) = @_;

    my @mediums = values %{$packages->{mediums}};
    my $hdInstallPath = any::hdInstallPath();

    #- rare case where urpmi cannot be installed (no hd install path).
    our $copied_rpms_on_disk;
    $method eq 'disk' && !$hdInstallPath && !$copied_rpms_on_disk and return;

    log::l("install_urpmi $method");
    #- clean to avoid opening twice the rpm db.
    delete $packages->{rpmdb};

    #- import pubkey in rpmdb.
    my $db = pkgs::rpmDbOpenForInstall();
    $packages->parse_pubkeys(db => $db);
    foreach my $medium (@mediums) {
	$packages->import_needed_pubkeys($medium->{pubkey}, db => $db, callback => sub {
					     my (undef, undef, $_k, $id, $imported) = @_;
					     if ($id) {
						 log::l(($imported ? "imported" : "found") . " key=$id for medium $medium->{descr}");
						 $medium->{key_ids}{$id} = undef;
					     }
					 });
    }

    my @cfg;
    foreach (sort { $a->{medium} <=> $b->{medium} } @mediums) {
	my $name = $_->{fakemedium};
	if ($_->selected) {
	    my $curmethod = $_->method || $::o->{method};
	    my $dir = (($copied_rpms_on_disk ? "/var/ftp/pub/Mandrivalinux" : '')
		|| $_->{finalprefix}
		|| $_->{prefix}
		|| ${{ nfs => "file://mnt/nfs", 
		       disk => "file:/" . $hdInstallPath,
		       ftp => $ENV{URLPREFIX},
		       http => $ENV{URLPREFIX},
		       cdrom => "removable://mnt/cdrom" }}{$curmethod}
		|| #- for live_update or live_install script.
		   readlink("/tmp/image/media") =~ m,^(/.*)/media/*$, && "removable:/$1") . "/$_->{rpmsdir}";
	    #- use list file only if visible password or macro.
	    my $need_list = $dir =~ m,^(?:[^:]*://[^/:\@]*:[^/:\@]+\@|.*%{),; #- }

            my $removable_device;

            if ($curmethod eq 'disk-iso') {
                my $p = find { $_->{real_mntpoint} eq '/tmp/hdimage' } @{$::o->{fstab}} or
                  log::l("unable to find ISO image mountpoint, not adding urpmi media"), next;
                my $iso_info = find_ISO_image_labelled($_->{descr}) or
                  log::l("unable to find ISO image labelled $name, not adding urpmi media"), next;
                my ($iso_path) = $iso_info->{file} =~ m,^/tmp/hdimage/+(.*), or
                  log::l("unable to find ISO image file name ($iso_info->{file}), not adding urpmi media"), next;
                my $dest = "/mnt/inst_iso";
                $dir = "removable:/$dest/$_->{rpmsdir}";
                -d "$::prefix$dest" or mkdir_p("$::prefix$dest");
                #- FIXME: don't use /mnt/hd but really try to find the mount point
                $removable_device = ($p->{mntpoint} || "/mnt/hd") . "/$iso_path";
            } elsif ($curmethod eq 'cdrom') {
                $removable_device = '/dev/cdrom';
		my $p; $p = fs::get::mntpoint2part("/tmp/image", $::o->{fstab})
		    and $removable_device = $p->{device};
		$_->{static} = 1;
            }

	    #- build a list file if needed.
	    if ($need_list) {
		my $mask = umask 077;
		open(my $LIST, ">$::prefix/var/lib/urpmi/list.$name") or log::l("failed to write list.$name");
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
		    open(my $F, "parsehdlist '$::prefix/var/lib/urpmi/hdlist.$name.cz' |");
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

	    #- build a names file
	    if (open my $F, ">", "$::prefix/var/lib/urpmi/names.$name") {
		if (defined $_->{start} && defined $_->{end}) {
		    foreach ($_->{start} .. $_->{end}) {
			print $F $packages->{depslist}[$_]->name . "\n";
		    }
		}
		close $F;
	    }

	    #- build synthesis file if there are still not existing (ie not copied from mirror).
	    if (-s "$::prefix/var/lib/urpmi/synthesis.hdlist.$name.cz" <= 32) {
		unlink "$::prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";
		run_program::rooted($::prefix, "parsehdlist", ">", "/var/lib/urpmi/synthesis.hdlist.$name",
				    "--synthesis", "/var/lib/urpmi/hdlist.$name.cz");
		run_program::rooted($::prefix, "gzip", "-S", ".cz", "/var/lib/urpmi/synthesis.hdlist.$name");
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
  key-ids: " . join(',', keys(%{$_->{key_ids}})) : "") . (defined $removable_device && "
  removable: $removable_device") . ($_->{update} ? "
  update" : "") . ($_->{static} ? "
  static" : "") . "
}

";
	} else {
	    #- remove deselected media by removing copied hdlist and synthesis files
	    log::l("removing media $name");
	    unlink "$::prefix/var/lib/urpmi/hdlist.$name.cz";
	    unlink "$::prefix/var/lib/urpmi/synthesis.hdlist.$name.cz";
	}
    }
    #- touch a MD5SUM file and write config file
    eval { output("$::prefix/var/lib/urpmi/MD5SUM", '') };
    eval { output "$::prefix/etc/urpmi/urpmi.cfg", @cfg };
}


#-###############################################################################
#- kde stuff
#-###############################################################################
sub kdemove_desktop_file {
    my ($prefix) = @_;
    my @toMove = qw(doc.kdelnk news.kdelnk updates.kdelnk home.kdelnk printer.kdelnk floppy.kdelnk cdrom.kdelnk FLOPPY.kdelnk CDROM.kdelnk);

    #- remove any existing save in Trash of each user and
    #- move appropriate file there after an upgrade.
    foreach my $dir (grep { -d $_ } list_skels($prefix, 'Desktop')) {
	renamef("$dir/$_", "$dir/Trash/$_") 
	  foreach grep { -e "$dir/$_" } @toMove, grep { /\.rpmorig$/ } all($dir);
    }
}


#-###############################################################################
#- auto_install stuff
#-###############################################################################
sub auto_inst_file() { "$::prefix/root/drakx/auto_inst.cfg.pl" }

sub report_bug() {
    any::report_bug('auto_inst' => g_auto_install('', 1));
}

sub g_auto_install {
    my ($b_replay, $b_respect_privacy) = @_;
    my $o = {};

    require pkgs;
    $o->{default_packages} = pkgs::selected_leaves($::o->{packages});

    my @fields = qw(mntpoint fs_type size);
    $o->{partitions} = [ map { 
	my %l; @l{@fields} = @$_{@fields}; \%l;
    } grep { 
	$_->{mntpoint} && fs::format::known_type($_);
    } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(locale authentication mouse net timezone superuser keyboard users partitioning isUpgrade manualFstab nomouseprobe crypto security security_user libsafe useSupermount autoExitInstall X services postInstall postInstallNonRooted); #- TODO modules bootloader 

    $o->{printer} = $::o->{printer} if $::o->{printer};

    local $o->{partitioning}{auto_allocate} = !$b_replay;
    $o->{autoExitInstall} = !$b_replay;
    $o->{interactiveSteps} = [ 'doPartitionDisks', 'formatPartitions' ] if $b_replay;

    #- deep copy because we're modifying it below
    $o->{users} = $b_respect_privacy ? [] : [ @{$o->{users} || []} ];

    my @user_info_to_remove = (
	if_($b_respect_privacy, qw(realname pw)), 
	qw(oldu oldg password password2),
    );
    $_ = { %{$_ || {}} }, delete @$_{@user_info_to_remove} foreach $o->{superuser}, @{$o->{users} || []};

    if ($b_respect_privacy && $o->{net}) {
	if (my $type = $o->{net}{type}) {
	    my @net_type_to_remove = qw(passwd login phone_in phone_out);
	    $_ = { %{$_ || {}} }, delete @$_{@net_type_to_remove} foreach $o->{net}{$type};
	}
    }
    my $warn_privacy = $b_respect_privacy ? "!! This file has been simplified to respect privacy when reporting problems.
# You should use /root/drakx/auto_inst.cfg.pl instead !!\n#" : '';
    
    require Data::Dumper;
    my $str = join('', 
"#!/usr/bin/perl -cw
# $warn_privacy
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
	    find { eval { fs::mount::mount($dev, $mountdir, $_, 0); 1 } } qw(ext2 vfat) or return;

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
		    s/^(\s*append)/$1 $param/; 
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
	
	    fs::mount::umount($mountdir);
	    devices::del_loop($dev);
	}
	rmdir $mountdir;
	@imgs;
    }
}


sub g_default_packages {
    my ($o) = @_;

    my ($_h, $file) = media_browser($o, 'save', 'package_list.pl') or return;

    require Data::Dumper;
    my $str = Data::Dumper->Dump([ { default_packages => pkgs::selected_leaves($o->{packages}) } ], ['$o']);
    $str =~ s/ {8}/\t/g;
    output($file,
	   "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl'\n" .
	   "# before testing.  To use it, boot with ``linux defcfg=floppy''\n" .
	   $str . "\0");
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file();
    my $o;
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? 'auto_inst.cfg' : "patch";
	unless ($::testing) {
            my $dev = devices::make(detect_devices::floppy());
            foreach my $fs (arch() =~ /sparc/ ? 'romfs' : ('ext2', 'vfat')) {
                eval { fs::mount::mount($dev, '/mnt', $fs, 'readonly'); 1 } and goto mount_ok;
            }
            die "Could not mount floppy [$dev]";
          mount_ok:
	    $f = "/mnt/$f";
	}
	-e $f or $f .= '.pl';

	my $_b = before_leaving {
	    fs::mount::umount("/mnt") unless $::testing;
	    modules::unload(qw(vfat fat));
	};
	$o = loadO($O, $f);
    } else {
	my $fh;
	if (ref $f) {
	    $fh = $f;
	} else {
	    -e "$f.pl" and $f .= ".pl" unless -e $f;

	    if (-e $f) { open $fh, $f } else { $fh = getFile($f) or die N("Error reading file %s", $f) }
	}
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
    #- {rpmsrate_flags_chosen} was called {compssUsersChoice}
    if (my $rpmsrate_flags_chosen = delete $o->{compssUsersChoice}) {
	$o->{rpmsrate_flags_chosen} = $rpmsrate_flags_chosen;
    }
    #- compssUsers flags are now named CAT_XXX
    if ($o->{rpmsrate_flags_chosen} &&
	! any { /^CAT_/ } keys %{$o->{rpmsrate_flags_chosen}}) {
	#- we don't really know if this is needed for compatibility, but it won't hurt :)
	foreach (keys %{$o->{rpmsrate_flags_chosen}}) {
	    $o->{rpmsrate_flags_chosen}{"CAT_$_"} = $o->{rpmsrate_flags_chosen}{$_};
	}
	#- it used to be always selected
	$o->{rpmsrate_flags_chosen}{CAT_SYSTEM} = 1;
    }

    #- backward compatibility for network fields
    exists $o->{intf} and $o->{net}{ifcfg} = delete $o->{intf};
    exists $o->{netcnx}{type} and $o->{net}{type} = delete $o->{netcnx}{type};
    exists $o->{netc}{NET_INTERFACE} and $o->{net}{net_interface} = delete $o->{netc}{NET_INTERFACE};
    my %netc_translation = (
			    resolv => [ qw(dnsServer dnsServer2 dnsServer3 DOMAINNAME DOMAINNAME2 DOMAINNAME3) ],
			    network => [ qw(NETWORKING FORWARD_IPV4 NETWORKING_IPV6 HOSTNAME GATEWAY GATEWAYDEV NISDOMAIN) ],
			    auth => [ qw(LDAPDOMAIN WINDOMAIN) ],
			   );
    foreach my $dest (keys %netc_translation) {
	exists $o->{netc}{$_} and $o->{net}{$dest}{$_} = delete $o->{netc}{$_} foreach @{$netc_translation{$dest}};
    }
    delete @$o{qw(netc netcnx)};

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
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/nfsimage| or internal_error("can not find nfsimage");
	@ks = (server => $1, directory => $2);
    }
    @ks = (method => $method, @ks);

    if (member($o->{method}, qw(http ftp nfs))) {
	if ($ENV{PROXY}) {
	    push @ks, proxy_host => $ENV{PROXY}, proxy_port => $ENV{PROXYPORT};
	}
	my $intf = first(values %{$o->{net}{ifcfg}});
	push @ks, interface => $intf->{DEVICE};
	if ($intf->{BOOTPROTO} eq 'dhcp') {
	    push @ks, network => 'dhcp';
	} else {
	    push @ks, network => 'static', ip => $intf->{IPADDR}, netmask => $intf->{NETMASK}, gateway => $o->{net}{network}{GATEWAY};
	    require network::network;
	    if (my @dnss = network::network::dnsServers($o->{net})) {
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

    if ($::local_install) {
	my $f = common::release_file('/mnt') or return;
	chomp(my $s = cat_("/mnt$f"));
	$s =~ s/\s+for\s+\S+//;
	return { release => $s, release_file => $f };
    }

    map { 
	my $handle = any::inspect($_, $prefix);
	if (my $f = $handle && common::release_file($handle->{dir})) {
	    chomp(my $s = cat_("$handle->{dir}$f"));
	    $s =~ s/\s+for\s+\S+//;
	    log::l("find_root_parts found $_->{device}: $s");
	    { release => $s, part => $_, release_file => $f };
	} else { () }
    } @$fstab;
}

sub migrate_device_names {
    my ($all_hds, $from_fstab, $new_root, $root_from_fstab, $o_in) = @_;

    log::l("warning: fstab says root partition is $root_from_fstab->{device}, whereas we were reading fstab from $new_root->{device}");
    my ($old_prefix, $old_part_number) = devices::simple_partition_scan($root_from_fstab);
    my ($new_prefix, $new_part_number) = devices::simple_partition_scan($new_root);

    if ($old_part_number != $new_part_number) {
	log::l("argh, $root_from_fstab->{device} and $old_part_number->{device} are not the same partition number");
	return;
    }

    log::l("replacing $old_prefix with $new_prefix");
    
    my %h;
    foreach (@$from_fstab) {
	if ($_->{device} =~ s!^\Q$old_prefix!$new_prefix!) {
	    #- this is simple to handle, nothing more to do
	} elsif ($_->{part_number}) {
	    my $device_prefix = devices::part_prefix($_);
	    push @{$h{$device_prefix}}, $_;
	} else {
	    #- hopefully this does not need anything special
	}
    }
    my @from_fstab_per_hds = values %h or return;


    my @current_hds = grep { $new_root->{rootDevice} ne $_->{device} } fs::get::hds($all_hds);

    found_one:
    @from_fstab_per_hds or return;

    foreach my $from_fstab_per_hd (@from_fstab_per_hds) {
	my ($matching, $other) = partition { 
	    my $hd = $_;
	    every {
		my $wanted = $_;
		my $part = find { $_->{part_number} eq $wanted->{part_number} } partition_table::get_normal_parts($hd);
		$part && $part->{fs_type} && fs::type::can_be_this_fs_type($wanted, $part->{fs_type});
	    } @$from_fstab_per_hd;
	} @current_hds;
	@$matching == 1 or next;

	my ($hd) = @$matching;
	@current_hds = @$other;
	@from_fstab_per_hds = grep { $_ != $from_fstab_per_hd } @from_fstab_per_hds;

	log::l("$hd->{device} nicely corresponds to " . join(' ', map { $_->{device} } @$from_fstab_per_hd));
	foreach (@$from_fstab_per_hd) {
	    partition_table::compute_device_name($_, $hd);
	}
	goto found_one;
    }
	
    #- we can not find one and only one matching hd
    my @from_fstab_not_handled = map { @$_ } @from_fstab_per_hds;
    log::l("we still do not know what to do with: " . join(' ', map { $_->{device} } @from_fstab_not_handled));


    if (!$o_in) {
	die 'still have';
	log::l("well, ignoring them!");
	return;
    }

    my $propositions_valid = every {
	my $wanted = $_;
	my @parts = grep { $_->{part_number} eq $wanted->{part_number}
			     && $_->{fs_type} && fs::type::can_be_this_fs_type($wanted, $_->{fs_type}) } fs::get::hds_fstab(@current_hds);
	$wanted->{propositions} = \@parts;
	@parts > 0;
    } @from_fstab_not_handled;

    $o_in->ask_from('', 
		    N("The following disk(s) were renamed:"),
		    [ map {
			{ label => N("%s (previously named as %s)", $_->{mntpoint}, $_->{device}),
			  val => \$_->{device}, format => sub { $_[0] && $_->{device} },
			  list => [ '', 
				    $propositions_valid ? @{$_->{propositions}} : 
				    fs::get::hds_fstab(@current_hds) ] };
		    } @from_fstab_not_handled ]);
}

sub use_root_part {
    my ($all_hds, $part, $o_in) = @_;
    my $migrate_device_names;
    {
	my $handle = any::inspect($part, $::prefix) or internal_error();

	my @from_fstab = fs::read_fstab($handle->{dir}, '/etc/fstab', 'keep_default');

	my $root_from_fstab = fs::get::root_(\@from_fstab);
	if (!fs::get::is_same_hd($root_from_fstab, $part)) {
	    $migrate_device_names = 1;
	    log::l("from_fstab contained: $_->{device} $_->{mntpoint}") foreach @from_fstab;
	    migrate_device_names($all_hds, \@from_fstab, $part, $root_from_fstab, $o_in);
	    log::l("from_fstab now contains: $_->{device} $_->{mntpoint}") foreach @from_fstab;
	}
	fs::add2all_hds($all_hds, @from_fstab);
	log::l("fstab is now: $_->{device} $_->{mntpoint}") foreach fs::get::fstab($all_hds);
    }
    isSwap($_) and $_->{mntpoint} = 'swap' foreach fs::get::really_all_fstab($all_hds); #- use all available swap.
    $migrate_device_names;
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
    fs::merge_info_from_mtab($o->{fstab}) if !$::local_install;

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

my %media_browser;
sub media_browser {
    my ($in, $save, $o_suggested_name) = @_;

    my %media_type2text = (
	fd => N("Floppy"),
	hd => N("Hard Disk"),
	cdrom => N("CDROM"),
    );
    my @network_protocols = (if_(!$save, N_("HTTP")), N_("FTP"), N_("NFS"));

    my $to_text = sub {
	my ($hd) = @_;
	($media_type2text{$hd->{media_type}} || $hd->{media_type}) . ': ' . partition_table::description($hd);
    };

  ask_media:
    my $all_hds = fsedit::get_hds({}, $in);
    fs::get_raw_hds('', $all_hds);

    my @raw_hds = grep { !$save || $_->{media_type} ne 'cdrom' } @{$all_hds->{raw_hds}};
    my @dev_and_text = group_by2(
	(map { $_ => $to_text->($_) } @raw_hds),
	(map { 
	    my $hd = $to_text->($_);
	    map { $_ => join('\1', $hd, partition_table::description($_)) } grep { isTrueFS($_) || isOtherAvailableFS($_) } fs::get::hds_fstab($_);
	} fs::get::hds($all_hds)),
	if_(member($::o->{method}, qw(ftp http nfs)) || install_steps::hasNetwork($::o),
	    map { $_ => join('\1', N("Network"), translate($_)) } @network_protocols),
    );

    $in->ask_from_({
	messages => N("Please choose a media"),
    }, [ 
	{ val => \$media_browser{dev}, separator => '\1', list => [ map { $_->[1] } @dev_and_text ] },
    ]) or return;

    my $dev = (find { $_->[1] eq $media_browser{dev} } @dev_and_text)->[0];

    my $browse = sub {
	my ($dir) = @_;

      browse:
	my $file = $in->ask_filename({ save => $save, 
				       directory => $dir, 
				       if_($o_suggested_name, file => "$dir/$o_suggested_name"),
				   }) or return;
	if (-e $file && $save) {
	    $in->ask_yesorno('', N("File already exists. Overwrite it?")) or goto browse;
	}
	if ($save) {
	    if (!open(my $_fh, ">>$file")) {
		$in->ask_warn('', N("Permission denied"));
		goto browse;
	    }
	    $file;
	} else {
	    open(my $fh, $file) or goto browse;
	    $fh;
	}
    };
    my $inspect_and_browse = sub {
	my ($dev) = @_;

	if (my $h = any::inspect($dev, $::prefix, $save)) {
	    if (my $file = $browse->($h->{dir})) {
		return $h, $file;
	    }
	    undef $h; #- help perl
	} else {
	    $in->ask_warn(N("Error"), formatError($@));
	}
	();
    };

    if (member($dev, @network_protocols)) {
	require install_interactive;
	install_interactive::upNetwork($::o);

	if ($dev eq 'HTTP') {
	    require http;
	    $media_browser{url} ||= 'http://';

	    while (1) {
		$in->ask_from('', 'URL', [
		    { val => \$media_browser{url} }
		]) or last;
		    
		if ($dev eq 'HTTP') {
		    my $fh = http::getFile($media_browser{url});
		    $fh and return '', $fh;
		}
	    }
	} elsif ($dev eq 'NFS') {
	    while (1) {
		$in->ask_from('', 'NFS', [
		    { val => \$media_browser{nfs} }
		]) or last;

		my ($kind) = fs::wild_device::analyze($media_browser{nfs});
		if ($kind ne 'nfs') {
		    $in->ask_warn('', N("Bad NFS name"));
		    next;
		}

		my $nfs = fs::wild_device::to_subpart($media_browser{nfs});
		$nfs->{fs_type} = 'nfs';

		if (my ($h, $file) = $inspect_and_browse->($nfs)) {
		    return $h, $file;
		}
	    }
	} else {
	    $in->ask_warn('', 'todo');
	    goto ask_media;
	}
    } else {
	if (!$dev->{fs_type} || $dev->{fs_type} eq 'auto' || $dev->{fs_type} =~ /:/) {
	    if (my $p = fs::type::type_subpart_from_magic($dev)) {
		add2hash($p, $dev);
		$dev = $p;
	    } else {
		$in->ask_warn(N("Error"), N("Bad media %s", partition_table::description($dev)));
		goto ask_media;
	    }
	}

	if (my ($h, $file) = $inspect_and_browse->($dev)) {
	    return $h, $file;
	}

	goto ask_media;
    }
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

sub screenshot_dir__and_move() {
    my ($dir1, $dir2) = ("$::prefix/root", '/tmp');
    if (-e $dir1) {
	if (-e "$dir2/DrakX-screenshots") {
	    cp_af("$dir2/DrakX-screenshots", $dir1);
	    rm_rf("$dir2/DrakX-screenshots");
	}
	$dir1;
    } else {
	$dir2;
    }
}

sub take_screenshot {
    my ($in) = @_;
    my $dir = screenshot_dir__and_move() . '/DrakX-screenshots';
    my $warn;
    if (!-e $dir) {
	mkdir $dir or $in->ask_warn('', N("Can not make screenshots before partitioning")), return;
	$warn = 1;
    }
    my $nb = 1;
    $nb++ while -e "$dir/$nb.png";
    system("fb2png /dev/fb0 $dir/$nb.png 0");

    $in->ask_warn('', N("Screenshots will be available after install in %s", "/root/DrakX-screenshots")) if $warn;
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
    require security::various;
    security::level::set($o->{security});
    security::various::config_libsafe($::prefix, $o->{libsafe});
    security::various::config_security_user($::prefix, $o->{security_user});
}

sub write_fstab {
    my ($o) = @_;
    fs::write_fstab($o->{all_hds}, $o->{prefix}) if !$o->{isUpgrade} || $o->{migrate_device_names};
}

my $clp_name = 'mdkinst.clp';
sub clp_on_disk() { "$::prefix/tmp/$clp_name" }

sub move_clp_to_disk() {
    return if -e clp_on_disk() || $::local_install;

    my ($loop, $current_clp) = devices::find_clp_loop($clp_name) or return;
    log::l("move_clp_to_disk: copying $current_clp to ", clp_on_disk());
    cp_af($current_clp, clp_on_disk());
    run_program::run('losetup', '-r', $loop, clp_on_disk());

    #- in $current_clp eq "/tmp/$clp_name"
    unlink "/tmp/$clp_name";
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

    #- ds is an alias for pcmcia in recent 2.6 kernels
    #- but we don't have modules.alias in install, so try to load both
    eval { modules::load('pcmcia', $pcic, 'ds', 'pcmcia') };

    #- run cardmgr in foreground while it is configuring the card.
    run_program::run("cardmgr", "-f", "-m", "/modules");
    sleep(3);
    
    #- make sure to be aware of loaded module by cardmgr.
    modules::read_already_loaded($modules_conf);
}

1;
