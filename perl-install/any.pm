package any; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use detect_devices;
use partition_table qw(:types);
use fsedit;
use fs;
use lang;
use run_program;
use modules;
use log;
use c;

sub drakx_version { 
    sprintf "DrakX v%s built %s", $::testing ? ('TEST', scalar gmtime()) : (split('/', cat_("$ENV{SHARE_PATH}/VERSION")))[2,3];
}

sub facesdir {
    my ($prefix) = @_;
    "$prefix/usr/share/mdk/faces/";
}
sub face2png {
    my ($face, $prefix) = @_;
    facesdir($prefix) . $face . ".png";
}
sub facesnames {
    my ($prefix) = @_;
    my $dir = facesdir($prefix);
    my @l = grep { /^[A-Z]/ } all($dir);
    map { if_(/(.*)\.png/, $1) } (@l ? @l : all($dir));
}

sub addKdmIcon {
    my ($prefix, $user, $icon) = @_;
    my $dest = "$prefix/usr/share/faces/$user.png";
    eval { cp_af(facesdir($prefix) . $icon . ".png", $dest) } if $icon;
}

sub allocUsers {
    my ($prefix, $users) = @_;
    my @m = my @l = facesnames($prefix);
    foreach (grep { !$_->{icon} || $_->{icon} eq "automagic" } @$users) {
	$_->{auto_icon} = splice(@m, rand(@m), 1); #- known biased (see cookbook for better)
	log::l("auto_icon is $_->{auto_icon}");
	@m = @l unless @m;
    }
}

sub addUsers {
    my ($prefix, $users) = @_;
    my $msec = "$prefix/etc/security/msec";

    allocUsers($prefix, $users);
    foreach my $u (@$users) {
	run_program::rooted($prefix, "usermod", "-G", join(",", @{$u->{groups}}), $u->{name}) if !is_empty_array_ref($u->{groups});
	addKdmIcon($prefix, $u->{name}, delete $u->{auto_icon} || $u->{icon});
    }
}

sub crypt {
    my ($password, $md5) = @_;
    crypt($password, $md5 ? '$1$' . salt(8) : salt(2));
}
sub enableShadow {
    my ($prefix) = @_;
    run_program::rooted($prefix, "pwconv")  or log::l("pwconv failed");
    run_program::rooted($prefix, "grpconv") or log::l("grpconv failed");
}
sub enableMD5Shadow { #- NO MORE USED
    my ($prefix, $shadow, $md5) = @_;
    substInFile {
	if (/^password.*pam_pwdb.so/) {
	    s/\s*shadow//; s/\s*md5//;
	    s/$/ shadow/ if $shadow;
	    s/$/ md5/ if $md5;
	}
    } grep { -r $_ } map { "$prefix/etc/pam.d/$_" } qw(login rlogin passwd);
}

sub grub_installed {
    my ($in) = @_;
    my $f = "/usr/sbin/grub";
    $in->do_pkgs->install('grub') if !-e $f;
    -e $f;
}

sub setupBootloader {
    my ($in, $b, $all_hds, $fstab, $security, $prefix, $more) = @_;
    my $hds = $all_hds->{hds};

    $more++ if $b->{bootUnsafe};
    my $automatic = !$::expert && $more < 1;
    my $semi_auto = !$::expert && arch() !~ /ia64/;
    my $ask_per_entries = $::expert || $more > 1;
    my $prev_boot = $b->{boot};
    my $mixed_kind_of_disks = 
      (grep { $_->{device} =~ /^sd/ } @$hds) && (grep { $_->{device} =~ /^hd/ } @$hds) ||
      (grep { $_->{device} =~ /^hd[fghi]/ } @$hds) && (grep { $_->{device} =~ /^hd[abcd]/ } @$hds);

    if ($mixed_kind_of_disks) {
	$automatic = $semi_auto = 0;
	#- full expert questions when there is 2 kind of disks
	#- it would need a semi_auto asking on which drive the bios boots...
    }
    $automatic = 0 if arch() =~ /ppc/; #- no auto for PPC yet
	
    if ($automatic) {
	#- automatic
    } elsif ($semi_auto) {
	my @l = (__("First sector of drive (MBR)"), __("First sector of boot partition"));

	$in->set_help('setupBootloaderBeginner') unless $::isStandalone;
	if (arch() =~ /sparc/) {
	    $b->{use_partition} = $in->ask_from_list_(_("SILO Installation"),
						      _("Where do you want to install the bootloader?"),
						      \@l, $l[$b->{use_partition}]) or return 0;
	} elsif (arch() =~ /ppc/) {
		if (defined $partition_table_mac::bootstrap_part) {
			$b->{boot} = $partition_table_mac::bootstrap_part;
			log::l("set bootstrap to $b->{boot}"); 
		} else {
			die "no bootstrap partition - yaboot.conf creation failed";
		}
	} else {
	    my $boot = $hds->[0]{device};
	    my $onmbr = "/dev/$boot" eq $b->{boot};
	    $b->{boot} = "/dev/" . ($in->ask_from_list_(_("LILO/grub Installation"),
							_("Where do you want to install the bootloader?"),
							\@l, $l[!$onmbr]) eq $l[0] 
				    ? $boot : fsedit::get_root($fstab, 'boot')->{device});
	}
    } else {
	$in->set_help(arch() =~ /sparc/ ? "setupSILOGeneral" :  arch() =~ /ppc/ ? 'setupYabootGeneral' :"setupBootloader") unless $::isStandalone; #- TO MERGE ?

	my @silo_install_lang = (_("First sector of drive (MBR)"), _("First sector of boot partition"));
	my $silo_install_lang = $silo_install_lang[$b->{use_partition}];

	my %bootloaders = (if_(exists $b->{methods}{silo},
			       __("SILO")                     => sub { $b->{methods}{silo} = 1 }),
			   if_(exists $b->{methods}{lilo},
			       __("LILO with text menu")      => sub { $b->{methods}{lilo} = "lilo-menu" },
			       __("LILO with graphical menu") => sub { $b->{methods}{lilo} = "lilo-graphic" }),
			   if_(exists $b->{methods}{grub},
			       #- put lilo if grub is chosen, so that /etc/lilo.conf is generated
			       __("Grub")                     => sub { $b->{methods}{grub} = 1;
								       exists $b->{methods}{lilo}
									 and $b->{methods}{lilo} = "lilo-menu" }),
			   if_(exists $b->{methods}{loadlin},
			       __("Boot from DOS/Windows (loadlin)") => sub { $b->{methods}{loadlin} = 1 }),
			   if_(exists $b->{methods}{yaboot},
			       __("Yaboot") => sub { $b->{methods}{yaboot} = 1 }),
			  );
	my $bootloader = arch() =~ /sparc/ ? __("SILO") : arch() =~ /ppc/ ? __("Yaboot") : __("LILO with graphical menu");
	my $profiles = bootloader::has_profiles($b);
	my $memsize = bootloader::get_append($b, 'mem');
	my $prev_clean_tmp = my $clean_tmp = grep { $_->{mntpoint} eq '/tmp' } @{$all_hds->{special} ||= []};

	$b->{vga} ||= 'normal';
	if (arch() !~ /ppc/) {
	$in->ask_from('', _("Bootloader main options"), [
{ label => _("Bootloader to use"), val => \$bootloader, list => [ keys(%bootloaders) ], format => \&translate },
    arch() =~ /sparc/ ? (
{ label => _("Bootloader installation"), val => \$silo_install_lang, list => \@silo_install_lang },
) : if_(arch() !~ /ia64/,
{ label => _("Boot device"), val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } (@$hds, grep { !isFat($_) } @$fstab)), detect_devices::floppies_dev() ], not_edit => !$::expert },
{ label => _("LBA (doesn't work on old BIOSes)"), val => \$b->{lba32}, type => "bool", text => "lba", advanced => 1 },
{ label => _("Compact"), val => \$b->{compact}, type => "bool", text => _("compact"), advanced => 1 },
{ label => _("Video mode"), val => \$b->{vga}, list => [ keys %bootloader::vga_modes ], not_edit => !$::expert, format => sub { $bootloader::vga_modes{$_[0]} }, advanced => 1 },
),
{ label => _("Delay before booting default image"), val => \$b->{timeout} },
    if_($security >= 4,
{ label => _("Password"), val => \$b->{password}, hidden => 1 },
{ label => _("Password (again)"), val => \$b->{password2}, hidden => 1 },
{ label => _("Restrict command line options"), val => \$b->{restricted}, type => "bool", text => _("restrict") },
    ),
{ label => _("Clean /tmp at each boot"), val => \$clean_tmp, type => 'bool', advanced => 1 },
{ label => _("Precise RAM size if needed (found %d MB)", availableRamMB()), val => \$memsize, advanced => 1 },
    if_(detect_devices::isLaptop,
{ label => _("Enable multi profiles"), val => \$profiles, type => 'bool', advanced => 1 },
    ),
],
				 complete => sub {
				     !$memsize || $memsize =~ /K$/ || $memsize =~ s/^(\d+)M?$/$1M/i or $in->ask_warn('', _("Give the ram size in MB")), return 1;
#-				     $security > 4 && length($b->{password}) < 6 and $in->ask_warn('', _("At this level of security, a password (and a good one) in lilo is requested")), return 1;
				     $b->{restricted} && !$b->{password} and $in->ask_warn('', _("Option ``Restrict command line options'' is of no use without a password")), return 1;
				     $b->{password} eq $b->{password2} or !$b->{restricted} or $in->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return 1;
				     0;
				 }
				) or return 0;
	} else {
	$b->{boot} = $partition_table_mac::bootstrap_part;	
	$in->ask_from('', _("Bootloader main options"), [
	{ label => _("Bootloader to use"), val => \$bootloader, list => [ keys(%bootloaders) ], format => \&translate },	
	{ label => _("Init Message"), val => \$b->{'init-message'} },
	{ label => _("Boot device"), val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } (grep { isAppleBootstrap($_) } @$fstab))], not_edit => !$::expert },
	{ label => _("Open Firmware Delay"), val => \$b->{delay} },
	{ label => _("Kernel Boot Timeout"), val => \$b->{timeout} },
	{ label => _("Enable CD Boot?"), val => \$b->{enablecdboot}, type => "bool" },
	{ label => _("Enable OF Boot?"), val => \$b->{enableofboot}, type => "bool" },
	{ label => _("Default OS?"), val=> \$b->{defaultos}, list => [ 'linux', 'macos', 'macosx', 'darwin' ] },
	]) or return 0;				
	}
	
	$b->{methods}{$_} = 0 foreach keys %{$b->{methods}};
	$bootloaders{$bootloader} and $bootloaders{$bootloader}->();

	grub_installed($in) or return 1 if $b->{methods}{grub};

	#- at least one method
	grep_each { $::b } %{$b->{methods}} or return 0;

	$b->{use_partition} = $silo_install_lang eq _("First sector of drive (MBR)") ? 0 : 1;

	bootloader::set_profiles($b, $profiles);
	bootloader::add_append($b, "mem", $memsize);

	if ($prev_clean_tmp != $clean_tmp) {
	    if ($clean_tmp) {
		push @{$all_hds->{special}}, { device => 'none', mntpoint => '/tmp', type => 'tmpfs' };
	    } else {
		@{$all_hds->{special}} = grep { $_->{mntpoint} eq '/tmp' } @{$all_hds->{special}};
	    }
	}
    }

    #- remove bios mapping if the user changed the boot device
    delete $b->{bios} if $b->{boot} ne $prev_boot;

    if ($mixed_kind_of_disks && 
#	$b->{boot} !~ /$hds->[0]{device}/ && #- not the first disk
	$b->{boot} =~ /\d$/ && #- on a partition
	is_empty_hash_ref($b->{bios}) && #- some bios mapping already there
	arch() !~ /ppc/) {
	my $hd = $in->ask_from_listf('', _("You decided to install the bootloader on a partition.
This implies you already have a bootloader on the hard drive you boot (eg: System Commander).

On which drive are you booting?"), \&partition_table::description, $hds) or goto &setupBootloader;
	$b->{first_hd_device} = "/dev/$hd->{device}";
    }

    $ask_per_entries or return 1;

    while (1) {
	$in->set_help(arch() =~ /sparc/ ? 'setupSILOAddEntry' : arch() =~ /ppc/ ? 'setupYabootAddEntry' : 'setupBootloaderAddEntry') unless $::isStandalone;
	my ($c, $e);
	$in->ask_from_(
		{
		 messages => 
_("Here are the entries on your boot menu so far.
You can add some more or change the existing ones."),
		 ok => '',
},
		[ { val => \$e, type => 'combo', format => sub {
		    my ($e) = @_;
		    ref $e ? 
		      "$e->{label} ($e->{kernel_or_dev})" . ($b->{default} eq $e->{label} && "  *") : 
		      translate($e);
		}, list => [ @{$b->{entries}} ], allow_empty_list => 1 },
		  (map { my $s = $_; { val => translate($_), clicked_may_quit => sub { $c = $s; 1 } } } (if_(@{$b->{entries}} > 0, __("Modify")), __("Add"), __("Done"))),
		]
	);
	!$c || $c eq "Done" and last;

	if ($c eq "Add") {
	    my @labels = map { $_->{label} } @{$b->{entries}};
	    my $prefix;
	    if ($in->ask_from_list_('', _("Which type of entry do you want to add?"),
				    [ __("Linux"), arch() =~ /sparc/ ? __("Other OS (SunOS...)") : arch() =~ /ppc/ ? 
				   __("Other OS (MacOS...)") : __("Other OS (windows...)") ]
				   ) eq "Linux") {
		$e = { type => 'image',
		       root => '/dev/' . fsedit::get_root($fstab)->{device}, #- assume a good default.
		     };
		$prefix = "linux";
	    } else {
		$e = { type => 'other' };
		$prefix = arch() =~ /sparc/ ? "sunos" : arch() =~ /ppc/ ? "macos" : "windows";;
	    }
	    $e->{label} = $prefix;
	    for (my $nb = 0; member($e->{label}, @labels); $nb++) { $e->{label} = "$prefix-$nb" }
	}
	my %old_e = %$e;
	my $default = my $old_default = $e->{label} eq $b->{default};

	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
{ label => _("Image"), val => \$e->{kernel_or_dev}, list => [ map { s/$prefix//; $_ } glob_("$prefix/boot/vmlinuz*") ], not_edit => 0 },
{ label => _("Root"), val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
{ label => _("Append"), val => \$e->{append} },
  if_(arch !~ /ppc|ia64/,
{ label => _("Video mode"), val => \$e->{vga}, list => [ keys %bootloader::vga_modes ], format => sub { $bootloader::vga_modes{$_[0]} }, not_edit => !$::expert },
),
{ label => _("Initrd"), val => \$e->{initrd}, list => [ map { s/$prefix//; $_ } glob_("$prefix/boot/initrd*") ], not_edit => 0 },
{ label => _("Read-write"), val => \$e->{'read-write'}, type => 'bool' }
	    );
	    @l = @l[0..2] unless $::expert;
	} else {
	    @l = ( 
{ label => _("Root"), val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
if_(arch() !~ /sparc|ppc|ia64/,
{ label => _("Table"), val => \$e->{table}, list => [ '', map { "/dev/$_->{device}" } @$hds ], not_edit => !$::expert },
{ label => _("Unsafe"), val => \$e->{unsafe}, type => 'bool' }
),
	    );
	    @l = $l[0] unless $::expert;
	}
if (arch() !~ /ppc/) {
	@l = (
{ label => _("Label"), val => \$e->{label} },
@l,
{ label => _("Default"), val => \$default, type => 'bool' },
	);
} else {
	@l = ({ label => _("Label"), val => \$e->{label}, list=> ['macos', 'macosx', 'darwin'] },
	@l );
	if ($e->{type} eq "image") {
		@l = ({ label => _("Label"), val => \$e->{label} },
		$::expert ? @l[1..4] : (@l[1..2], { label => _("Append"), val => \$e->{append} }) ,
		if_($::expert, { label => _("Initrd-size"), val => \$e->{initrdsize}, list => [ '', '4096', '8192', '16384', '24576' ] }),
		if_($::expert, $l[5]),
		{ label => _("NoVideo"), val => \$e->{novideo}, type => 'bool' },
		{ label => _("Default"), val => \$default, type => 'bool' }
		);
	}
}

	if ($in->ask_from_(
	    { 
	     if_($c ne "Add", cancel => _("Remove entry")),
	     callbacks => {
	       complete => sub {
		   $e->{label} or $in->ask_warn('', _("Empty label not allowed")), return 1;
		   $e->{kernel_or_dev} or $in->ask_warn('', $e->{type} eq 'image' ? _("You must specify a kernel image") : _("You must specify a root partition")), return 1;
		   member(lc $e->{label}, map { lc $_->{label} } grep { $_ != $e } @{$b->{entries}}) and $in->ask_warn('', _("This label is already used")), return 1;
		   0;
	       } } }, \@l)) {
	    $b->{default} = $old_default || $default ? $default && $e->{label} : $b->{default};
	    require bootloader;
	    bootloader::configure_entry($prefix, $e); #- hack to make sure initrd file are built.

	    push @{$b->{entries}}, $e if $c eq "Add";
	} else {
	    delete $b->{default} if $b->{default} eq $e->{label};
	    @{$b->{entries}} = grep { $_ != $e } @{$b->{entries}};
	}
    }
    1;
}

my @etc_pass_fields = qw(name pw uid gid realname home shell);
sub unpack_passwd {
    my ($l) = @_;
    my %l; @l{@etc_pass_fields} = split ':', chomp_($l);
    \%l;
}
sub pack_passwd {
    my ($l) = @_;
    join(':', @$l{@etc_pass_fields}) . "\n";
}

sub get_autologin {
    my ($prefix, $o) = @_;
    my %l = getVarsFromSh("$prefix/etc/sysconfig/autologin");
    $o->{autologin} ||= $l{USER};
    %l = getVarsFromSh("$prefix/etc/sysconfig/desktop");
    $o->{desktop} ||= $l{DESKTOP};
}

sub set_autologin {
  my ($prefix, $user, $desktop) = @_;

  if ($user) {
      my %l = getVarsFromSh("$prefix/etc/sysconfig/desktop");
      $l{DESKTOP} = $desktop;
      setVarsInSh("$prefix/etc/sysconfig/desktop", \%l);
      log::l("cat $prefix/etc/sysconfig/desktop ($desktop):\n", cat_("$prefix/etc/sysconfig/desktop"));
  }
  setVarsInSh("$prefix/etc/sysconfig/autologin",
	      { USER => $user, AUTOLOGIN => bool2yesno($user), EXEC => "/usr/X11R6/bin/startx" });
  log::l("cat $prefix/etc/sysconfig/autologin ($user):\n", cat_("$prefix/etc/sysconfig/autologin"));
}

sub rotate_log {
    my ($f) = @_;
    if (-e $f) {
	my $i = 1;
	for (; -e "$f$i" || -e "$f$i.gz"; $i++) {}
	rename $f, "$f$i";
    }
}
sub rotate_logs {
    my ($prefix) = @_;
    rotate_log("$prefix/root/drakx/$_") foreach qw(ddebug.log install.log);
}

sub writeandclean_ldsoconf {
    my ($prefix) = @_;
    my $file = "$prefix/etc/ld.so.conf";
    output $file,
      grep { !m|^(/usr)?/lib$| } #- no need to have /lib and /usr/lib in ld.so.conf
	uniq cat_($file), "/usr/X11R6/lib\n";
}

sub shells {
    my ($prefix) = @_;
    grep { -x "$prefix$_" } chomp_(cat_("$prefix/etc/shells"));
}

sub inspect {
    my ($part, $prefix, $rw) = @_;

    isMountableRW($part) or return;

    my $dir = $::isInstall ? "/tmp/inspect_tmp_dir" : "/root/.inspect_tmp_dir";

    if ($part->{isMounted}) {
	$dir = ($prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	$dir = '';
    } else {
	mkdir $dir, 0700;
	eval { fs::mount($part->{device}, $dir, type2fs($part), !$rw) };
	$@ and return;
    }
    my $h = before_leaving {
	if (!$part->{isMounted} && $dir) {
	    fs::umount($dir);
	    unlink($dir)
	}
    };
    $h->{dir} = $dir;
    $h;
}

#-----modem conf
sub pppConfig {
    my ($in, $modem, $prefix) = @_;
    $modem or return;

    if ($modem->{device} ne "/dev/modem") {
	devfssymlinkf($modem->{device}, 'modem', $prefix) or log::l("creation of $prefix/dev/modem failed")
    }
    $in->do_pkgs->install('ppp') if !$::testing;

    my %toreplace;
    $toreplace{$_} = $modem->{$_} foreach qw(connection phone login passwd auth domain dns1 dns2);
    $toreplace{kpppauth} = ${{ 'Script-based' => 0, 'PAP' => 1, 'Terminal-based' => 2, }}{$modem->{auth}};
    $toreplace{kpppauth} = ${{ 'Script-based' => 0, 'PAP' => 1, 'Terminal-based' => 2, 'CHAP' => 3 }}{$modem->{auth}};
    $toreplace{phone} =~ s/\D//g;
    $toreplace{dnsserver} = join ',', map { $modem->{$_} } "dns1", "dns2";
    $toreplace{dnsserver} .= $toreplace{dnsserver} && ',';

    #- using peerdns or dns1,dns2 avoid writing a /etc/resolv.conf file.
    $toreplace{peerdns} = "yes";

    $toreplace{connection} ||= 'DialupConnection';
    $toreplace{domain} ||= 'localdomain';
    $toreplace{intf} ||= 'ppp0';
    $toreplace{papname} = ($modem->{auth} eq 'PAP' || $modem->{auth} eq 'CHAP') && $toreplace{login};

    #- build ifcfg-ppp0.
    my $ifcfg = "$prefix/etc/sysconfig/network-scripts/ifcfg-ppp0";
    local *IFCFG; open IFCFG, ">$ifcfg" or die "Can't open $ifcfg";
    print IFCFG <<END;
DEVICE="$toreplace{intf}"
ONBOOT="no"
USERCTL="no"
MODEMPORT="/dev/modem"
LINESPEED="115200"
PERSIST="yes"
DEFABORT="yes"
DEBUG="yes"
INITSTRING="ATZ"
DEFROUTE="yes"
HARDFLOWCTL="yes"
ESCAPECHARS="no"
PPPOPTIONS=""
PAPNAME="$toreplace{papname}"
REMIP=""
NETMASK=""
IPADDR=""
MRU=""
MTU=""
DISCONNECTTIMEOUT="5"
RETRYTIMEOUT="60"
BOOTPROTO="none"
PEERDNS="$toreplace{peerdns}"
END
    foreach (1..2) {
	if ($toreplace{"dns$_"}) {
	    print IFCFG <<END;
DNS$_=$toreplace{"dns$_"}
END
	}
    }
    close IFCFG;

    #- build chat-ppp0.
    my $chat = "$prefix/etc/sysconfig/network-scripts/chat-ppp0";
    local *CHAT; open CHAT, ">$chat" or die "Can't open $chat";
    print CHAT <<END;
'ABORT' 'BUSY'
'ABORT' 'ERROR'
'ABORT' 'NO CARRIER'
'ABORT' 'NO DIALTONE'
'ABORT' 'Invalid Login'
'ABORT' 'Login incorrect'
'' 'ATZ'
END
    if ($modem->{special_command}) {
	print CHAT <<END;
'OK' '$modem->{special_command}'
END
    }
    print CHAT <<END;
'OK' 'ATDT$toreplace{phone}'
'CONNECT' ''
END
    if ($modem->{auth} eq 'Terminal-based' || $modem->{auth} eq 'Script-based') {
	print CHAT <<END;
'ogin:--ogin:' '$toreplace{login}'
'ord:' '$toreplace{passwd}'
END
    }
    print CHAT <<END;
'TIMEOUT' '5'
'~--' ''
END
    close CHAT;
    chmod 0600, $chat;

    if ($modem->{auth} eq 'PAP' || $modem->{auth} eq 'CHAP') {
	#- need to create a secrets file for the connection.
	my $secrets = "$prefix/etc/ppp/" . lc($modem->{auth}) . "-secrets";
	my @l = cat_($secrets);
	my $replaced = 0;
	do { $replaced ||= 1
	       if s/^\s*"?$toreplace{login}"?\s+ppp0\s+(\S+)/"$toreplace{login}"  ppp0  "$toreplace{passwd}"/; } foreach @l;
	if ($replaced) {
	    local *F;
	    open F, ">$secrets" or die "Can't open $secrets: $!";
	    print F @l;
        } else {
	    local *F;
	    open F, ">>$secrets" or die "Can't open $secrets: $!";
	    print F "$toreplace{login}  ppp0  \"$toreplace{passwd}\"\n";
	}
	#- restore access right to secrets file, just in case.
	chmod 0600, $secrets;
    }

    #- install kppprc file according to used configuration.
    mkdir_p("$prefix/usr/share/config");

    {
	local *KPPPRC;
	open KPPPRC, ">$prefix/usr/share/config/kppprc" or die "Can't open $prefix/usr/share/config/kppprc: $!";
	#chmod 0600, "$prefix/usr/share/config/kppprc";
	print KPPPRC c::to_utf8(<<END);
# KDE Config File
[Account0]
ExDNSDisabled=0
AutoName=0
ScriptArguments=
AccountingEnabled=0
DialString=ATDT
Phonenumber=$toreplace{phone}
IPAddr=0.0.0.0
Domain=$toreplace{domain}
Name=$toreplace{connection}
VolumeAccountingEnabled=0
pppdArguments=
Password=$toreplace{passwd}
BeforeDisconnect=
Command=
ScriptCommands=
Authentication=$toreplace{kpppauth}
DNS=$toreplace{dnsserver}
SubnetMask=0.0.0.0
AccountingFile=
DefaultRoute=1
Username=$toreplace{login}
Gateway=0.0.0.0
StorePassword=1
DisconnectCommand=
[Modem]
BusyWait=0
Enter=CR
FlowControl=CRTSCTS
Volume=0
Timeout=60
UseCDLine=0
UseLockFile=1
Device=/dev/modem
Speed=115200
[Graph]
InBytes=0,0,255
Text=0,0,0
Background=255,255,255
Enabled=true
OutBytes=255,0,0
[General]
QuitOnDisconnect=0
ShowLogWindow=0
DisconnectOnXServerExit=1
DefaultAccount=$toreplace{connection}
iconifyOnConnect=1
Hint_QuickHelp=0
AutomaticRedial=0
PPPDebug=0
NumberOfAccounts=1
ShowClock=1
DockIntoPanel=0
pppdTimeout=30
END
    }
    miscellaneousNetwork($prefix);
}

sub miscellaneousNetwork {
    my ($prefix) = @_;
    setVarsInSh ("$prefix/etc/profile.d/proxy.sh",  $::o->{miscellaneous}, qw(http_proxy ftp_proxy));
    setVarsInCsh("$prefix/etc/profile.d/proxy.csh", $::o->{miscellaneous}, qw(http_proxy ftp_proxy));
}

sub load_category_no_message {
    my ($category, $at_least_one) = @_;
    my @l;
    @l = modules::load_category($category, undef);
    @l = modules::load_category($category, undef, 'force') if !@l && $at_least_one;
    @l;
}

sub load_category {
    my ($in, $category, $auto, $at_least_one) = @_;

    my @l;
    if (!$::noauto) {
	my $w;
	my $wait_message = sub { $w = wait_load_module($in, $category, @_) };
	@l = modules::load_category($category, $wait_message);
	@l = modules::load_category($category, $wait_message, 'force') if !@l && $at_least_one;
    }
    if (my @err = grep { $_ } map { $_->{error} } @l) {
	$in->ask_warn('', join("\n", @err));
    }
    return @l if $auto && (@l || !$at_least_one);

    @l = map { $_->{description} } @l;

    if ($at_least_one && !@l) {
	@l = load_category__prompt($in, $category) or return;
    }

    load_category__prompt_for_more($in, $category, @l);
}

sub load_category__prompt_for_more {
    my ($in, $category, @l) = @_;

    (my $msg_type = $category) =~ s/\|.*//;

    while (1) {
	my $msg = @l ?
	  [ _("Found %s %s interfaces", join(", ", @l), $msg_type),
	    _("Do you have another one?") ] :
	  _("Do you have any %s interfaces?", $msg_type);

	my $opt = [ __("Yes"), __("No") ];
	push @$opt, __("See hardware info") if $::expert;
	my $r = $in->ask_from_list_('', $msg, $opt, "No") or die 'already displayed';
	if ($r eq "No") { return @l }
	if ($r eq "Yes") {
	    push @l, load_category__prompt($in, $category) || next;
	} else {
	    $in->ask_warn('', [ detect_devices::stringlist() ]);
	}
    }
}

sub wait_load_module {
    my ($in, $category, $text, $module) = @_;
#-PO: the first %s is the card type (scsi, network, sound,...)
#-PO: the second is the vendor+model name
    $in->wait_message('',
		     [ _("Installing driver for %s card %s", $category, $text),
		       if_($::expert, _("(module %s)", $module))
		     ]);
}

sub load_module__ask_options {
    my ($in, $module_descr, $parameters) = @_;

    if (@$parameters) {
	$in->ask_from('', 
		      _("You may now provide its options to module %s.\nNote that any address should be entered with the prefix 0x like '0x123'", $module_descr), 
		      [ map {; { label => $_->[0], help => $_->[1], val => \$_->[2] } } @$parameters ],
		     ) or return;
	map { if_($_->[2], "$_->[0]=$_->[2]") } @$parameters;
    } else {
	split ' ', $in->ask_from_entry('',
_("You may now provide options to module %s.
Options are in format ``name=value name2=value2 ...''.
For instance, ``io=0x300 irq=7''", $module_descr), _("Module options:"),
				);
    }
}

sub load_category__prompt {
    my ($in, $category) = @_;

    (my $msg_type = $category) =~ s/\|.*//;
    my %available_modules = map_each { $::a => $::b ? "$::a ($::b)" : $::a } modules::category2modules_and_description($category);
    my $module = $in->ask_from_listf('',
#-PO: the %s is the driver type (scsi, network, sound,...)
			       _("Which %s driver should I try?", $msg_type),
			       sub { $available_modules{$_[0]} },
			       [ keys %available_modules ]) or return;
    my $module_descr = $available_modules{$module};

    my @options;
    require modparm;
    my @parameters = modparm::parameters($module);
    if (@parameters && $in->ask_from_list_('',
_("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $module_descr), [ __("Autoprobe"), __("Specify options") ], 'Autoprobe') ne 'Autoprobe') {
	@options = load_module__ask_options($in, $module_descr, \@parameters);
    }
    while (1) {
	eval {
	    my $w = wait_load_module($in, $category, $module_descr, $module);
	    log::l("user asked for loading module $module (type $category, desc $module_descr)");
	    modules::load([ $module, @options ]);
	};
	return $module_descr if !$@;

	$in->ask_yesorno('',
_("Loading module %s failed.
Do you want to try again with other parameters?", $module_descr), 1) or return;

	@options = load_module__ask_options($in, $module_descr, \@parameters);
    }
}

sub ask_users {
    my ($prefix, $in, $users, $security) = @_;

    my $u if 0; $u ||= {};

    my @shells = map { chomp; $_ } cat_("$prefix/etc/shells");
    my @icons = facesnames($prefix);

    my %high_security_groups = (
        xgrp => _("access to X programs"),
	rpm => _("access to rpm tools"),
	wheel => _("allow \"su\""),
	adm => _("access to administrative files"),
    );
    while (1) {
	$u->{password2} ||= $u->{password} ||= '';
	$u->{shell} ||= '/bin/bash';
	my $names = @$users ? _("(already added %s)", join(", ", map { $_->{realname} || $_->{name} } @$users)) : '';

	my %groups;
	my $verif = sub {
	    $u->{password} eq $u->{password2} or $in->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return (1,2);
	    $security > 3 && length($u->{password}) < 6 and $in->ask_warn('', _("This password is too simple")), return (1,2);
	    $u->{name} or $in->ask_warn('', _("Please give a user name")), return (1,0);
	    $u->{name} =~ /^[a-z0-9_-]+$/ or $in->ask_warn('', _("The user name must contain only lower cased letters, numbers, `-' and `_'")), return (1,0);
	    length($u->{name}) <= 32 or $in->ask_warn('', _("The user name is too long")), return (1,0);
	    member($u->{name}, map { $_->{name} } @$users) and $in->ask_warn('', _("This user name is already added")), return (1,0);
	    return 0;
	};
	my $ret = $in->ask_from_(
	    { title => _("Add user"),
	      messages => _("Enter a user\n%s", $names),
	      ok => _("Accept user"),
	      cancel => $security < 4 || @$users ? _("Done") : '',
	      callbacks => {
	          focus_out => sub {
		      if ($_[0] eq 0) {
			  $u->{name} ||= lc first($u->{realname} =~ /([\w-]+)/);
		      }
		  },
	          complete => $verif,
                  canceled => sub { $u->{name} ? &$verif : 0; },
	    } }, [ 
	    { label => _("Real name"), val => \$u->{realname} },
	    { label => _("User name"), val => \$u->{name} },
            { label => _("Password"),val => \$u->{password}, hidden => 1 },
            { label => _("Password (again)"), val => \$u->{password2}, hidden => 1 },
            { label => _("Shell"), val => \$u->{shell}, list => [ shells($prefix) ], not_edit => !$::expert, advanced => 1 },
	      if_($security <= 3 && @icons,
	    { label => _("Icon"), val => \ ($u->{icon} ||= 'man'), list => \@icons, icon2f => sub { face2png($_[0], $prefix) }, format => \&translate },
	      ),
	      if_($security > 3,
		  map {; 
            { label => $_, val => \$groups{$_}, text => $high_security_groups{$_}, type => 'bool' }
		  } keys %high_security_groups,
	      ),
           ],
        );
	$u->{groups} = [ grep { $groups{$_} } keys %groups ];

	push @$users, $u if $u->{name};
	$u = {};
	$ret or return;
    }
}

sub autologin {
    my ($prefix, $o, $in) = @_;

    my $cmd = $prefix ? "chroot $prefix" : "";
    my @wm = (split (' ', `$cmd /usr/sbin/chksession -l 2>/dev/null`));
    my @users = map { $_->{name} } @{$o->{users} || []};

    if (@wm > 1 && @users && !$o->{authentication}{NIS} && $o->{security} <= 2) {
	add2hash_($o, { autologin => $users[0] });

	$in->ask_from_(
		       { title => _("Autologin"),
			 messages => _("I can set up your computer to automatically log on one user.
Do you want to use this feature?"),
			 ok => _("Yes"),
			 cancel => _("No") },
		       [ { label => _("Choose the default user:"), val => \$o->{autologin}, list => \@users },
			 { label => _("Choose the window manager to run:"), val => \$o->{desktop}, list => \@wm } ]
		      )
	  or delete $o->{autologin};
    } else {
	delete $o->{autologin};
    }
}

sub selectLanguage {
    my ($in, $lang, $langs_) = @_;
    my $langs = $langs_ || {};
    my @langs = lang::list(exclude_non_necessary_utf8 => $::isInstall, 
			   exclude_non_installed_langs => !$::isInstall,
			  );
    $in->ask_from_(
	{ messages => _("Please choose a language to use."),
	  title => 'language choice',
	  advanced_messages => formatAlaTeX(_("Mandrake Linux can support multiple languages. Select
the languages you would like to install. They will be available
when your installation is complete and you restart your system.")),
	  callbacks => {
	      focus_out => sub { $langs->{$lang} = 1 },
	  },
	},
	[ { val => \$lang, separator => '|', 
	    format => \&lang::lang2text, list => \@langs },
	    if_($langs_, (map {;
	       { val => \$langs->{$_->[0]}, type => 'bool', disabled => sub { $langs->{all} },
		 text => $_->[1], advanced => 1,
	       } 
	   } sort { $a->[1] cmp $b->[1] } map { [ $_, lang::lang2text($_) ] } lang::list()),
	  { val => \$langs->{all}, type => 'bool', text => _("All"), advanced => 1 }),
	]) or return;
    $lang;
}

sub write_passwd_user {
    my ($prefix, $u, $isMD5) = @_;

    $u->{pw} = &crypt($u->{password}, $isMD5) if $u->{password};
    $u->{shell} ||= '/bin/bash';

    substInFile {
	my $l = unpack_passwd($_);
	if ($l->{name} eq $u->{name}) {
	    add2hash_($u, $l);
	    $_ = pack_passwd($u);
	    $u = {};
	}
	if (eof && $u->{name}) {
	    $_ .= pack_passwd($u);
	}
    } "$prefix/etc/passwd";
}

sub set_login_serial_console {
    my ($prefix, $port, $speed) = @_;

    my $line = "s$port:12345:respawn:/sbin/getty ttyS$port DT$speed ansi\n";
    substInFile { s/^s$port:.*//; $_ = "$line" if eof } "$prefix/etc/inittab";
}


sub runlevel {
    my ($prefix, $runlevel) = @_;
    my $f = "$prefix/etc/inittab";
    -r $f or log::l("missing inittab!!!"), return;
    if ($runlevel) {
	substInFile { s/^id:\d:initdefault:\s*$/id:$runlevel:initdefault:\n/ } $f;
    } else {
	cat_($f) =~ /^id:(\d):initdefault:\s*$/ && $1;
    }
}

sub report_bug {
    my ($prefix, @other) = @_;

    sub header { "
********************************************************************************
* $_[0]
********************************************************************************";
    }

    join '', map { chomp; "$_\n" }
      header("lspci"), detect_devices::stringlist(),
      header("pci_devices"), cat_("/proc/bus/pci/devices"),
      header("fdisk"), arch() =~ /ppc/ ? `$ENV{LD_LOADER} pdisk -l` : `$ENV{LD_LOADER} fdisk -l`,
      header("scsi"), cat_("/proc/scsi/scsi"),
      header("lsmod"), cat_("/proc/modules"),
      header("cmdline"), cat_("/proc/cmdline"),
      header("pcmcia: stab"), cat_("$prefix/var/lib/pcmcia/stab") || cat_("$prefix/var/run/stab"),
      header("usb"), cat_("/proc/bus/usb/devices"),
      header("partitions"), cat_("/proc/partitions"),
      header("cpuinfo"), cat_("/proc/cpuinfo"),
      header("syslog"), cat_("/tmp/syslog") || cat_("$prefix/var/log/syslog"),
      header("ddcxinfos"), ddcxinfos(),
      header("stage1.log"), cat_("/tmp/stage1.log") || cat_("$prefix/root/drakx/stage1.log"),
      header("ddebug.log"), cat_("/tmp/ddebug.log") || cat_("$prefix/root/drakx/ddebug.log"),
      header("install.log"), cat_("$prefix/root/drakx/install.log"),
      header("fstab"), cat_("$prefix/etc/fstab"),
      header("modules.conf"), cat_("$prefix/etc/modules.conf"),
      header("lilo.conf"), cat_("$prefix/etc/lilo.conf"),
      header("menu.lst"), cat_("$prefix/boot/grub/menu.lst"),
      header("/etc/modules"), cat_("$prefix/etc/modules"),
      map_index { even($::i) ? header($_) : $_ } @other;
}

sub devfssymlinkf {
    my ($if, $of, $prefix) = @_;
    symlinkf($if, "$prefix/dev/$of");

    output_p("$prefix/etc/devfs/conf.d/$of.conf", 
"REGISTER	^$if\$	CFUNCTION GLOBAL symlink $if $of
UNREGISTER	^$if\$	CFUNCTION GLOBAL unlink $of
");
}

sub fileshare_config {
    my ($in, $type) = @_; #- $type is 'nfs', 'smb' or ''

    my $file = '/etc/security/fileshare.conf';
    my %conf = getVarsFromSh($file);

    my @l = (__("No sharing"), __("Allow all users"), __("Custom"));
    my $restrict = exists $conf{RESTRICT} ? text2bool($conf{RESTRICT}) : 1;

    if ($restrict) {
	#- verify we can export in $type
	my %type2file = (nfs => [ '/etc/init.d/nfs', 'nfs-utils' ], smb => [ '/etc/init.d/smb', 'samba' ]);
	my @wanted = $type ? $type : keys %type2file;
	my @have = grep { -e $type2file{$_}[0] } @wanted;
	if (!@have) {
	    if (@wanted == 1) {
		$in->ask_okcancel('', _("The package %s needs to be installed. Do you want to install it?", $type2file{$wanted[0]}[1]), 1) or return;
	    } else {
		my %choices;
		my $wanted = $in->ask_many_from_list('', _("You can export using NFS or Samba. Please select which you'd like to use."),
						  { list => \@wanted }) or return;
		@wanted = @$wanted or return;
	    }
	    $in->do_pkgs->install(map { $type2file{$_}[1] } @wanted);
	    @have = grep { -e $type2file{$_}[0] } @wanted;
	}
	if (!@have) {
	    $in->ask_warn('', _("Mandatory package %s is missing", $wanted[0]));
	    return;
	}
    }

    my $r = $in->ask_from_list_('fileshare',
_("Would you like to allow users to share some of their directories?
Allowing this will permit users to simply click on \"Share\" in konqueror and nautilus.

\"Custom\" permit a per-user granularity.
"),
				\@l, $l[$restrict ? 0 : 1]) or return;
    $restrict = $r ne $l[1];
    $conf{RESTRICT} = bool2yesno($restrict);

    setVarsInSh($file, \%conf);
    if ($r eq $l[2]) {
	# custom
	if ($in->ask_from_no_check(
	{
	 -e '/usr/bin/userdrake' ? (ok => _("Launch userdrake"), cancel => _("Cancel")) : (cancel => ''),
	 messages =>
_("The per-user sharing uses the group \"fileshare\". 
You can use userdrake to add a user in this group.")
	}, [])) {
	    if (!fork) { exec "userdrake" or c::_exit(0) }
	}
    }
}

sub ddcxinfos {
    my @l = `$ENV{LD_LOADER} ddcxinfos`;
    if ($::isInstall && -e "/tmp/ddcxinfos") {
	my @l_old = cat_("/tmp/ddcxinfos");
	if (@l < @l_old) {
	    log::l("new ddcxinfos is worse, keeping the previous one");
	    @l = @l_old;
	} elsif (@l > @l_old) {
	    log::l("new ddcxinfos is better, dropping the previous one");
	}
    }
    output("/tmp/ddcxinfos", @l) if $::isInstall;
    @l;
}

sub config_libsafe {
    my ($prefix, $libsafe) = @_;
    my %t = getVarsFromSh("$prefix/etc/sysconfig/system");
    if (@_ > 1) {
	$t{LIBSAFE} = bool2yesno($libsafe);
	setVarsInSh("$prefix/etc/sysconfig/system", \%t);
    }
    text2bool($t{LIBSAFE});
}

sub choose_security_options {
    my ($in, $security, $libsafe, $email, $options) = @_;
    my $expert_file = "/etc/security/msec/expert_mode";
		      
    my @shown_options = ();
    my $key = "";
    my $i=0;
    my $title;
		        
    my $expert_section = cat_($expert_file);

    if ($expert_section == 0) { $title = _("DrakSec - Network Advanced Options"); }
    elsif ($expert_section == 1) { $title = _("DrakSec - User Advanced Options"); }
    elsif ($expert_section == 2) { $title = _("DrakSec - Server Advanced Options"); }

    for $key (keys %$options) {
       $shown_options[$i]->{label} = "$options->{$key}{label}";
       $shown_options[$i]->{val} = $options->{$key}{val};
       $shown_options[$i]->{list} = $options->{$key}{list};
       $shown_options[$i]->{type} = $options->{$key}{type};
       $i++;
    }

    $in->ask_from(
         $title,
         _("Choose advanced security options\n\n"),
         [
            @shown_options
         ]
    );
}

sub choose_security_level {
    my ($in, $security, $libsafe) = @_;
    my $expert_file = "/etc/security/msec/expert_mode";

    my $email;

    my %l = (
      0 => _("Welcome To Crackers"),
      1 => _("Poor"),
      2 => _("Standard"),
      3 => _("High"),
      4 => _("Higher"),
      5 => _("Paranoid"),
    );
    my %help = (
      0 => _("This level is to be used with care. It makes your system more easy to use,
but very sensitive: it must not be used for a machine connected to others
or to the Internet. There is no password access."),
      1 => _("Password are now enabled, but use as a networked computer is still not recommended."),
      2 => _("This is the standard security recommended for a computer that will be used to connect to the Internet as a client."),
      3 => _("There are already some restrictions, and more automatic checks are run every night."),
      4 => _("With this security level, the use of this system as a server becomes possible.
The security is now high enough to use the system as a server which can accept
connections from many clients. Note: if your machine is only a client on the Internet, you should better choose a lower level."),
      5 => _("This is similar to the previous level, but the system is entirely closed and security features are at their maximum."),
    );
    delete @l{0,1};
    delete $l{5} if !$::expert;

    $in->ask_from(
            ("DrakSec Basic Options"),
            ("Please choose the desired security level") . "\n\n" .
            join('', map { "$l{$_}: " . formatAlaTeX($help{$_}) . "\n\n" } keys %l),
            [
              { label => _("Security level"), val => $security, list => [ sort keys %l ], format => sub { $l{$_} } },
                if_($in->do_pkgs->is_installed('libsafe') && arch() =~ /^i.86/,
                { label => _("Use libsafe for servers"), val => $libsafe, type => 'bool', text =>
                  _("A library which defends against buffer overflow and format string attacks.") } ),
                { label => _("Security user (login or email)"), val => $email, },
                { clicked_may_quit => sub { open(EXPERT, '>'.$expert_file); print EXPERT "0"; close EXPERT; },
                  val => _("NETWORK-RELATED SECURITY OPTIONS") },
                { clicked_may_quit => sub { open(EXPERT, '>'.$expert_file); print EXPERT "1"; close EXPERT; },
                  val => _("USER-RELATED SECURITY OPTIONS") },
                { clicked_may_quit => sub { open(EXPERT, '>'.$expert_file); print EXPERT "2"; close EXPERT; },
                  val => _("SERVER-RELATED SECURITY OPTIONS") }
            ],
    );
													 }

sub running_window_manager {
    my @window_managers = (
	'kdeinit: kwin', 
	qw(gnome-session icewm wmaker afterstep fvwm fvwm2 fvwm95 mwm twm enlightenment xfce blackbox sawfish olvwm),
    );
    foreach (@window_managers) {
	return $_ if `/sbin/pidof "$_"` > 0;
    }
    '';
}

sub ask_window_manager_to_logout {
    my ($wm) = @_;
    
    my %h = (
	'kdeinit: kwin' => "su $ENV{USER} -c 'dcop kdesktop default logout'",
	'gnome-session' => "save-session --kill",
	'icewm' => "killall -QUIT icewm",
    );
    system($h{$wm} || return);
    1;
}

sub get_secure_level {
    my ($prefix) = @_;

    cat_("/etc/profile")           =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.0 msec
    cat_("/etc/profile.d/msec.sh") =~ /export SECURE_LEVEL=(\d+)/ && $1 || #- 8.1 msec
      ${{ getVarsFromSh("$prefix/etc/sysconfig/msec") }}{SECURE_LEVEL}  || #- 8.2 msec
	$ENV{SECURE_LEVEL};
}

sub alloc_raw_device {
    my ($prefix, $device) = @_;
    my $used = 0;
    my $raw_dev;
    substInFile {
	$used = max($used, $1) if m|^\s*/dev/raw/raw(\d+)|;
	if (eof) {
	    $raw_dev = "raw/raw" . ($used + 1);
	    $_ .= "/dev/$raw_dev /dev/$device\n";
	}
    } "$prefix/etc/sysconfig/rawdevices";
    $raw_dev;
}

sub config_dvd {
    my ($prefix) = @_;
    if (my @dvds = grep { detect_devices::isDvdDrive($_) } detect_devices::cdroms__faking_ide_scsi()) {
	log::l("configuring DVD");
	#- create /dev/dvd symlink
	each_index {
	    devfssymlinkf($_->{device}, 'dvd' . ($::i ? $::i + 1 : ''), $prefix);
	} @dvds;
	if (my $raw_dev = alloc_raw_device($prefix, 'dvd')) {
	    devfssymlinkf($raw_dev, 'rdvd', $prefix);
	}	
    }
}

sub config_mtools {
    my ($prefix) = @_;
    my $file = "$prefix/etc/mtools.conf";
    -e $file or return;

    my ($f1, $f2) = detect_devices::floppies_dev();
    substInFile {
	s|drive a: file="(.*?)"|drive a: file="/dev/$f1"|;
	s|drive b: file="(.*?)"|drive b: file="/dev/$f2"| if $f2;
    } $file;
}

1;
