package bootloader; # $Id$

use diagnostics;
use strict;
use vars qw(%vga_modes);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :functional :system);
use partition_table qw(:types);
use log;
use any;
use fsedit;
use devices;
use loopback;
use commands;
use detect_devices;
use partition_table_raw;
use run_program;
use modules;


%vga_modes = (
 "Ask at boot" => 'ask',
 "Normal" => 'normal',
 "80x50" => '0x0f01',
 "80x43" => '0x0f02',
 "80x28" => '0x0f03',
 "80x30" => '0x0f04',
 "80x34" => '0x0f05',
 "80x60" => '0x0f06',
 "100x30" => '0x0122',
 "640x480 in 16 bits (FrameBuffer only)" => 785,
 "800x600 in 16 bits (FrameBuffer only)" => 788,
 "1024x768 in 16 bits (FrameBuffer only)" => 791,
 "1280x1024 in 16 bits (FrameBuffer only)" => 794,
);

my %vga_modes2nb = (
 'ask'    => -3,
 'normal' => -1,
#- other entries are identity
);


#-#####################################################################################
#- Functions
#-#####################################################################################

sub get {
    my ($kernel, $bootloader) = @_;
    $_->{kernel_or_dev} && $_->{kernel_or_dev} eq $kernel and return $_ foreach @{$bootloader->{entries}};
    undef;
}
sub get_label {
    my ($label, $bootloader) = @_;
    $_->{label} && $_->{label} eq $label and return $_ foreach @{$bootloader->{entries}};
    undef;
}

sub mkinitrd($$$) {
    my ($prefix, $kernelVersion, $initrdImage) = @_;

    $::testing || -e "$prefix/$initrdImage" and return;

    my $loop_boot = loopback::prepare_boot($prefix);

    modules::load('loop');
    run_program::rooted($prefix, "mkinitrd", "-f", $initrdImage, "--ifneeded", $kernelVersion) or unlink("$prefix/$initrdImage");

    loopback::save_boot($loop_boot);

    -e "$prefix/$initrdImage" or die "mkinitrd failed";
}

sub mkbootdisk($$$;$) {
    my ($prefix, $kernelVersion, $dev, $append) = @_;

    modules::load_multi(arch() =~ /sparc/ ? 'romfs' : (), 'loop');
    my @l = qw(mkbootdisk --noprompt); 
    push @l, "--appendargs", $append if $append;
    if ($dev =~ /fd/) {
	devices::make($dev . 'H1440');
    } else {
	push @l, "--bios", 0, if $dev !~ /fd/;
    }
    run_program::rooted_or_die($prefix, @l, "--device", "/dev/$dev", $kernelVersion);
}

sub read($$) {
    my ($prefix, $file) = @_;
    my $global = 1;
    my ($e, $v, $f);
    my %b;
    foreach (cat_("$prefix$file")) {
	($_, $v) = /^\s*(.*?)\s*(?:=\s*(.*?))?\s*$/;

	if (/^(image|other)$/) {
	    push @{$b{entries}}, $e = { type => $_, kernel_or_dev => $v };
	    $global = 0;
	} elsif ($global) {
	    $b{$_} = $v || 1;
	} else {
	    if ((/map-drive/ .. /to/) && /to/) {
		$e->{mapdrive}{$e->{'map-drive'}} = $v;
	    } else {
		$e->{$_} = $v || 1;
	    }
	}
    }
    delete $b{timeout} unless $b{prompt};
    $_->{append} =~ s/^\s*"?(.*?)"?\s*$/$1/ foreach \%b, @{$b{entries}};
    $b{timeout} = $b{timeout} / 10 if $b{timeout};
    $b{message} = cat_("$prefix$b{message}") if $b{message};
    \%b;
}

sub suggest_onmbr($) {
    my ($hds) = @_;
    
    my $type = partition_table_raw::typeOfMBR($hds->[0]{device});
    !$type || member($type, qw(dos dummy lilo grub empty)), !$type;
}

sub compare_entries($$) {
    my ($a, $b) = @_;
    my %entries;

    @entries{keys %$a, keys %$b} = ();
    $a->{$_} eq $b->{$_} and delete $entries{$_} foreach keys %entries;
    scalar keys %entries;
}

sub add_entry($$) {
    my ($entries, $v) = @_;
    my (%usedold, $freeold);

    do { $usedold{$1 || 0} = 1 if $_->{label} =~ /^old ([^_]*)_/x } foreach @$entries;
    foreach (0..scalar keys %usedold) { exists $usedold{$_} or $freeold = $_ || '', last }

    foreach (@$entries) {
	if ($_->{label} eq $v->{label}) {
	    compare_entries($_, $v) or return; #- avoid inserting it twice as another entry already exists !
	    $_->{label} = "old${freeold}_$_->{label}";
	}
    }
    push @$entries, $v;
}

sub add_kernel($$$$$) {
    my ($prefix, $lilo, $kernelVersion, $specific, $v) = @_;
    my $ext = $specific && "-$specific"; $specific =~ s/\d+\.\d+|hack//;
    my $kname = "vmlinuz";
    if (arch() =~ /ppc/) { 
    	$kname = "vmlinux";
    }
	my ($vmlinuz, $image, $initrdImage) = ("$kname-$kernelVersion$specific", "/boot/$kname$ext", "/boot/initrd$ext.img");    
    -e "$prefix/boot/$vmlinuz" or log::l("unable to find kernel image $prefix/boot/$vmlinuz"), return;
    {
	my $f = "initrd-$kernelVersion$specific.img";
	eval { mkinitrd($prefix, "$kernelVersion$specific", "/boot/$f") };
	undef $initrdImage if $@;
	symlinkf $f, "$prefix$initrdImage" or $initrdImage = "/boot/$f"
	  if $initrdImage;
    }
    symlinkf "$vmlinuz", "$prefix/$image" or $image = "/boot/$vmlinuz";
    add2hash($v,
	     {
	      type => 'image',
	      label => 'linux',
	      kernel_or_dev => $image,
	      initrd => $initrdImage,
	      append => $lilo->{perImageAppend},
	     });
    add_entry($lilo->{entries}, $v);
    $v;
}

sub get_append {
    my ($b, $key) = @_;
    ($b->{perImageAppend} =~ /\b$key=(\S*)/)[0];
}
sub add_append {
    my ($b, $key, $val) = @_;

    foreach ({ append => $b->{perImageAppend} }, @{$b->{entries}}) {
	$_->{append} =~ s/\b$key=\S*\s*//;
	$_->{append} =~ s/\s*$/ $key=$val)/ if $val;
    }
}

sub configure_entry($$) {
    my ($prefix, $entry) = @_;
    if ($entry->{type} eq 'image') {
	my $specific_version;
	$entry->{kernel_or_dev} =~ /vmlinu.-(.*)/ and $specific_version = $1;
	readlink("$prefix/$entry->{kernel_or_dev}") =~ /vmlinu.-(.*)/ and $specific_version = $1;

	if ($specific_version) {
	    $entry->{initrd} or $entry->{initrd} = "/boot/initrd-$specific_version.img";
	    unless (-e "$prefix/$entry->{initrd}") {
		eval { mkinitrd($prefix, $specific_version, "$entry->{initrd}") };
		undef $entry->{initrd} if $@;
	    }
	}
    }
    $entry;
}

sub dev2prompath { #- SPARC only
    my ($dev) = @_;
    my ($wd, $num) = $dev =~ /^(.*\D)(\d*)$/;
    require c;
    $dev = c::disk2PromPath($wd) and $dev = $dev =~ /^sd\(/ ? "$dev$num" : "$dev;$num";
    $dev;
}

sub suggest {
    my ($prefix, $lilo, $hds, $fstab, $kernelVersion, $vga_fb) = @_;
    my $root_part = fsedit::get_root($fstab);
    my $root = isLoopback($root_part) ? "loop7" : $root_part->{device};
    my $boot = fsedit::get_root($fstab, 'boot')->{device};
    my $partition = first($boot =~ /\D*(\d*)/);

    require c; c::initSilo() if arch() =~ /sparc/;

    my ($onmbr, $unsafe) = $lilo->{crushMbr} ? (1, 0) : suggest_onmbr($hds);
    add2hash_($lilo, arch() =~ /sparc/ ?
	{
	 default => "linux",
	 entries => [],
	 timeout => 5,
	 use_partition => 0, #- we should almost always have a whole disk partition.
	 root          => "/dev/$root",
	 partition     => $partition || 1,
	 boot          => $root eq $boot && "/boot", #- this helps for getting default partition for silo.
	} : arch =~ /ppc/ ?
	{
	 defaultos => "linux",
	 default => "linux",
	 entries => [],
	 initmsg => "Welcome to Mandrake Linux!",
	 delay => 30,	#- OpenFirmware delay
	 timeout => 50,
	 enableofboot => 1,
	 enablecdboot => 1,
	} :
	{
	 boot => "/dev/" . ($onmbr ? $hds->[0]{device} : fsedit::get_root($fstab, 'boot')->{device}),
	 bootUnsafe => $unsafe,
	 map => "/boot/map",
	 default => "linux",
	 lba32 => 1,
	 entries => [],
	 timeout => $onmbr && 5,
	 install => "/boot/boot.b",
	});
#- the following is not needed anymore with latest lilo
#-    $lilo->{disk} ||= "/dev/$hds->[0]{device} bios=0x80" if $hds->[0]{device} =~ /^hd[be]$/;

    if (!$lilo->{message} || $lilo->{message} eq "1") {
	$lilo->{message} = join('', cat_("$prefix/boot/message"));
	if (!$lilo->{message}) {
	    my $msg_en =
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
__("Welcome to %s the operating system chooser!

Choose an operating system in the list above or
wait %d seconds for default boot.

");
	    my $msg = translate($msg_en);
	    #- use the english version if more than 20% of 8bits chars
	    $msg = $msg_en if int(grep { $_ & 0x80 } unpack "c*", $msg) / length($msg) > 0.2;
	    $lilo->{message} = sprintf $msg, arch() =~ /sparc/ ? "SILO" : "LILO", $lilo->{timeout};
	}
    }


    add2hash_($lilo, { getVarsFromSh("$prefix/etc/sysconfig/system") }); #- for CLEAN_TMP
    add2hash_($lilo, { memsize => $1 }) if cat_("/proc/cmdline") =~ /mem=(\S+)/;

    my $isSecure = -e "$prefix/boot/vmlinuz-${kernelVersion}secure";

    my $isSMP = detect_devices::hasSMP();
    if ($isSMP && !-e "$prefix/boot/vmlinuz-${kernelVersion}smp") {
	log::l("SMP machine, but no SMP kernel found") unless $isSecure;
	$isSMP = 0;
    }
    add_kernel($prefix, $lilo, $kernelVersion, $isSecure ? 'secure' : $isSMP ? 'smp' : '',
	       {
		label => 'linux',
		root  => "/dev/$root",
		$vga_fb ? ( vga => $vga_fb) : (), #- using framebuffer
	       });
    add_kernel($prefix, $lilo, $kernelVersion, '',
	       {
		label => $isSecure || $isSMP ? 'linux-up' : 'linux-nonfb',
		root  => "/dev/$root",
	       }) if $isSecure || $isSMP || $vga_fb;
    add_kernel($prefix, $lilo, $kernelVersion, '',
	       {
		label => 'failsafe',
		root  => "/dev/$root",
	       })->{append} .= " failsafe" unless $lilo->{password};

    #- manage older kernel if installed.
    foreach (qw(2.2 hack)) {
	my $hasOld = -e "$prefix/boot/vmlinuz-$_";
	if ($hasOld) {
	    my $oldVersion = first(readlink("$prefix/boot/vmlinuz-$_") =~ /vmlinuz-(.*mdk)/);
	    my $oldSecure = -e "$prefix/boot/vmlinuz-${_}secure";
	    my $oldSMP = $isSMP && -e "$prefix/boot/vmlinuz-${_}smp";

	    add_kernel($prefix, $lilo, $oldVersion, $oldSecure ? "${_}secure" : $oldSMP ? "${_}smp" : $_,
		       {
			label => "linux-$_",
			root  => "/dev/$root",
			$vga_fb ? ( vga => $vga_fb) : (), #- using framebuffer
		       });
	    add_kernel($prefix, $lilo, $oldVersion, $_,
		       {
			label => $oldSecure || $oldSMP ? "linux-${_}up" : "linux-${_}nonfb",
			root  => "/dev/$root",
		       }) if $oldSecure || $oldSMP || $vga_fb;
	    add_kernel($prefix, $lilo, $oldVersion, $_,
		       {
			label => "failsafe-$_",
			root  => "/dev/$root",
		       })->{append} .= " failsafe" unless $lilo->{password};
	}
    }

    if (arch() =~ /sparc/) {
	#- search for SunOS, it could be a really better approach to take into account
	#- partition type for mounting point.
	my $sunos = 0;
	foreach (@$hds) {
	    foreach (@{$_->{primary}{normal}}) {
		my $path = $_->{device} =~ m|^/| && $_->{device} !~ m|^/dev/| ? $_->{device} : dev2prompath($_->{device});
		add_entry($lilo->{entries},
			  {
			   type => 'other',
			   kernel_or_dev => $path,
			   label => "sunos"   . ($sunos++ ? $sunos : ''),
			  }) if $path && isSunOS($_) && type2name($_->{type}) =~ /root/i;
	    }
	}
    } elsif (arch() =~ /ppc/) {
	#- if we identified a MacOS partition earlier - add it
	if (defined $partition_table_mac'macos_part) {
	    add_entry($lilo->{entries},
		      {
		       label => "macos",
		       kernel_or_dev => $partition_table_mac'macos_part
		      });
	}
    } else {
	#- search for dos (or windows) boot partition. Don't look in extended partitions!
	my ($dos, $win) = 0, 0;
	foreach (@$hds) {
	    foreach (@{$_->{primary}{normal}}) {
		add_entry($lilo->{entries},
			  {
			   type => 'other',
			   kernel_or_dev => "/dev/$_->{device}",
			   label => isDos($_) ? "dos"     . ($dos++ ? $dos : '') : "windows" . ($win++ ? $win : '') ,
			   table => "/dev/$_->{rootDevice}",
			   unsafe => 1
			  }) if isFat($_) && isFat({ type => fsedit::typeOfPart($_->{device}) });
	    }
	}
    }
    my %l = (
 		yaboot => bool(arch() =~ /ppc/),
	     silo => bool(arch() =~ /sparc/),
	     lilo => bool(arch() !~ /sparc|ppc/) && !isLoopback(fsedit::get_root($fstab)),
	     grub => bool(arch() !~ /sparc|ppc/ && availableRamMB() < 800), #- don't use grub if more than 800MB
	     loadlin => bool(arch() !~ /sparc|ppc/) && -e "/initrd/loopfs/lnx4win",
	    );
    unless ($lilo->{methods}) {
	$lilo->{methods} ||= { map { $_ => 1 } grep { $l{$_} } keys %l };
	if ($lilo->{methods}{lilo} && -e "$prefix/boot/boot-graphic.b") {
	    $lilo->{methods}{lilo} = "boot-graphic.b";
	    exists $lilo->{methods}{grub} and $lilo->{methods}{grub} = undef;
	}
    }
}

sub suggest_floppy {
    my ($bootloader) = @_;

    add_entry($bootloader->{entries},
      {
       type => 'other',
       kernel_or_dev => '/dev/fd0',
       label => 'floppy',
       unsafe => 1
      });
}

sub keytable($$) {
    my ($prefix, $f) = @_;
    local $_ = $f;
    if ($_ && !/\.klt$/) {
	$f = "/boot/$_.klt";
	run_program::rooted($prefix, "keytab-lilo.pl", ">", $f, $_) or undef $f;
    }
    $f && -r "$prefix/$f" && $f;
}

sub has_profiles { bool(get_label("office", $b)) }
sub set_profiles {
    my ($b, $want_profiles) = @_;

    my $office = get_label("office", $b);
    if ($want_profiles xor $office) {
	my $e = get_label("linux", $b);
	if ($want_profiles) {
	    push @{$b->{entries}}, { %$e, label => "office", append => "$e->{append} prof=Office" };
	    $e->{append} .= " prof=Home";
	} else {
	    # remove profiles
	    $e->{append} =~ s/\s*prof=\w+//;
	    @{$b->{entries}} = grep { $_ != $office } @{$b->{entries}};
	}
    }

}

sub get_of_dev($$) {
	my ($prefix, $unix_dev) = @_;
	#- don't care much for this - need to run ofpath rooted, and I need the result
	#- In test mode, just run on "/", otherwise you can't get to the /proc files		
	if ($::testing) {
		$prefix = "";
	}
	run_program::rooted_or_die($prefix, "/usr/local/sbin/ofpath $unix_dev", ">", "/tmp/ofpath");
	open(FILE, "$prefix/tmp/ofpath") || die "Can't open $prefix/tmp/ofpath";
	my $of_dev = "";
	local $_ = "";
	while(<FILE>){
		$of_dev = $_;
	}
	chop($of_dev);
	my @del_file = ($prefix . "/tmp/ofpath");
	unlink (@del_file);
	log::l("OF Device: $of_dev");
	$of_dev;
}

sub install_yaboot($$$) {
    my ($prefix, $lilo) = @_;
    $lilo->{prompt} = $lilo->{timeout};

    if ($lilo->{message}) {
	local *F;
	open F, ">$prefix/boot/message" and print F $lilo->{message} or $lilo->{message} = 0;
    }
    {
	local *F;
        local $\ = "\n";
	my $f = "$prefix/etc/yaboot.conf";
	open F, ">$f" or die "cannot create yaboot config file: $f";
	log::l("writing yaboot config to $f");

	print F "#yaboot.conf - generated by DrakX";
    print F "init-message=\"\\n$lilo->{initmsg}\\n\"" if $lilo->{initmsg};

	if ($lilo->{boot}) {
		print F "boot=$lilo->{boot}";
		my $of_dev = get_of_dev($prefix, $lilo->{boot});
	    print F "ofboot=$of_dev";
	} else {
		die "no bootstrap partition defined."
	}
	
	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(delay timeout);
	print F "install=/usr/local/lib/yaboot/yaboot";
	print F "magicboot=/usr/local/lib/yaboot/ofboot";
	$lilo->{$_} and print F $_ foreach qw(enablecdboot enableofboot);
	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(defaultos default);
	print F "nonvram";
	
	foreach (@{$lilo->{entries}}) {

	    if ($_->{type} eq "image") {
			my $of_dev = get_of_dev($prefix, $_->{root});
			print F "$_->{type}=$of_dev,$_->{kernel_or_dev}";
	    	print F "\tlabel=", substr($_->{label}, 0, 15); #- lilo doesn't handle more than 15 char long labels
			print F "\troot=$_->{root}";
			print F "\tinitrd=$_->{initrd}" if $_->{initrd};
			print F "\tappend=\"$_->{append}\"" if $_->{append};
			print F "\tread-write" if $_->{'read-write'};
			print F "\tread-only" if !$_->{'read-write'};
	    } else {
	    	my $of_dev = get_of_dev($prefix, $_->{kernel_or_dev});
			print F "$_->{label}=$of_dev";		
	    }
	}
    }
    log::l("Installing boot loader...");
    $::testing and return;
    run_program::rooted($prefix, "/sbin/ybin", "2>", "/tmp/.error") or die "ybin failed";
    unlink "$prefix/tmp/.error";	
}

sub install_silo($$$) {
    my ($prefix, $silo, $fstab) = @_;
    my $boot = fsedit::get_root($fstab, 'boot')->{device};
    my ($wd, $num) = $boot =~ /^(.*\D)(\d*)$/;

    #- setup boot promvars for.
    require c;
    if ($boot =~ /^md/) {
	#- get all mbr devices according to /boot are listed,
	#- then join all zero based partition translated to prom with ';'.
	#- keep bootdev with the first of above.
	log::l("/boot is present on raid partition which is not currently supported for promvars");
    } else {
	if (!$silo->{use_partition}) {
	    foreach (@$fstab) {
		if (!$_->{start} && $_->{device} =~ /$wd/) {
		    $boot = $_->{device};
		    log::l("found a zero based partition in $wd as $boot");
		    last;
		}
	    }
	}
	$silo->{bootalias} = c::disk2PromPath($boot);
	$silo->{bootdev} = $silo->{bootalias};
        log::l("preparing promvars for device=$boot");
    }
    c::hasAliases() or log::l("clearing promvars alias as non supported"), $silo->{bootalias} = '';

    if ($silo->{message}) {
	local *F;
	open F, ">$prefix/boot/message" and print F $silo->{message} or $silo->{message} = 0;
    }
    {
	local *F;
        local $\ = "\n";
	my $f = "$prefix/boot/silo.conf"; #- always write the silo.conf file in /boot ...
	symlinkf "../boot/silo.conf", "$prefix/etc/silo.conf"; #- ... and make a symlink from /etc.
	open F, ">$f" or die "cannot create silo config file: $f";
	log::l("writing silo config to $f");

	$silo->{$_} and print F "$_=$silo->{$_}" foreach qw(partition root default append);
	$silo->{$_} and print F $_ foreach qw(restricted);
	#- print F "password=", $silo->{password} if $silo->{restricted} && $silo->{password}; #- done by msec
	print F "timeout=", round(10 * $silo->{timeout}) if $silo->{timeout};
	print F "message=$silo->{boot}/message" if $silo->{message};

	foreach (@{$silo->{entries}}) {#my ($v, $e) = each %{$silo->{entries}}) {
	    my $type = "$_->{type}=$_->{kernel_or_dev}"; $type =~ s|/boot|$silo->{boot}|;
	    print F $type;
	    print F "\tlabel=$_->{label}";

	    if ($_->{type} eq "image") {
		my $initrd = $_->{initrd}; $initrd =~ s|/boot|$silo->{boot}|;
		print F "\tpartition=$_->{partition}" if $_->{partition};
		print F "\troot=$_->{root}" if $_->{root};
		print F "\tinitrd=$initrd" if $_->{initrd};
		print F "\tappend=\"$1\"" if $_->{append} =~ /^\s*"?(.*?)"?\s*$/;
		print F "\tread-write" if $_->{'read-write'};
		print F "\tread-only" if !$_->{'read-write'};
	    }
	}
    }
    log::l("Installing boot loader...");
    $::testing and return;
    run_program::rooted($prefix, "silo", "2>", "/tmp/.error", $silo->{use_partition} ? ("-t") : ()) or 
        run_program::rooted($prefix, "silo", "2>", "/tmp/.error", "-p", "2", $silo->{use_partition} ? ("-t") : ()) or 
	    die "silo failed";
    unlink "$prefix/tmp/.error";

    #- try writing in the prom.
    log::l("setting promvars alias=$silo->{bootalias} bootdev=$silo->{bootdev}");
    require c;
    c::setPromVars($silo->{bootalias}, $silo->{bootdev});
}

sub install_lilo($$) {
    my ($prefix, $lilo) = @_;
    $lilo->{prompt} = $lilo->{timeout};

    if ($lilo->{message}) {
	local *F;
	open F, ">$prefix/boot/message" and print F $lilo->{message} or $lilo->{message} = 0;
    }
    {
	local *F;
        local $\ = "\n";
	my $f = "$prefix/etc/lilo.conf";
	open F, ">$f" or die "cannot create lilo config file: $f";
	log::l("writing lilo config to $f");

	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(boot map install vga default append keytable disk);
	$lilo->{$_} and print F $_ foreach qw(linear lba32 compact prompt restricted);
	#- print F "password=", $lilo->{password} if $lilo->{restricted} && $lilo->{password}; #- done by msec
	print F "timeout=", round(10 * $lilo->{timeout}) if $lilo->{timeout};
	if ($lilo->{message}) {
	    if (-e "$prefix/boot/$lilo->{methods}{lilo}" && $lilo->{methods}{lilo} eq "boot-graphic.b") {
		print F "message=/boot/message-graphic";
	    } else {
		print F "message=/boot/message";
	    }
	}
	print F "menu-scheme=wb:bw:wb:bw";

	foreach (@{$lilo->{entries}}) {
	    print F "$_->{type}=$_->{kernel_or_dev}";
	    print F "\tlabel=", substr($_->{label}, 0, 15); #- lilo doesn't handle more than 15 char long labels

	    if ($_->{type} eq "image") {
		print F "\troot=$_->{root}";
		print F "\tinitrd=$_->{initrd}" if $_->{initrd};
		print F "\tappend=\"$_->{append}\"" if $_->{append};
		print F "\tvga=$_->{vga}" if $_->{vga};
		print F "\tread-write" if $_->{'read-write'};
		print F "\tread-only" if !$_->{'read-write'};
	    } else {
		print F "\ttable=$_->{table}" if $_->{table};
		print F "\tunsafe" if $_->{unsafe} && !$_->{table};
		
		#- boot off the second drive, so reverse the BIOS maps
		$_->{mapdrive} ||= { '0x80' => '0x81', '0x81' => '0x80' } 
		  if $_->{table} && $lilo->{boot} !~ /$_->{table}/;

		while (my ($from, $to) = each %{$_->{mapdrive} || {}}) {
		    print F "\tmap-drive=$from";
		    print F "\t   to=$to";
		}
	    }
	}
    }
    #- try to use a specific stage2 if defined and present.
    -e "$prefix/boot/$lilo->{methods}{lilo}" and symlinkf $lilo->{methods}{lilo}, "$prefix/boot/boot.b";
    log::l("stage2 of lilo used is " . readlink "$prefix/boot/boot.b");
    log::l("Installing boot loader...");
    $::testing and return;
    run_program::rooted_or_die($prefix, "lilo", "2>", "/tmp/.error");
    unlink "$prefix/tmp/.error";
}

sub dev2bios {
    my ($hds, $where) = @_;
    my @dev = map { $_->{device} } @$hds;
    member($where, @dev) or ($where) = @dev; #- if not on mbr, 

    s/h(d[e-g])/x$1/ foreach $where, @dev; #- emulates ultra66 as xd_

    my $start = substr($where, 0, 2);

    my $translate = sub {
	$_ eq $where ? "aaa" : #- if exact match, value it first
	  /^$start(.*)/ ? "ad$1" : #- if same class (ide/scsi/ultra66), value it before other classes
	    $_;
    };
    @dev = map { $_->[0] }
           sort { $a->[1] cmp $b->[1] }
	   map { [ $_, &$translate ] } @dev;

    s/x(d.)/h$1/ foreach @dev; #- switch back;

    (map_index { $_ => "fd$::i" } detect_devices::floppies()),
    (map_index { $_ => "hd$::i" } @dev);
}

sub dev2grub {
    my ($dev, $dev2bios) = @_;
    $dev =~ m|^(/dev/)?(...)(.*)$| or die "dev2grub (bad device $dev), caller is " . join(":", caller());
    my $grub = $dev2bios->{$2} or die "dev2grub ($2)";
    "($grub" . ($3 && "," . ($3 - 1)) . ")";
}

sub install_grub {
    my ($prefix, $lilo, $fstab, $hds) = @_;
    my %dev2bios = dev2bios($hds, $lilo->{boot});

    {
	my %bios2dev = reverse %dev2bios;
	output "$prefix/boot/grub/device.map", 
	  join '', map { "($_) /dev/$bios2dev{$_}\n" } sort keys %bios2dev;
    }
    my $file2grub = sub {	
	my $file = expand_symlinks "$prefix$_[0]";
	if (!isReiserfs(fsedit::get_root($fstab, 'boot'))) { #- grub in reiserfs doesn't handle symlinks.
	    if (my $l = readlink "$prefix$_[0]") {
		$l =~ m|/| or $file =~ s/\Q$l/basename $_[0]/e; #- keep simple end symlinks
	    }
	}
	unless ($file =~ s/^$prefix//) {
	    my ($fs) = grep { loopback::carryRootLoopback($_) } @$fstab or die;
	    log::l("found $fs->{mntpoint}");
	    $file =~ s|/initrd/loopfs|$fs->{mntpoint}|;
	}
	my ($fs);
	foreach (@$fstab) {
	    my $m = $_->{mntpoint};
	    $fs = $_ if 
	      $file =~ /^$m/ && 
	      (!$fs || length $fs->{mntpoint} < length $m);
	}
	$fs or die "file2grub not found $file";
	$file =~ s|$fs->{mntpoint}/?|/|;
	dev2grub($fs->{device}, \%dev2bios) . $file;
    };
    {
	local *F;
        local $\ = "\n";
	my $f = "$prefix/boot/grub/menu.lst";
	open F, ">$f" or die "cannot create grub config file: $f";
	log::l("writing grub config to $f");

	$lilo->{$_} and print F "$_ $lilo->{$_}" foreach qw(timeout);

	print F "color black/cyan yellow/cyan";
	print F "i18n ", $file2grub->("/boot/grub/messages");
	print F "keytable ", $file2grub->($lilo->{keytable}) if $lilo->{keytable};
	print F "altconfigfile ", $file2grub->(my $once = "/boot/grub/menu.once");
	output "$prefix$once", " " x 100;

	map_index {
	    print F "default $::i" if $_->{label} eq $lilo->{default};
	} @{$lilo->{entries}};

	foreach (@{$lilo->{entries}}) {
	    print F "\ntitle $_->{label}";

	    if ($_->{type} eq "image") {
		my $vga = $_->{vga} || $lilo->{vga};
		printf F "kernel %s root=%s %s%s%s\n",
		  $file2grub->($_->{kernel_or_dev}),
		  $_->{root} =~ /loop7/ ? "707" : $_->{root}, #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
		  $_->{append},
		  $_->{'read-write'} && " rw",
		  $vga && $vga ne "normal" && " vga=$vga";
		print F "initrd ", $file2grub->($_->{initrd}) if $_->{initrd};
	    } else {
		print F "root ", dev2grub($_->{kernel_or_dev}, \%dev2bios);
		if ($_->{kernel_or_dev} !~ /fd/) {
		    #- boot off the second drive, so reverse the BIOS maps
		    $_->{mapdrive} ||= { '0x80' => '0x81', '0x81' => '0x80' } 
		      if $_->{table} && $lilo->{boot} !~ /$_->{table}/;
	    
		    map_each { print F "map ($::b) ($::a)" } %{$_->{mapdrive} || {}};

		    print F "makeactive";
		}
		print F "chainloader +1";
	    }
	}
    }
    my $hd = fsedit::get_root($fstab, 'boot')->{rootDevice};

    my $dev = dev2grub($lilo->{boot}, \%dev2bios);
    my ($s1, $s2, $m) = map { $file2grub->("/boot/grub/$_") } qw(stage1 stage2 menu.lst);
    my $f = "/boot/grub/install.sh";
    output "$prefix$f",
"grub --device-map=/boot/grub/device.map --batch <<EOF
install $s1 d $dev $s2 p $m
quit
EOF
";

     output "$prefix/boot/grub/messages", map { substr(translate($_) . "\n", 0, 78) } ( #- ensure the translated messages are not too big the hard way
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
__("Welcome to GRUB the operating system chooser!"),
__("Use the %c and %c keys for selecting which entry is highlighted."),
__("Press enter to boot the selected OS, \'e\' to edit the"),
__("commands before booting, or \'c\' for a command-line."),
__("The highlighted entry will be booted automatically in %d seconds."),
);
   
    my $e = "$prefix/boot/.enough_space";
    output $e, 1; -s $e or die _("not enough room in /boot");
    unlink $e;

    log::l("Installing boot loader...");
    $::testing and return;
    symlink "$prefix/boot", "/boot";
    run_program::run("sh", $f) or die "grub installation failed";
    unlink "$prefix/tmp/.error.grub", "/boot";
}

sub lnx4win_file { 
    my $lilo = shift;
    map { local $_ = $_; s,/,\\,g; "$lilo->{boot_drive}:\\lnx4win$_" } @_;
}

sub loadlin_cmd {
    my ($prefix, $lilo) = @_;
    my $e = get_label("linux", $lilo) || first(grep { $_->{type} eq "image" } @{$lilo->{entries}});

    commands::cp("$prefix$e->{kernel_or_dev}", "$prefix/boot/vmlinuz") unless -e "$prefix/boot/vmlinuz";
    commands::cp("$prefix$e->{initrd}", "$prefix/boot/initrd.img") unless -e "$prefix/boot/initrd.img";

    $e->{label}, sprintf"%s %s initrd=%s root=%s $e->{append}", 
      lnx4win_file($lilo, "/loadlin.exe", "/boot/vmlinuz", "/boot/initrd.img"),
	$e->{root} =~ /loop7/ ? "0707" : $e->{root}; #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
}

sub install_loadlin {
    my ($prefix, $lilo, $fstab) = @_;

    my $boot;
    ($boot) = grep { $lilo->{boot} eq "/dev/$_->{device}" } @$fstab;
    ($boot) = grep { loopback::carryRootLoopback($_) } @$fstab unless $boot && $boot->{device_windobe};
    ($boot) = grep { isFat($_) } @$fstab unless $boot && $boot->{device_windobe};
    log::l("loadlin device is $boot->{device} (windobe $boot->{device_windobe})");
    $lilo->{boot_drive} = $boot->{device_windobe};

    my ($winpart) = grep { $_->{device_windobe} eq 'C' } @$fstab;
    log::l("winpart is $winpart->{device}");
    my $winhandle = any::inspect($winpart, $prefix, 'rw');
    my $windrive = $winhandle->{dir};
    log::l("windrive is $windrive");

    my ($label, $cmd) = loadlin_cmd($prefix, $lilo);

    #install_loadlin_config_sys($lilo, $windrive, $label, $cmd);
    #install_loadlin_desktop($lilo, $windrive);

    output "/initrd/loopfs/lnx4win/linux.bat", unix2dos(
'@echo off
echo Linux Mandrake
smartdrv /C
' . "$cmd\n");

}

sub install_loadlin_config_sys {
    my ($lilo, $windrive, $label, $cmd) = @_;

    my $config_sys = "$windrive/config.sys";
    local $_ = cat_($config_sys);
    output "$windrive/config.mdk", $_ if $_;
    
    my $timeout = $lilo->{timeout} || 1;

    $_ = "
[Menu]
menuitem=Windows
menudefault=Windows,$timeout

[Windows]
" . $_ if !/^\Q[Menu]/m;

    #- remove existing entry
    s/^menuitem=$label\s*//mi;    
    s/\n\[$label\].*?(\n\[|$)/$1/si;

    #- add entry
    s/(.*\nmenuitem=[^\n]*)/$1\nmenuitem=$label/s;

    $_ .= "
[$label]
shell=$cmd
";
    output $config_sys, unix2dos($_);
}

sub install_loadlin_desktop {
    my ($lilo, $windrive) = @_;
    my $windir = lc(cat_("$windrive/msdos.sys") =~ /^WinDir=.:\\(\S+)/m ? $1 : "windows");

#-PO: "Desktop" and "Start Menu" are the name of the directories found in c:\windows 
    foreach (__("Desktop"), __("Start Menu")) {
        my $d = "$windrive/$windir/" . translate($_);
        -d $d or $d = "$windrive/$windir/$_";
        -d $d or log::l("can't find windows $d directory"), next;
        output "$d/Linux4Win.url", unix2dos(sprintf 
q([InternetShortcut]
URL=file:\lnx4win\lnx4win.exe
WorkingDirectory=%s
IconFile=%s
IconIndex=0
), lnx4win_file($lilo, "/", "/lnx4win.ico"));
    }
}


sub install {
    my ($prefix, $lilo, $fstab, $hds) = @_;

    {
	my $f = "$prefix/etc/sysconfig/system";
	setVarsInSh($f, add2hash_({ CLEAN_TMP => $lilo->{CLEAN_TMP} }, { getVarsFromSh($f) }));
    }
    $lilo->{keytable} = keytable($prefix, $lilo->{keytable});

    my %l = grep_each { $::b } %{$lilo->{methods}};
    my @rcs = map {
	my $f = $bootloader::{"install_$_"} or die "unknown bootloader method $_";
	eval { $f->(@_) };
	$@;
    } reverse sort keys %l; #- reverse sort for having grub installed after lilo if both are there.
    
    return if grep { !$_ } @rcs; #- at least one worked?
    die first(map { $_ } @rcs);
}

#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #
