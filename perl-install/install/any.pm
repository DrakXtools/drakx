package install::any; # $Id$

use strict;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(addToBeDone);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use run_program;
use fs::type;
use fs::format;
use fs::any;
use partition_table;
use devices;
use modules;
use detect_devices;
use install::media 'getFile_';
use lang;
use any;
use log;

our @advertising_images;

sub drakx_version { 
    my ($o) = @_;

	my $version = cat__(getFile_($o->{stage2_phys_medium}, "install/stage2/VERSION"));
	sprintf "DrakX v%s", chomp_($version);
}

#-######################################################################################
#- Functions
#-######################################################################################
sub dont_run_directly_stage2() {
    readlink("/usr/bin/runinstall2") eq "runinstall2.sh";
}

sub is_network_install {
    my ($o) = @_;
    member($o->{method}, qw(ftp http nfs));
}


sub start_i810fb() {
    my ($vga) = cat_('/proc/cmdline') =~ /vga=(\S+)/;
    return if !$vga || listlength(cat_('/proc/fb'));

    my %vga_to_xres = (0x311 => '640', 0x314 => '800', 0x317 => '1024');
    my $xres = $vga_to_xres{$vga} || '800';

    log::l("trying to load i810fb module with xres <$xres> (vga was <$vga>)");
    eval { modules::load('intel_agp') };
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

    print drakx_version($::o), "\n";

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

    my $n = !$::testing && getAvailableSpace_mounted($::prefix) || 
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
	return MB($nb);
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

sub ask_suppl_media_method {
    my ($o) = @_;
    our $suppl_already_asked;

    my $msg = $suppl_already_asked
      ? N("Do you have further supplementary media?")
      : formatAlaTeX(
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
	    N("The following media have been found and will be used during install: %s.


Do you have a supplementary installation medium to configure?",
	    join(", ", map { $_->{name} } install::media::allMediums($o->{packages}))));

    my %l = my @l = (
	''      => N("None"),
	'cdrom' => N("CD-ROM"),
	'http'  => N("Network (HTTP)"),
	'ftp'   => N("Network (FTP)"),
	'nfs'   => N("Network (NFS)"),
    );

    $o->ask_from(
	'', $msg,
	[ {
	    val => \my $suppl,
	    list => [ map { $_->[0] } group_by2(@l) ],
	    type => 'list',
	    format => sub { $l{$_[0]} },
	} ],
    );

    $suppl_already_asked = 1;
    $suppl;
}

#- if the supplementary media is networked, but not the main one, network
#- support must be installed and network started.
sub prep_net_suppl_media {
    my ($o) = @_;

    require network::tools;
    my (undef, $is_up, undef) = network::tools::get_internet_connection($o->{net});

    return if our $net_suppl_media_configured && $is_up;
    $net_suppl_media_configured = 1;

    #- install basesystem now
    $o->do_pkgs->ensure_is_installed('basesystem', undef, 1);

    require network::netconnect;
    network::netconnect::real_main($o->{net}, $o, $o->{modules_conf});
    require install::interactive;
    install::interactive::upNetwork($o);
    sleep(3);
}

sub ask_url {
    my ($in, $o_url) = @_;

    my $url = $o_url;
    $in->ask_from_({ messages => N("URL of the mirror?"), focus_first => 1 }, [ 
	{ val => \$url,
	  validate => sub { 
	      if ($url =~ m!^(http|ftp)://!) {
		  1;
	      } else {
		  $in->ask_warn('', N("URL must start with ftp:// or http://"));
		  0;
	      }
	  } } ]) && $url;
}
sub ask_mirror {
    my ($o, $type, $o_url) = @_;
    
    require mirror;

    my $mirrors = eval {
	my $_w = $o->wait_message('', N("Contacting Mandriva Linux web site to get the list of available mirrors..."));
	mirror::list($o->{product_id}, $type);
    };
    my $err = $@;
    if (!$mirrors) {
	$o->ask_warn('', N("Failed contacting Mandriva Linux web site to get the list of available mirrors") . "\n$err");
	return ask_url($o, $o_url);
    }

    my $give_url = { country => '-', host => 'URL' };

    my $mirror = $o_url ? (find { $_->{url} eq $o_url } @$mirrors) || $give_url 
        #- use current time zone to select best mirror
      : mirror::nearest($o->{timezone}{timezone}, $mirrors);

    $o->ask_from_({ messages => N("Choose a mirror from which to get the packages"),
		    cancel => N("Cancel"),
		}, [ { separator => '|',
		       format => \&mirror::mirror2text,
		       list => [ @$mirrors, $give_url ],
		       val => \$mirror,
		   },
		 ]) or return;

    my $url;
    if ($mirror eq $give_url) {
	$url = ask_url($o, $o_url) or goto &ask_mirror;
    } else {
	$url = $mirror->{url};
    }
    $url =~ s!/main/?$!!;
    log::l("chosen mirror: $url");
    $url;
}

sub ask_suppl_media_url {
    my ($o, $method, $o_url) = @_;

    if ($method eq 'ftp' || $method eq 'http') {
	install::any::ask_mirror($o, 'distrib', $o_url);
    } elsif ($method eq 'cdrom') {
	'cdrom://';
    } elsif ($method eq 'nfs') {
	my ($host, $dir) = $o_url ? $o_url =~ m!nfs://(.*?)(/.*)! : ();
	$o->ask_from_(
	    { title => N("NFS setup"), 
	      messages => N("Please enter the hostname and directory of your NFS media"),
	      focus_first => 1,
	      callbacks => {
		  complete => sub {
		      $host or $o->ask_warn('', N("Hostname missing")), return 1, 0;
		      $dir eq '' || begins_with($dir, '/') or $o->ask_warn('', N("Directory must begin with \"/\"")), return 1, 1;
		      0;
		  },
	      } },
	    [ { label => N("Hostname of the NFS mount ?"), val => \$host }, 
	      { label => N("Directory"), val => \$dir } ],
	) or return;
	$dir =~ s!/+$!!; 
	$dir ||= '/';
	"nfs://$host$dir";
    } else { internal_error("bad method $method") }
}
sub selectSupplMedia {
    my ($o) = @_;
    my $url;

  ask_method:
    my $method = ask_suppl_media_method($o) or return;

    #- configure network if needed
    if (!scalar keys %{$o->{net}{ifcfg}} && $method !~ /^(?:cdrom|disk)/ && !$::local_install) {
	prep_net_suppl_media($o);
    }

  ask_url:
    $url = ask_suppl_media_url($o, $method, $url) or goto ask_method;

    my $phys_medium = install::media::url2mounted_phys_medium($o, $url, undef, N("Supplementary")) or $o->ask_warn('', formatError($@)), goto ask_url;
    $phys_medium->{is_suppl} = 1;
    $phys_medium->{unknown_CD} = 1;

    my $arch = $o->{product_id}{arch};
    my $field = $phys_medium->{device} ? 'rel_path' : 'url';
    my $val = $phys_medium->{$field};
    my $val0 = $val =~ m!^(.*?)(/media)?/?$! && "$1/media";
    my $val2 = $val =~ m!^(.*?)(/\Q$arch\E)?(/media)?/?$! && "$1/$arch/media";

    foreach (uniq($val0, $val, $val2)) {
	log::l("trying with $field set to $_");
	$phys_medium->{$field} = $_;

	#- first, try to find a media.cfg file
	eval { install::media::get_media_cfg($o, $phys_medium, $o->{packages}, undef, 'force_rpmsrate') };
	if (!$@) {
	    delete $phys_medium->{unknown_CD}; #- we have a known CD now
	    return 1;
	}
    }
    #- restore it
    $phys_medium->{$field} = $val;

    #- try using media_info/hdlist.cz
    my $medium_id = int(@{$o->{packages}{media}});
    eval { install::media::get_standalone_medium($o, $phys_medium, $o->{packages}, { name => "Supplementary media $medium_id" }) };
    if (!$@) {
	log::l("read suppl hdlist (via $method)");
	delete $phys_medium->{unknown_CD}; #- we have a known CD now
	return 1;
    }

    install::media::umount_phys_medium($phys_medium);
    install::media::remove_from_fstab($o->{all_hds}, $phys_medium);
    $o->ask_warn('', N("Can't find a package list file on this mirror. Make sure the location is correct."));
    goto ask_url;
}

sub load_rate_files {
    my ($o) = @_;
    #- must be done after getProvides

    install::pkgs::read_rpmsrate($o->{packages}, $o->{rpmsrate_flags_chosen}, '/tmp/rpmsrate', $o->{match_all_hardware});

    ($o->{compssUsers}, $o->{gtk_display_compssUsers}) = install::pkgs::readCompssUsers('/tmp/compssUsers.pl');

    defined $o->{compssUsers} or die "Can't read compssUsers.pl file, aborting installation\n";
}

sub setPackages {
    my ($o) = @_;

    require install::pkgs;
    {
	$o->{packages} = install::pkgs::empty_packages($o->{keep_unrequested_dependencies});
	
	my $media = $o->{media} || [ { type => 'media_cfg', url => 'drakx://media' } ];

	my ($suppl_method, $copy_rpms_on_disk) = install::media::get_media($o, $media, $o->{packages});

	if ($suppl_method) {
	    1 while $o->selectSupplMedia;
	}

	#- open rpm db according to right mode needed
	$o->{packages}{rpmdb} ||= install::pkgs::rpmDbOpen('rebuild_if_needed', $o->{rpm_dbapi});

	{
	    my $_wait = $o->wait_message('', N("Looking at packages already installed..."));
	    install::pkgs::selectPackagesAlreadyInstalled($o->{packages});
	}

	if (my $extension = $o->{upgrade_by_removing_pkgs_matching}) {
	    my $time = time();
	    my ($_w, $wait_message) = $o->wait_message_with_progress_bar;
	    $wait_message->(N("Removing packages prior to upgrade..."));
	    my ($current, $total);
	    my $callback = sub {
		my (undef, $type, $_id, $subtype, $amount) = @_;
		if ($type eq 'user') {
		    ($current, $total) = (0, $amount);
		} elsif ($type eq 'uninst' && $subtype eq 'stop') {
		    $wait_message->('', $current++, $total);
		}
	    };
	    push @{$o->{default_packages}}, install::pkgs::upgrade_by_removing_pkgs($o->{packages}, $callback, $extension, $o->{isUpgrade});
	    log::l("Removing packages took: ", formatTimeRaw(time() - $time));
	}

	mark_skipped_packages($o);

	#- always try to select basic kernel (else on upgrade, kernel will never be updated provided a kernel is already
	#- installed and provides what is necessary).
	my $kernel_pkg = install::pkgs::bestKernelPackage($o->{packages}, $o->{match_all_hardware});
	install::pkgs::selectPackage($o->{packages}, $kernel_pkg, 1);
	if ($o->{isUpgrade} && $o->{packages}{sizes}{dkms}) {
	    log::l("selecting kernel-desktop-devel-latest (since dkms was installed)");
	    install::pkgs::select_by_package_names($o->{packages}, ['kernel-desktop-devel-latest'], 1);
	}

	install::pkgs::select_by_package_names_or_die($o->{packages}, ['basesystem'], 1);

	my $rpmsrate_flags_was_chosen = $o->{rpmsrate_flags_chosen};

	put_in_hash($o->{rpmsrate_flags_chosen} ||= {}, rpmsrate_always_flags($o)); #- must be done before install::pkgs::read_rpmsrate()
	load_rate_files($o);

	install::media::copy_rpms_on_disk($o) if $copy_rpms_on_disk;

	set_rpmsrate_default_category_flags($o, $rpmsrate_flags_was_chosen);

	push @{$o->{default_packages}}, default_packages($o);
	select_default_packages($o);
    }

    if ($o->{isUpgrade}) {
	{
	    my $_w = $o->wait_message('', N("Finding packages to upgrade..."));
	    install::pkgs::selectPackagesToUpgrade($o->{packages});
	}
	if ($o->{packages}{sizes}{'kdebase-progs'}) {
	    log::l("selecting task-kde (since kdebase-progs was installed)");
	    install::pkgs::select_by_package_names($o->{packages}, ['task-kde']);
	}
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
    cp_with_progress_({ keep_special => 1 }, $wait_message, $total, \@_, $dest);
}
sub cp_with_progress_ {
    my ($options, $wait_message, $total, $list, $dest) = @_;
    @$list or return;
    @$list == 1 || -d $dest or die "cp: copying multiple files, but last argument ($dest) is not a directory\n";

    -d $dest or $dest = dirname($dest);
    _cp_with_progress($options, $wait_message, 0, $total, $list, $dest);
}
sub _cp_with_progress {
    my ($options, $wait_message, $current, $total, $list, $dest) = @_;

    foreach my $src (@$list) {
	my $dest = $dest;
	-d $dest and $dest .= '/' . basename($src);

	unlink $dest;

	if (-l $src && $options->{keep_special}) {
	    unless (symlink(readlink($src) || die("readlink failed: $!"), $dest)) {
		warn "symlink: can't create symlink $dest: $!\n";
	    }
	} elsif (-d $src) {
	    -d $dest or mkdir $dest, (stat($src))[2] or die "mkdir: can't create directory $dest: $!\n";
	    _cp_with_progress($options, $wait_message, $current, $total, [ glob_($src) ], $dest);
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
    $o->{rpmsrate_flags_chosen}{CAT_MINIMAL_DOCS} = 1;
}


sub rpmsrate_always_flags {
    my ($o) = @_;

    my $rpmsrate_flags_chosen = {};
    $rpmsrate_flags_chosen->{qq(META_CLASS"$o->{meta_class}")} = 1;
    $rpmsrate_flags_chosen->{uc($_)} = 1 foreach grep { $o->{match_all_hardware} || detect_devices::probe_category("multimedia/$_") } modules::sub_categories('multimedia');
    $rpmsrate_flags_chosen->{uc($_)} = 1 foreach detect_devices::probe_name('Flag');
    $rpmsrate_flags_chosen->{UTF8} = $o->{locale}{utf8};
    $rpmsrate_flags_chosen->{BURNER} = 1 if $o->{match_all_hardware} || detect_devices::burners();
    $rpmsrate_flags_chosen->{DVD} = 1 if $o->{match_all_hardware} || detect_devices::dvdroms();
    $rpmsrate_flags_chosen->{USB} = 1 if $o->{match_all_hardware} || $o->{modules_conf}->get_probeall("usb-interface");
    $rpmsrate_flags_chosen->{PCMCIA} = 1 if $o->{match_all_hardware} || detect_devices::hasPCMCIA();
    $rpmsrate_flags_chosen->{HIGH_SECURITY} = 1 if $o->{security} > 3;
    $rpmsrate_flags_chosen->{BIGMEM} = 1 if detect_devices::BIGMEM();
    $rpmsrate_flags_chosen->{SMP} = 1 if $o->{match_all_hardware} || detect_devices::hasSMP();
    $rpmsrate_flags_chosen->{CDCOM} = 1 if any { $_->{name} =~ /commercial/i } install::media::allMediums($o->{packages});
    $rpmsrate_flags_chosen->{'3D'} = 1 if
      $o->{match_all_hardware} ||
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
    push @l, "mdadm" if !is_empty_array_ref($o->{all_hds}{raids});
    push @l, "lvm2" if !is_empty_array_ref($o->{all_hds}{lvms});
    push @l, "dmraid" if any { fs::type::is_dmraid($_) } @{$o->{all_hds}{hds}};
    push @l, 'powernowd' if cat_('/proc/cpuinfo') =~ /AuthenticAMD/ && arch() =~ /x86_64/
      || cat_('/proc/cpuinfo') =~ /model name.*Intel\(R\) Core\(TM\)2 CPU/;
    push @l, detect_devices::probe_name('Pkg');

    my $dmi_BIOS = detect_devices::dmidecode_category('BIOS');
    my $dmi_Base_Board = detect_devices::dmidecode_category('Base Board');
    if ($dmi_BIOS->{Vendor} eq 'COMPAL' && $dmi_BIOS->{Characteristics} =~ /Function key-initiated network boot is supported/
          || $dmi_Base_Board->{Manufacturer} =~ /^ACER/ && $dmi_Base_Board->{'Product Name'} =~ /TravelMate 610/) {
	#- FIXME : append correct options (wireless, ...)
	modules::append_to_modules_loaded_at_startup_for_all_kernels('acerhk');
    }

    push @l, 'quota' if any { $_->{options} =~ /usrquota|grpquota/ } @{$o->{fstab}};
    push @l, uniq(grep { $_ } map { fs::format::package_needed_for_partition_type($_) } @{$o->{fstab}});

    my @locale_pkgs = map { URPM::packages_providing($o->{packages}, 'locales-' . $_) } lang::langsLANGUAGE($o->{locale}{langs});
    unshift @l, uniq(map { $_->name } @locale_pkgs);

    @l;
}

sub mark_skipped_packages {
    my ($o) = @_;
    install::pkgs::skip_packages($o->{packages}, $o->{skipped_packages}) if $o->{skipped_packages};
}

sub select_default_packages {
    my ($o) = @_;
    install::pkgs::select_by_package_names($o->{packages}, $o->{default_packages});
}

sub unselectMostPackages {
    my ($o) = @_;
    install::pkgs::unselectAllPackages($o->{packages});
    select_default_packages($o);
}

sub warnAboutNaughtyServers {
    my ($o) = @_;
    my @naughtyServers = install::pkgs::naughtyServers($o->{packages}) or return 1;
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
	log::l("unselecting naughty servers: " . join(' ', @naughtyServers));
	install::pkgs::unselectPackage($o->{packages}, install::pkgs::packageByName($o->{packages}, $_)) foreach @naughtyServers;
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
	    require install::steps;
	    install::steps::upNetwork($o, 'pppAvoided');
	    $f->();
	} 'configureNetwork';
    };
    require authentication;
    authentication::set($o, $o->{net}, $o->{authentication} ||= {}, $when_network_is_up);
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

    require install::pkgs;
    $o->{default_packages} = install::pkgs::selected_leaves($::o->{packages});

    my @fields = qw(mntpoint fs_type size);
    $o->{partitions} = [ map { 
	my %l; @l{@fields} = @$_{@fields}; \%l;
    } grep { 
	$_->{mntpoint} && fs::format::known_type($_);
    } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(locale authentication mouse net timezone superuser keyboard users partitioning isUpgrade manualFstab nomouseprobe crypto security security_user libsafe autoExitInstall X services postInstall postInstallNonRooted); #- TODO modules bootloader 

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
", Data::Dumper->Dump([$o], ['$o']));
    $str =~ s/ {8}/\t/g; #- replace all 8 space char by only one tabulation, this reduces file size so much :-)
    $str;
}

sub getAndSaveAutoInstallFloppies {
    my ($o, $replay) = @_;
    my $name = ($replay ? 'replay' : 'auto') . '_install';
    my $dest_dir = "$::prefix/root/drakx";

    eval { modules::load('loop') };

    if (arch() =~ /ia64/) {
	#- nothing yet
    } else {
	my $mountdir = "$::prefix/root/aif-mount"; -d $mountdir or mkdir $mountdir, 0755;
	my $param = 'kickstart=floppy ' . generate_automatic_stage1_params($o);

	my $img = install::media::getAndSaveInstallFloppies($o, $dest_dir, $name) or return;

	{
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

	    {
		local $o->{partitioning}{clearall} = !$replay;
		eval { output("$mountdir/auto_inst.cfg", g_auto_install($replay)) };
		$@ and log::l("Warning: <", formatError($@), ">");
	    }
	
	    fs::mount::umount($mountdir);
	    devices::del_loop($dev);
	}
	rmdir $mountdir;
	$img;
    }
}


sub g_default_packages {
    my ($o) = @_;

    my ($_h, $file) = media_browser($o, 'save', 'package_list.pl') or return;

    require Data::Dumper;
    my $str = Data::Dumper->Dump([ { default_packages => install::pkgs::selected_leaves($o->{packages}) } ], ['$o']);
    $str =~ s/ {8}/\t/g;
    output($file,
	   "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl'\n" .
	   "# before testing.  To use it, boot with ``linux defcfg=floppy''\n" .
	   $str);
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file();
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? 'auto_inst.cfg' : "patch";
	my $o;
	foreach (removable_media__early_in_install()) {
            my $dev = devices::make($_->{device});
            foreach my $fs (arch() =~ /sparc/ ? 'romfs' : ('ext2', 'vfat')) {
                eval { fs::mount::mount($dev, '/mnt', $fs, 'readonly'); 1 } or next;
		if (my $abs_f = find { -e $_ } "/mnt/$f", "/mnt/$f.pl") {
		    $o = loadO_($O, $abs_f);
		}
		fs::mount::umount("/mnt");
		goto found if $o;
            }
	}
	die "Could not find $f";
      found:
	modules::unload(qw(vfat fat));
	$o;
    } else {
	loadO_($O, $f);
    }
}

sub loadO_ {
    my ($O, $f) = @_; 

    my $o;
    {
	my $fh;
	if (ref $f) {
	    $fh = $f;
	} else {
	    -e "$f.pl" and $f .= ".pl" unless -e $f;

	    $fh = -e $f ? common::open_file($f) : getFile_($O->{stage2_phys_medium}, $f) || die N("Error reading file %s", $f);
	}
	my $s = cat__($fh);
	close $fh;
	{
	    no strict;
	    eval $s;
	    $@ and die;
	}
	$O and add2hash_($o ||= {}, $O);
    }
    $O and bless $o, ref $O;

    handle_old_auto_install_format($o);

    $o;
}

sub handle_old_auto_install_format {
    my ($o) = @_;

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
    if ($o->{updates} && $o->{updates}{mirror}) {
	$o->{updates}{url} = delete $o->{updates}{mirror};
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
	my @l = install::ftp::parse_ftp_url($ENV{URLPREFIX});
	@ks = (server => $l[0], directory => $l[1], user => $l[2], pass => $l[3]);
    } elsif ($o->{method} eq 'nfs') {
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/media| or internal_error("can not find nfsimage");
	@ks = (server => $1, directory => $2);
    }
    @ks = (method => $method, @ks);

    if (is_network_install($o)) {
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

sub find_root_parts {
    my ($fstab, $prefix) = @_;

    if ($::local_install) {
	my $f = common::release_file('/mnt') or return;
	return common::parse_release_file('/mnt', $f, {});
    }

    map { 
	my $handle = any::inspect($_, $prefix);
	if (my $f = $handle && common::release_file($handle->{dir})) {
	    common::parse_release_file($handle->{dir}, $f, $_);
	} else { () }
    } grep { isTrueLocalFS($_) } @$fstab;
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
    return if $::local_install;

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
    fs::any::get_hds($o->{all_hds} ||= {}, $o->{fstab} ||= [], 
		     $o->{manualFstab}, $o->{partitioning}, $::local_install, $o_in);
}

sub removable_media__early_in_install() {
    eval { modules::load('usb_storage', 'sd_mod') } if detect_devices::usbStorage();
    my $all_hds = fsedit::get_hds({});
    fs::get_raw_hds('', $all_hds);

    my @l1 = grep { detect_devices::isKeyUsb($_) } @{$all_hds->{hds}};
    my @l2 = grep { $_->{media_type} eq 'fd' || detect_devices::isKeyUsb($_) } @{$all_hds->{raw_hds}};
    (fs::get::hds_fstab(@l1), @l2);
}

my %media_browser;
sub media_browser {
    my ($in, $save, $o_suggested_name) = @_;

    my %media_type2text = (
	fd => N("Floppy"),
	hd => N("Hard Disk"),
	cdrom => N("CDROM"),
    );
    my @network_protocols = (if_(!$save, N_("HTTP")), if_(0, N_("FTP")), N_("NFS"));

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
	if_(is_network_install($::o) || install::steps::hasNetwork($::o),
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
	    common::open_file($file) || goto browse;
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
	require install::interactive;
	install::interactive::upNetwork($::o);

	if ($dev eq 'HTTP') {
	    require install::http;
	    $media_browser{url} ||= 'http://';

	    while (1) {
		$in->ask_from('', 'URL', [
		    { val => \$media_browser{url} }
		]) or last;
		    
		if ($dev eq 'HTTP') {
		    my $fh = install::http::getFile($media_browser{url});
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

sub X_options_from_o {
    my ($o) = @_;
    { 
	freedriver => $o->{freedriver},
	allowFB => $o->{allowFB},
	ignore_bad_conf => $o->{isUpgrade} =~ /redhat|conectiva/,
    };
}

sub screenshot_dir__and_move() {
    my ($dir0, $dir1, $dir2) = ('/root', "$::prefix/root", '/tmp');
    if (-e $dir0 && ! -e '/root/non-chrooted-marker.DrakX') {
	($dir0, 'nowarn'); #- it occurs during pkgs install when we are chrooted
    } elsif (-e $dir1) {
	if (-e "$dir2/DrakX-screenshots") {
	    cp_af("$dir2/DrakX-screenshots", $dir1);
	    rm_rf("$dir2/DrakX-screenshots");
	}
	$dir1;
    } else {
	$dir2;
    }
}

my $warned;
sub take_screenshot {
    my ($in) = @_;
    my ($base_dir, $nowarn) = screenshot_dir__and_move();
    my $dir = "$base_dir/DrakX-screenshots";
    if (!-e $dir) {
	mkdir $dir or $in->ask_warn('', N("Can not make screenshots before partitioning")), return;
    }
    my $nb = 1;
    $nb++ while -e "$dir/$nb.png";
    system("fb2png /dev/fb0 $dir/$nb.png 0");

    if (!$warned && !$nowarn) {
	$warned = 1;
	$in->ask_warn('', N("Screenshots will be available after install in %s", "/root/DrakX-screenshots"));
    }
}

sub copy_advertising {
    my ($o) = @_;

    return if $::rootwidth < 800;

    my $f;
    my $source_dir = "install/extra/advertising";
    foreach ("." . $o->{locale}{lang}, "." . substr($o->{locale}{lang},0,2), '') {
	$f = getFile_($o->{stage2_phys_medium}, "$source_dir$_/list") or next;
	$source_dir = "$source_dir$_";
    }
    if (my @files = <$f>) {
	my $dir = "$::prefix/tmp/drakx-images";
	mkdir $dir;
	unlink glob_("$dir/*");
	foreach (@files) {
	    chomp;
	    install::media::getAndSaveFile_($o->{stage2_phys_medium}, "$source_dir/$_", "$dir/$_");
	    (my $pl = $_) =~ s/\.png/.pl/;
	    install::media::getAndSaveFile_($o->{stage2_phys_medium}, "$source_dir/$pl", "$dir/$pl");
	}
	@advertising_images = map { "$dir/$_" } @files;
    }
}

sub remove_advertising() {
    eval { rm_rf("$::prefix/tmp/drakx-images") };
    @advertising_images = ();
}

sub disable_user_view() {
    substInFile { s/^UserView=.*/UserView=true/ } "$::prefix/etc/kde/kdm/kdmrc";
    substInFile { s/^Browser=.*/Browser=0/ } "$::prefix/etc/X11/gdm/custom.conf";
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
    fs::write_fstab($o->{all_hds}, $::prefix) 
	if !$o->{isUpgrade} || $o->{isUpgrade} =~ /redhat|conectiva/ || $o->{migrate_device_names};
}

sub adjust_files_mtime_to_timezone() {
    #- to ensure linuxconf does not cry against those files being in the future
    #- to ensure fc-cache works correctly on fonts installed after reboot

    my $timezone_shift = run_program::rooted_get_stdout($::prefix, 'date', '+%z');
    my ($h, $m) = $timezone_shift =~ /\+(..)(..)/ or return;
    my $now = time() - ($h * 60 + $m * 60) * 60;

    my @files = (
	(map { "$::prefix/$_" } '/etc/modules.conf', '/etc/crontab', '/etc/sysconfig/mouse', '/etc/sysconfig/network', '/etc/X11/fs/config'),
	glob_("$::prefix/var/cache/fontconfig/*"),
    );
    log::l("adjust_files_mtime_to_timezone: setting time back $h:$m for files " . join(' ', @files));
    foreach (@files) {
	utime $now, $now, $_;
    }
}


sub move_compressed_image_to_disk {
    my ($o) = @_;

    our $compressed_image_on_disk;
    return if $compressed_image_on_disk || $::local_install;

    my $name = 'mdkinst.sqfs';
    my ($loop, $current_image) = devices::find_compressed_image($name) or return;
    my $compressed_image_size = (-s $current_image) / 1024; #- put in KiB

    my $dir;
    if (availableRamMB() > 400) {
	$dir = '/tmp'; #- on tmpfs
    } else {
	my $tmp = fs::get::mntpoint2part('/tmp', $o->{fstab});
	if ($tmp && fs::df($tmp, $::prefix) / 2 > $compressed_image_size * 1.2) { #- we want at least 20% free afterwards
	    $dir = "$::prefix/tmp";
	} else {
	    my $root = fs::get::mntpoint2part('/', $o->{fstab});
	    my $root_free_MB = fs::df($root, $::prefix) / 2 / 1024;
	    my $wanted_size_MB = $o->{isUpgrade} || fs::get::mntpoint2part('/usr', $o->{fstab}) ? 150 : 300;
	    log::l("compressed image: root free $root_free_MB MB, wanted at least $wanted_size_MB MB");
	    if ($root_free_MB > $wanted_size_MB) {
		$dir = $tmp ? $::prefix : "$::prefix/tmp";
	    } else {
		$dir = '/tmp'; #- on tmpfs
		if (availableRamMB() < 200) {
		    log::l("ERROR: not much ram (" . availableRamMB() . " MB), we're going in the wall!");
		}
	    }
	}
    }
    $compressed_image_on_disk = "$dir/$name";

    if ($current_image ne $compressed_image_on_disk) {
	log::l("move_compressed_image_to_disk: copying $current_image to $compressed_image_on_disk");
	cp_af($current_image, $compressed_image_on_disk);
	run_program::run('losetup', '-r', $loop, $compressed_image_on_disk);
	unlink $current_image if $current_image eq "/tmp/$name";
    }
}

sub deploy_server_notify {
    my ($o) = @_;
    my $fallback_intf = "eth0";
    my $fallback_port = 3710;

    my ($server, $port) = $o->{deploy_server} =~ /^(.*?)(?::(\d+))?$/;
    if ($server) {
        require network::tools;
        require IO::Socket;
        $port ||= $fallback_port;
        my $intf = network::tools::get_current_gateway_interface() || $fallback_intf;
        my $mac = c::get_hw_address($intf);
        my $sock = IO::Socket::INET->new(PeerAddr => $server, PeerPort => $port, Proto => 'tcp');
        if ($sock) {
            print $sock "$mac\n";
            close($sock);
            log::l(qq(successfully notified deploy server $server on port $port));
        } else {
            log::l(qq(unable to contact deploy server $server on port $port));
        }
    } else {
        log::l(qq(unable to parse deploy server in string $o->{deploy_server}));
    }
}

#-###############################################################################
#- pcmcia various
#-###############################################################################
sub configure_pcmcia {
    my ($o) = @_;
    my $controller = detect_devices::pcmcia_controller_probe();
    $o->{pcmcia} ||= $controller && $controller->{driver} or return;
    log::l("configuring PCMCIA controller ($o->{pcmcia})");
    symlink "/tmp/stage2/$_", $_ foreach "/etc/pcmcia";
    eval { modules::load($o->{pcmcia}, 'pcmcia') };
    run_program::run("pcmcia-socket-startup");
}

1;
