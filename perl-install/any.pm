package any;

use diagnostics;
use strict;
use vars qw(@users);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file :functional);
use commands;
use detect_devices;
use partition_table qw(:types);
use fsedit;
use fs;
use run_program;
use modules;
use log;

sub facesdir {
    my ($prefix) = @_;
    "$prefix/usr/share/faces/";
}
sub face2xpm {
    my ($face, $prefix) = @_;
    facesdir($prefix) . $face . ".xpm";
}
sub facesnames {
    my ($prefix) = @_;
    my $dir = facesdir($prefix);
    grep { -e "$dir/$_.png" } map { /(.*)\.xpm/ } all($dir);
}

sub addKdmIcon {
    my ($prefix, $user, $icon) = @_;
    my $dest = "$prefix/usr/share/faces/$user.png";
    eval { commands::cp("-f", facesdir($prefix) . $icon . ".png", $dest) } if $icon;
}

sub allocUsers {
    my ($prefix, @users) = @_;
    my @m = my @l = facesnames($prefix);
    foreach (grep { !$_->{icon} || $_->{icon} eq "automagic" } @users) {
	$_->{auto_icon} = splice(@m, rand(@m), 1); #- known biased (see cookbook for better)
	log::l("auto_icon is $_->{auto_icon}");
	@m = @l unless @m;
    }
}

sub addUsers {
    my ($prefix, @users) = @_;
    my $msec = "$prefix/etc/security/msec";

    allocUsers($prefix, @users);
    foreach my $u (@users) {
	substInFile { s/^$u->{name}\n//; $_ .= "$u->{name}\n" if eof } "$msec/user.conf" if -d $msec;
	addKdmIcon($prefix, $u->{name}, delete $u->{auto_icon} || $u->{icon});
    }
    run_program::rooted($prefix, "/usr/share/msec/grpuser.sh --refresh");
#    addKdmIcon($prefix, 'root', 'root');
}

sub crypt {
    my ($password, $md5) = @_;
    $md5 ?
      c::crypt_md5($password, salt(8)) :
         crypt    ($password, salt(2));
}
sub enableShadow {
    my ($prefix) = @_;
    run_program::rooted($prefix, "pwconv")  or log::l("pwconv failed");
    run_program::rooted($prefix, "grpconv") or log::l("grpconv failed");
}
sub enableMD5Shadow {
    my ($prefix, $shadow, $md5) = @_;
    substInFile {
	if (/^password.*pam_pwdb.so/) {
	    s/\s*shadow//; s/\s*md5//;
	    s/$/ shadow/ if $shadow;
	    s/$/ md5/ if $md5;
	}
    } grep { -r $_ } map { "$prefix/etc/pam.d/$_" } qw(login rlogin passwd);
}

sub setupBootloader {
    my ($in, $b, $hds, $fstab, $security, $prefix, $more) = @_;

    $more++ if $b->{bootUnsafe};

    if ($::beginner && $more >= 1) {
	my @l = (__("First sector of drive (MBR)"), __("First sector of boot partition"));

	$in->set_help('setupBootloaderBeginner') unless $::isStandalone;
	if (arch() =~ /sparc/) {
	    $b->{use_partition} = $in->ask_from_list_(_("SILO Installation"),
						      _("Where do you want to install the bootloader?"),
						      \@l, $l[$b->{use_partition}]);
	} else {
	    my $boot = $hds->[0]{device};
	    my $onmbr = "/dev/$boot" eq $b->{boot};
	    $b->{boot} = "/dev/" . ($in->ask_from_list_(_("LILO/grub Installation"),
							_("Where do you want to install the bootloader?"),
							\@l, $l[!$onmbr]) eq $l[0] 
				    ? $boot : fsedit::get_root($fstab, 'boot')->{device});
	}
    } elsif ($more || !$::beginner) {
	$in->set_help(arch() =~ /sparc/ ? "setupSILOGeneral" : "setupBootloaderGeneral") unless $::isStandalone; #- TO MERGE ?

	if ($::expert) {
	    my $default = arch() =~ /sparc/ ? 'silo' : 'grub';
	    my $m = $in->ask_from_list_('', _("Which bootloader(s) do you want to use?"), [ keys(%{$b->{methods}}), __("None") ], $default) or return;
	    $b->{methods}{$_} = 0 foreach keys %{$b->{methods}};
	    $b->{methods}{$m} = 1 if $m ne "None";
	}
	#- at least one method
	grep_each { $::b } %{$b->{methods}} or return;

	#- put lilo if grub is chosen, so that /etc/lilo.conf is generated
	exists $b->{methods}{lilo} and $b->{methods}{lilo} = 1 if $b->{methods}{grub};

	my @silo_install_lang = (_("First sector of drive (MBR)"), _("First sector of boot partition"));
	my $silo_install_lang = $silo_install_lang[$b->{use_partition}];
	my @l = (
arch() =~ /sparc/ ? (
_("Bootloader installation") => { val => \$silo_install_lang, list => \@silo_install_lang },
) : (
_("Boot device") => { val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } @$hds, @$fstab), detect_devices::floppies() ], not_edit => !$::expert },
_("LBA (doesn't work on old BIOSes)") => { val => \$b->{lba32}, type => "bool", text => "lba" },
_("Compact") => { val => \$b->{compact}, type => "bool", text => _("compact") },
_("Video mode") => { val => \$b->{vga}, list => [ keys %bootloader::vga_modes ], not_edit => $::beginner },
),
_("Delay before booting default image") => \$b->{timeout},
$security < 4 ? () : (
_("Password") => { val => \$b->{password}, hidden => 1 },
_("Password (again)") => { val => \$b->{password2}, hidden => 1 },
_("Restrict command line options") => { val => \$b->{restricted}, type => "bool", text => _("restrict") },
)
	);
	@l = @l[0..3] unless $::expert; #- take "bootloader installation" and "delay before ..." on SPARC.

	$b->{vga} ||= 'Normal';
	$in->ask_from_entries_refH('', _("Bootloader main options"), \@l,
				 complete => sub {
#-				     $security > 4 && length($b->{password}) < 6 and $in->ask_warn('', _("At this level of security, a password (and a good one) in lilo is requested")), return 1;
				     $b->{restricted} && !$b->{password} and $in->ask_warn('', _("Option ``Restrict command line options'' is of no use without a password")), return 1;
				     $b->{password} eq $b->{password2} or !$b->{restricted} or $in->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return 1;
				     0;
				 }
				) or return 0;
	$b->{use_partition} = $silo_install_lang eq _("First sector of drive (MBR)") ? 0 : 1;
	$b->{vga} = $bootloader::vga_modes{$b->{vga}} || $b->{vga};
    }

    until ($::beginner && $more <= 1) {
	$in->set_help(arch() =~ /sparc/ ? 'setupSILOAddEntry' : 'setupBootloaderAddEntry') unless $::isStandalone;
	my $c = $in->ask_from_listf([''], 
_("Here are the different entries.
You can add some more or change the existing ones."),
		sub {
		    my ($e) = @_;
		    ref $e ? 
		      "$e->{label} ($e->{kernel_or_dev})" . ($b->{default} eq $e->{label} && "  *") : 
		      translate($e);
		},
		[ @{$b->{entries}}, __("Add"), __("Done") ]);

	$c eq "Done" and last;

	my ($e);

	if ($c eq "Add") {
	    my @labels = map { $_->{label} } @{$b->{entries}};
	    my $prefix;
	    if ($in->ask_from_list_('', _("Which type of entry do you want to add?"),
				    [ __("Linux"), arch() =~ /sparc/ ? __("Other OS (SunOS...)") : __("Other OS (windows...)") ]
				   ) eq "Linux") {
		$e = { type => 'image',
		       root => '/dev/' . fsedit::get_root($fstab)->{device}, #- assume a good default.
		     };
		$prefix = "linux";
	    } else {
		$e = { type => 'other' };
		$prefix = arch() =~ /sparc/ ? "sunos" : "windows";
	    }
	    $e->{label} = $prefix;
	    for (my $nb = 0; member($e->{label}, @labels); $nb++) { $e->{label} = "$prefix-$nb" }
	} else { 
	    $e = $c;
	}
	my %old_e = %$e;
	my $default = my $old_default = $e->{label} eq $b->{default};

	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
_("Image") => { val => \$e->{kernel_or_dev}, list => [ map { s/$prefix//; $_ } glob_("$prefix/boot/vmlinuz*") ], not_edit => 0 },
_("Root") => { val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
_("Append") => \$e->{append},
_("Initrd") => { val => \$e->{initrd}, list => [ map { s/$prefix//; $_ } glob_("$prefix/boot/initrd*") ] },
_("Read-write") => { val => \$e->{'read-write'}, type => 'bool' }
	    );
	    @l = @l[0..5] unless $::expert;
	} else {
	    @l = ( 
_("Root") => { val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
arch() !~ /sparc/ ? (
_("Table") => { val => \$e->{table}, list => [ '', map { "/dev/$_->{device}" } @$hds ], not_edit => !$::expert },
_("Unsafe") => { val => \$e->{unsafe}, type => 'bool' }
) : (),
	    );
	    @l = @l[0..1] unless $::expert;
	}
	@l = (
_("Label") => \$e->{label},
@l,
_("Default") => { val => \$default, type => 'bool' },
	);

	if ($in->ask_from_entries_refH($c eq "Add" ? '' : ['', _("Ok"), _("Remove entry")], 
	    '', \@l,
	    complete => sub {
		$e->{label} or $in->ask_warn('', _("Empty label not allowed")), return 1;
		member($e->{label}, map { $_->{label} } grep { $_ != $e } @{$b->{entries}}) and $in->ask_warn('', _("This label is already used")), return 1;
		0;
	    })) {
	    $b->{default} = $old_default || $default ? $default && $e->{label} : $b->{default};
	    require bootloader;
	    bootloader::configure_entry($prefix, $e); #- hack to make sure initrd file are built.

	    push @{$b->{entries}}, $e if $c eq "Add";
	} else {
	    @{$b->{entries}} = grep { $_ != $e } @{$b->{entries}};
	}
    }
    1;
}

sub setAutologin {
  my ($prefix, $user, $desktop) = @_;
  $user and do {
      local *F;
      open F, ">$prefix/home/$user/.wmrc" or die "Can't open $!";
      print F $desktop;
      close F;
  };
  my @wm = (qw(gnome ice maker kde after fvwm fvwm2 fvwm95 mwm twm enligh xfce blackbox sawfish));
  my @wm2 = (qw(gnome-session icewm wmaker kdestart afterstep fvwm fvwm2 fvwm95 mwm twm enlightenment xfce blackbox sawfish));
  my $i=0;
  foreach (@wm) {
      lc($desktop) =~ /$_/ and $desktop = $wm2[$i] and last;
      $i++;
  }
  my $f = "$prefix/home/$user/.xinitrc";
  -e $f or do {
      open F, ">$f" or die "Can't open $!";
      print F "# Mandrake-Autologin : if you remove this comment, I won't ever edit this file.";
      close F; };
  cat_($f) =~ /^# Mandrake-Autologin.*\n/ and do {
      substInFile {
	  s/^exec .*\n//;
	  $_ = "exec $desktop\n" . $_ if eof;
      } "$prefix/home/$user/.xinitrc"; };
  setVarsInSh("$prefix/etc/sysconfig/autologin",
	      { USER => $user, AUTOLOGIN => bool2yesno($user), EXEC => "/usr/X11R6/bin/startx" });
}


sub writeandclean_ldsoconf {
    my ($prefix) = @_;
    my $file = "$prefix/etc/ld.so.conf";

    log::l("before: ", cat_($file));
    output $file,
      grep { !m|^(/usr)?/lib$| } #- no need to have /lib and /usr/lib in ld.so.conf
	uniq cat_($file), "/usr/X11R6/lib\n";
    log::l("after: ", cat_($file));
}

sub shells {
    my ($prefix) = @_;
    grep { -x "$prefix$_" } map { chomp; $_ } cat_("$prefix/etc/shells");
}

sub inspect {
    my ($part, $prefix, $rw) = @_;

    isMountableRW($part) or return;

    my $dir = "/tmp/inspect_tmp_dir";

    if ($part->{isMounted}) {
	$dir = ($prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	$dir = '';
    } else {
	mkdir $dir, 0700;
	eval { fs::mount($part->{device}, $dir, type2fs($part->{type}), !$rw) };
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
    my ($in, $modem, $prefix, $install) = @_;
    $modem or return;

    symlinkf($modem->{device}, "$prefix/dev/modem") or log::l("creation of $prefix/dev/modem failed");
    $install->(qw(ppp)) unless $::testing;

    my %toreplace;
    $toreplace{$_} = $modem->{$_} foreach qw(connection phone login passwd auth domain dns1 dns2);
    $toreplace{kpppauth} = ${{ 'Script-based' => 0, 'PAP' => 1, 'Terminal-based' => 2, }}{$modem->{auth}};
    $toreplace{phone} =~ s/\D//g;
    $toreplace{dnsserver} = join ',', map { $modem->{$_} } "dns1", "dns2";
    $toreplace{dnsserver} .= $toreplace{dnsserver} && ',';

    #- using peerdns or dns1,dns2 avoid writing a /etc/resolv.conf file.
    $toreplace{peerdns} = "yes";

    $toreplace{connection} ||= 'DialupConnection';
    $toreplace{domain} ||= 'localdomain';
    $toreplace{intf} ||= 'ppp0';
    $toreplace{papname} = $modem->{auth} eq 'PAP' && $toreplace{login};

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
'OK'
END
    if ($modem->{special_command}) {
	print CHAT <<END;
'$modem->{special_command}'
'OK'
END
    }
    print CHAT <<END
'ATDT$toreplace{phone}'
'CONNECT' ''
END
    if ($modem->{auth} eq 'Terminal-based' || $modem->{auth} eq 'Script-based') {
	print CHAT <<END;
'ogin:' '$toreplace{login}'
'ord:' '$toreplace{passwd}'
END
    }
    print CHAT <<END;
'TIMEOUT' '5'
'~--' ''
END
    close CHAT;

    if ($modem->{auth} eq 'PAP') {
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

    #-install_any::template2userfile($o->{prefix}, "$ENV{SHARE_PATH}/kppprc.in", ".kde/share/config/kppprc", 1, %toreplace);
    commands::mkdir_("-p", "$prefix/usr/share/config");
    template2file("$ENV{SHARE_PATH}/kppprc.in", "$prefix/usr/share/config/kppprc", %toreplace);

    miscellaneousNetwork($prefix);
}

sub miscellaneousNetwork {
    my ($prefix) = @_;
    setVarsInSh ("$prefix/etc/profile.d/proxy.sh",  $::o->{miscellaneous}, qw(http_proxy ftp_proxy));
    setVarsInCsh("$prefix/etc/profile.d/proxy.csh", $::o->{miscellaneous}, qw(http_proxy ftp_proxy));
}

sub load_thiskind {
    my ($in, $type) = @_;
    my $w;
    modules::load_thiskind($type, sub { $w = wait_load_module($in, $type, @_) });
}

sub setup_thiskind {
    my ($in, $type, $auto, $at_least_one) = @_;

    return if arch() eq "ppc";

    my @l;
    if (!$::noauto) {
	@l = load_thiskind($in, $type);
	if (my @err = grep { $_ } map { $_->{error} } @l) {
	    $in->ask_warn('', join("\n", @err));
	}
	return @l if $auto && (@l || !$at_least_one);
    }
    @l = map { $_->{description} } @l;
    while (1) {
	(my $msg_type = $type) =~ s/\|.*//;
	my $msg = @l ?
	  [ _("Found %s %s interfaces", join(", ", @l), $msg_type),
	    _("Do you have another one?") ] :
	  _("Do you have any %s interfaces?", $msg_type);

	my $opt = [ __("Yes"), __("No") ];
	push @$opt, __("See hardware info") if $::expert;
	my $r = "Yes";
	$r = $in->ask_from_list_('', $msg, $opt, "No") unless $at_least_one && @l == 0;
	if ($r eq "No") { return @l }
	if ($r eq "Yes") {
	    push @l, load_module($in, $type) || next;
	} else {
	    $in->ask_warn('', [ detect_devices::stringlist() ]);
	}
    }
}

sub wait_load_module {
    my ($in, $type, $text, $module) = @_;
#-PO: the first %s is the card type (scsi, network, sound,...)
#-PO: the second is the vendor+model name
    $in->wait_message('',
		     [ _("Installing driver for %s card %s", $type, $text),
		       $::beginner ? () : _("(module %s)", $module)
		     ]);
}

sub load_module {
    my ($in, $type) = @_;
    my @options;

    my $m = $in->ask_from_listf('',
#-PO: the %s is the driver type (scsi, network, sound,...)
			       _("Which %s driver should I try?", $type),
			       \&modules::module2text,
			       [ modules::module_of_type($type) ]) or return;
    my $l = modules::module2text($m);
    require modparm;
    my @names = modparm::get_options_name($m);

    if ((@names != 0) && $in->ask_from_list_('',
_("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $l),
			      [ __("Autoprobe"), __("Specify options") ], "Autoprobe") ne "Autoprobe") {
      ASK:
	if (@names >= 0) {
	    my @l = $in->ask_from_entries('',
_("You may now provide its options to module %s.", $l),
					 \@names) or return;
	    @options = modparm::get_options_result($m, @l);
	} else {
	    @options = split ' ',
	      $in->ask_from_entry('',
_("You may now provide its options to module %s.
Options are in format ``name=value name2=value2 ...''.
For instance, ``io=0x300 irq=7''", $l),
				 _("Module options:"),
				);
	}
    }
    eval { 
	my $w = wait_load_module($in, $type, $l, $m);
	modules::load($m, $type, @options);
    };
    if ($@) {
	$in->ask_yesorno('',
_("Loading module %s failed.
Do you want to try again with other parameters?", $l), 1) or return;
	goto ASK;
    }
    $l;
}


1;
