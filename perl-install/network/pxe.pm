package network::pxe;

use common;
use network::tools;
use Xconfig::resolution_and_depth;

our $tftp_root = "/var/lib/tftpboot";
my $client_path = '/X86PC/linux';
our $pxelinux_client_root = $tftp_root . $client_path;
our $pxelinux_images = $pxelinux_client_root . '/images';
our $pxelinux_help_file = $pxelinux_client_root . '/help.txt';
our $pxelinux_message_file = $pxelinux_client_root . '/messages';
my $pxelinux_config_root = $pxelinux_client_root . '/pxelinux.cfg';
our $pxelinux_config_file = $pxelinux_config_root . '/default';
our $pxe_config_file = '/etc/pxe.conf';

my @global_pxelinux_settings = qw(PROMPT DEFAULT DISPLAY TIMEOUT F1);
my @append_settings = qw(initrd ramdisk_size vga display);
my @automatic_settings = qw(method interface network server directory);

our %vga_bios_to_resolution = (
		    'normal' => "vga",
		    'text' => "text",
		    '' => "automatic",
		     map { $_->{bios} => "$_->{X}x$_->{Y}" } grep { $_->{Depth} == 16 } Xconfig::resolution_and_depth::bios_vga_modes()
		       );
our %vga_resolution_to_bios = reverse %vga_bios_to_resolution;

sub read_pxelinux_help {
    my ($help_file) = @_;
    my %info;
    foreach (cat_($help_file)) {
	/^(\w+)\s*:\s*(.*)$/ and $info{$1} = $2;
    }
    \%info;
}

sub read_pxelinux_conf {
    my ($conf_file, $help_file) = @_;
    my (%conf);
    my $info = read_pxelinux_help($help_file);
    my $entry = {};
    foreach (cat_($conf_file)) {
	my $global = join('|', @global_pxelinux_settings);
	if (/^($global)\s+(.*)/) {
	    $conf{lc($1)} = $2;
	} elsif (/^label\s+(.*)/) {
	    $entry->{label} = $1;
	} elsif (/^\s+LOCALBOOT\s+(\d+)/) {
	    $entry->{localboot} = $1;
	} elsif (/^\s+KERNEL\s+(.*)/) {
	    $entry->{kernel} = $1;
	} elsif (/^\s+APPEND\s+(.*)/) {
	    my @others;
	    foreach (split /\s+/, $1) {
		my ($option, $value) = /^(.+?)(?:=(.*))?$/;
		if (member($option, @append_settings)) {
		    $entry->{$option} = $value;
		} elsif ($option eq 'automatic') {
		    foreach (split /,/, $value) {
			my ($option, $value) = /^(.+?):(.+)$/;
			$entry->{$option} = $value;
		    }
		} else {
		    push @others, $_;
		}
	    }
	    $entry->{others} = join(' ', @others);
	}
	if (exists $entry->{label} && (exists $entry->{localboot} || exists $entry->{kernel} && exists $entry->{initrd})) {
	    $entry->{info} = $info->{$entry->{label}};
	    exists $entry->{vga} and $entry->{vga} = $vga_bios_to_resolution{$entry->{vga}};
	    push @{$conf{entries}}, $entry;
	    $entry = {};
	}
    }
    \%conf;
}


sub list_pxelinux_labels {
    my ($conf) = @_;
    map { $_->{label} } @{$conf->{entries}};
}

sub write_pxelinux_conf {
    my ($conf, $conf_file) = @_;

    output($conf_file,
	   join("\n",
		"# DO NOT EDIT auto_generated by drakpxelinux.pl",
		(map { $_ . ' ' . $conf->{lc($_)} } @global_pxelinux_settings),
		'',
		(map {
		    my $e = $_;
		    my $automatic = join(',', map { "$_:$e->{$_}" } grep { $e->{$_} } @automatic_settings);
		    ("label $e->{label}",
		     exists $e->{localboot} ?
		     "    LOCALBOOT $e->{localboot}" :
		     ("    KERNEL $e->{kernel}",
		      "    APPEND " . join(' ',
					   (map { "$_=$e->{$_}" } grep { $e->{$_} } @append_settings),
					   if_($automatic, "automatic=$automatic"),
					   $e->{others})),
		     '');
		 } @{$conf->{entries}})));
}

sub write_default_pxe_messages {
  my ($net) = @_;
  my $hostname = $net->{hostname} || chomp_(`hostname`);
  output($pxelinux_message_file, <<EOF);

                   Welcome to Mandrakelinux PXE Server
                                                       Pxelinux
              .              .-----------------------------------.
             /|\\            /    Press F1 for available images    \\
            /_|_\\           \\    Hosted by  $hostname
            \\ | /   _       /'-----------------------------------'
             \\|/   (')     /
              '.    U     /                                (O__
                 .   '.  /                 (o_  (o_  (0_   //\\
                 {o_   (o_  (o_  (o_  (o_  //\\  //\\  //\\  //  )
                 (')_  (`)_ (/)_ (/)_ (/)_ V_/_ V_/_ V_/_ V__/_
            ---------------------------------------------------------

 press F1 for help
EOF
}

sub write_default_pxe_help() {
  output($pxelinux_help_file, <<EOF);
Available images are:
---------------------
local: local boot
EOF
}

sub add_in_help {
  my ($NAME, $INFO) = @_;
  if (!any { /$NAME/ } cat_($pxelinux_help_file)) {
    append_to_file($pxelinux_help_file, <<EOF);
$NAME : $INFO
EOF

  } else {
    substInFile {
      s/$NAME.*/$NAME : $INFO/;
    } $pxelinux_help_file;
  }
}

sub change_label_in_help {
  my ($NAMEOLD, $NEWNAME) = @_;
  substInFile {
    s/$NAMEOLD\s(.*)/$NEWNAME $1/;
  } $pxelinux_help_file;
}

# remove entry in help.txt
sub remove_in_help {
  my ($NAME) = @_;
  substInFile {
    s/^$NAME\s:.*//x;
    s/^\s*$//;
  } $pxelinux_help_file;
}

# adjust pxe confi with good value
sub write_pxe_conf {
  my ($net, $interface) = @_;
  if (!-f "$pxe_config_file.orig") { cp_af($pxe_config_file, "$pxe_config_file.orig") }
  my $domainname = $net->{resolv}{domainname} || chomp_(`dnsdomainname`);
  my $ip_address = network::tools::get_interface_ip_address($net, $interface);

  substInFile {
    s/default_address.*/default_address=$ip_address/;
    s/mtftp_address.*/mtftp_address=$ip_address/;
    s/domain.*/domain=$domainname/;
  } $pxe_config_file;
}


sub get_pxelinux_config_file_for_mac_address {
    my ($mac_address) = @_;
    #- 01 is the hardware type: Ethernet (ARP type 1)
    $pxelinux_config_root . "/" . join('-', '01', split(/:/, $mac_address));
}

sub set_profile_for_mac_address {
    my ($profile, $to_install, $mac_address) = @_;
    if ($profile) {
	symlinkf("profiles/" . ($to_install ? "install/" : "boot/") . $profile, get_pxelinux_config_file_for_mac_address($mac_address));
    } else {
	unlink get_pxelinux_config_file_for_mac_address($mac_address);
    }
}

#- returns (profile_type, profile_name)
sub profile_from_file {
    my ($file) = @_;
    $file =~ m!(?:^|/)profiles/(\w+)/(.*)?$!;
}

sub read_profiles() {
    my %profiles_conf;

    foreach (all($pxelinux_config_root)) {
	my $file = $pxelinux_config_root . '/' . $_;
        if (-l $file && /^01(?:-([0-9a-z]{2}))+$/) {
	    #- per MAC address settings
	    #- the filename looks like 01-aa-bb-cc-dd-ee-ff
	    #- where AA:BB:CC:DD:EE:FF is the MAC address
	    my ($type, $name) = profile_from_file(readlink($file));
	    tr/-/:/;
	    my $mac_address = substr($_, 3);
	    $profiles_conf{per_mac}{$mac_address} = { profile => $name, to_install => $type eq 'install' };
	}
    }

    foreach my $type (qw(boot install)) {
        my $root = $pxelinux_config_root . '/profiles/' . $type;
        mkdir_p($root);
        $profiles_conf{profiles}{$type}{$_} = 1 foreach all($root);
    }

    \%profiles_conf;
}

#- returns (pxelinux entries file, help file)
sub get_pxelinux_profile_path {
    my ($profile, $type) = @_;
    my $root = $pxelinux_config_root . '/profiles/' . $type;
    "$root/$profile", "$root/help-$profile.txt";
}

sub list_profiles {
    my ($profiles_conf) = @_;
    sort(uniq(map { keys %{$profiles_conf->{profiles}{$_}} } qw(boot install)));
}

sub profile_exists {
    my ($profiles_conf, $profile) = @_;
    member($profile, network::pxe::list_profiles($profiles_conf));
}

sub find_next_profile_name {
    my ($profiles_conf, $prefix) = @_;
    my $i;
    /^$prefix(\d*)$/ && $1 >= $i and $i = $1 + 1 foreach network::pxe::list_profiles($profiles_conf);
    "$prefix$i";
}

sub add_empty_profile {
    my ($profiles_conf, $profile, $to_install) = @_;
    $to_install and $profiles_conf->{profiles}{install}{$profile} = 1;
    $profiles_conf->{profiles}{boot}{$profile} = 1;
}

sub copy_profile_for_type {
    my ($profile, $clone, $type) = @_;
    my ($pxe, $help) = get_pxelinux_profile_path($profile, $type);
    my ($clone_pxe, $clone_help) = get_pxelinux_profile_path($clone, $type);
    -r $pxe and cp_f($pxe, $clone_pxe);
    -r $help and cp_f($help, $clone_help);
}

sub clone_profile {
    my ($profiles_conf, $profile) = @_;
    my $clone = find_next_profile_name($profiles_conf, $profile);
    if (exists $profiles_conf->{profiles}{install}{$profile}) {
	$profiles_conf->{profiles}{install}{$clone} = 1;
	copy_profile_for_type($profile, $clone, 'install');
    }
    $profiles_conf->{profiles}{boot}{$clone} = 1;
    copy_profile_for_type($profile, $clone, 'boot');
}

sub remove_profile {
    my ($profiles_conf, $profile) = @_;
    foreach my $type (qw(boot install)) {
	delete $profiles_conf->{profiles}{$type}{$profile};
	unlink foreach get_pxelinux_profile_path($profile, $type);
    }
}

1;
