package bootloader; # $Id$

use diagnostics;
use strict;
use vars qw(%vga_modes);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table qw(:types);
use log;
use any;
use fsedit;
use devices;
use loopback;
use detect_devices;
use partition_table_raw;
use run_program;
use modules;


%vga_modes = (
'ask' => "Ask at boot",
'normal' => "Normal",
'0x0f01' => "80x50",
'0x0f02' => "80x43",
'0x0f03' => "80x28",
'0x0f04' => "80x30",
'0x0f05' => "80x34",
'0x0f06' => "80x60",
'0x0122' => "100x30",
 785 => "640x480 in 16 bits (FrameBuffer only)",
 788 => "800x600 in 16 bits (FrameBuffer only)",
 791 => "1024x768 in 16 bits (FrameBuffer only)",
 794 => "1280x1024 in 16 bits (FrameBuffer only)",
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
    run_program::rooted($prefix, "mkinitrd", "-v", "-f", $initrdImage, "--ifneeded", $kernelVersion) or unlink("$prefix/$initrdImage");

    loopback::save_boot($loop_boot);

    -e "$prefix/$initrdImage" or die "mkinitrd failed";
}

sub mkbootdisk($$$;$) {
    my ($prefix, $kernelVersion, $dev, $append) = @_;

    modules::load_multi(arch() =~ /sparc/ ? 'romfs' : (), 'loop');
    my @l = qw(mkbootdisk --noprompt); 
    push @l, "--appendargs", $append if $append;
    eval { modules::load('vfat') };
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

sub suggest_onmbr {
    my ($hds) = @_;
    
    my $type = partition_table_raw::typeOfMBR($hds->[0]{device});
    !$type || member($type, qw(dos dummy lilo grub empty)), !$type;
}

sub compare_entries ($$) {
    my ($a, $b) = @_;
    my %entries;

    @entries{keys %$a, keys %$b} = ();
    $a->{$_} eq $b->{$_} and delete $entries{$_} foreach keys %entries;
    scalar keys %entries;
}

sub add_entry($$) {
    my ($entries, $v) = @_;
    my (%usedold, $freeold);

    do { $usedold{$1 || 0} = 1 if $_->{label} =~ /^old([^_]*)_/ } foreach @$entries;
    foreach (0..scalar keys %usedold) { exists $usedold{$_} or $freeold = $_ || '', last }

    foreach (@$entries) {
	if ($_->{label} eq $v->{label}) {
	    compare_entries($_, $v) or return; #- avoid inserting it twice as another entry already exists !
	    $_->{label} = "old${freeold}_$_->{label}";
	}
    }
    push @$entries, $v;
}

sub add_kernel {
    my ($prefix, $lilo, $version, $ext, $root, $v) = @_;

    #- new versions of yaboot don't handle symlinks
    my $ppcext = $ext;
    if (arch() =~ /ppc/) {
	$ext = "-$version";
    }

    log::l("adding vmlinuz$ext as vmlinuz-$version");
    -e "$prefix/boot/vmlinuz-$version" or log::l("unable to find kernel image $prefix/boot/vmlinuz-$version"), return;
    my $image = "/boot/vmlinuz" . ($ext ne "-$version" &&
				   symlinkf("vmlinuz-$version", "$prefix/boot/vmlinuz$ext") ? $ext : "-$version");
    my $initrd = eval { 
	mkinitrd($prefix, $version, "/boot/initrd-$version.img");
	"/boot/initrd" . ($ext ne "-$version" &&
			  symlinkf("initrd-$version.img", "$prefix/boot/initrd$ext.img") ? $ext : "-$version") . ".img";
    };
    my $label = $ext =~ /-(default)/ ? $1 : "linux$ext";

    #- more yaboot concessions - PPC
    if (arch() =~ /ppc/) {
	$label = $ppcext =~ /-(default)/ ? $1 : "linux$ppcext";
    }

    add2hash($v,
	     {
	      type => 'image',
	      root => "/dev/$root",
	      label => $label,
	      kernel_or_dev => $image,
	      initrd => $initrd,
	      append => $lilo->{perImageAppend},
	     });
    add_entry($lilo->{entries}, $v);
    $v;
}

sub unpack_append {
    my ($s) = @_;
    my @l = split(' ', $s);
    [ grep { !/=/ } @l ], [ map { if_(/(.*?)=(.*)/, [$1, $2]) } @l ];
}
sub pack_append {
    my ($simple, $dict) = @_;
    join(' ', @$simple, map { "$_->[0]=$_->[1]" } @$dict);
}

sub append__mem_is_memsize { $_[0] =~ /^\d+[kM]?$/i }

sub get_append {
    my ($b, $key) = @_;
    my (undef, $dict) = unpack_append($b->{perImageAppend});
    my @l = map { $_->[1] } grep { $_->[0] eq $key } @$dict;

    #- suppose we want the memsize
    @l = grep { append__mem_is_memsize($_) } @l if $key eq 'mem';

    log::l("more than one $key in $b->{perImageAppend}") if @l > 1;
    $l[0];
}
sub add_append {
    my ($b, $key, $val) = @_;

    foreach (\$b->{perImageAppend}, map { \$_->{append} } @{$b->{entries}}) {
	my ($simple, $dict) = unpack_append($$_);
	@$dict = grep { $_->[0] ne $key || $key eq 'mem' && append__mem_is_memsize($_->[1]) != append__mem_is_memsize($val) } @$dict;
	push @$dict, [ $key, $val ] if $val;
	$$_ = pack_append($simple, $dict);
	log::l("add_append: $$_");
    }
}
sub may_append {
    my ($b, $key, $val) = @_;
    add_append($b, $key, $val) if !get_append($b, $key);
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

sub get_kernels_and_labels {
    my ($prefix) = @_;
    my $dir = "$prefix/boot";
    my @l = grep { /^vmlinuz-/ } all($dir);
    my @kernels = grep { ! -l "$dir/$_" } @l;

    my @preferred = ('', 'secure', 'enterprise', 'smp');
    my %weights = map_index { $_ => $::i } @preferred;
    
    require pkgs;
    @kernels = 
      sort { pkgs::versionCompare($b->[1], $a->[1]) || $weights{$a->[2]} <=> $weights{$b->[2]} } 
      map {
	  if (my ($version, $ext) = /vmlinuz-((?:[\-.\d]*(?:mdk)?)*)(.*)/) {
	      [ "$version$ext", $version, $ext ];
	  } else {
	      log::l("non recognised kernel name $_");
	      ();
	  }
      } @kernels;

    my %majors;
    foreach (@kernels) {
	push @{$majors{$1}}, $_ if $_->[1] =~ /^(2\.\d+)/
    }
    while (my ($major, $l) = each %majors) {
	$l->[0][1] = $major if @$l == 1;
    }

    my %labels;
    foreach (@kernels) {
	my ($complete_version, $version, $ext) = @$_;
	my $label = '';
	if (exists $labels{$label}) {
	    $label = "-$ext";
	    if (!$ext || $labels{$label}) {
		$label = "-$version$ext";
	    }
	}
	$labels{$label} = $complete_version;
    }
    %labels;
}

sub suggest {
    my ($prefix, $lilo, $hds, $fstab, $vga_fb) = @_;
    my $root_part = fsedit::get_root($fstab);
    my $root = isLoopback($root_part) ? "loop7" : $root_part->{device};
    my $boot = fsedit::get_root($fstab, 'boot')->{device};
    my $partition = first($boot =~ /\D*(\d*)/);
    #- PPC xfs module requires enlarged initrd
    my $xfsroot = isThisFs("xfs", $root_part);

    require c; c::initSilo() if arch() =~ /sparc/;

    my ($onmbr, $unsafe) = $lilo->{crushMbr} ? (1, 0) : suggest_onmbr($hds);
    add2hash_($lilo, arch() =~ /sparc/ ?
	{
	 entries => [],
	 timeout => 10,
	 use_partition => 0, #- we should almost always have a whole disk partition.
	 root          => "/dev/$root",
	 partition     => $partition || 1,
	 boot          => $root eq $boot && "/boot", #- this helps for getting default partition for silo.
	} : arch =~ /ppc/ ?
	{
	 defaultos => "linux",
	 entries => [],
	 initmsg => "Welcome to Mandrake Linux!",
	 delay => 30,	#- OpenFirmware delay
	 timeout => 50,
	 enableofboot => 1,
	 enablecdboot => 1,
	 useboot => $boot,
	 xfsroot => $xfsroot,
	} :
	{
	 bootUnsafe => $unsafe,
	 entries => [],
	 timeout => $onmbr && 10,
	   if_(arch() !~ /ia64/,
	 lba32 => 1,
	 boot => "/dev/" . ($onmbr ? $hds->[0]{device} : fsedit::get_root($fstab, 'boot')->{device}),
	 map => "/boot/map",
	 install => "/boot/boot.b",
         ),
	});

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

    add2hash_($lilo, { memsize => $1 }) if cat_("/proc/cmdline") =~ /\bmem=(\d+[KkMm]?)(?:\s.*)?$/;
    if (my ($s, $port, $speed) = cat_("/proc/cmdline") =~ /console=(ttyS(\d),(\d+)\S*)/) {
	log::l("serial console $s $port $speed");
	add_append($lilo, 'console' => $s);
	any::set_login_serial_console($prefix, $port, $speed);
    }

    my %labels = get_kernels_and_labels($prefix);
    $labels{''} or die "no kernel installed";

    while (my ($ext, $version) = each %labels) {
	my $entry = add_kernel($prefix, $lilo, $version, $ext, $root,
	       {
		if_($vga_fb && $ext eq '', vga => $vga_fb), #- using framebuffer
	       });
	$entry->{append} .= " quiet" if $vga_fb && $version !~ /smp|enterprise/;

	if ($vga_fb && $ext eq '') {
	    add_kernel($prefix, $lilo, $version, $ext, $root, { label => 'linux-nonfb' });
	}
    }
    my $failsafe = add_kernel($prefix, $lilo, $labels{''}, '', $root, { label => 'failsafe' });
    $failsafe->{append} .= " failsafe";

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
    } elsif (arch() !~ /ia64/) {
	#- search for dos (or windows) boot partition. Don't look in extended partitions!
	my %nbs;
	foreach (@$hds) {
	    foreach (@{$_->{primary}{normal}}) {
		my $label = isNT($_) ? 'NT' : isDos($_) ? 'dos' : 'windows';
		add_entry($lilo->{entries},
			  {
			   type => 'other',
			   kernel_or_dev => "/dev/$_->{device}",
			   label => $label . ($nbs{$label}++ ? $nbs{$label} : ''),
			     if_($_->{device} =~ /[1-4]$/, 
			   table => "/dev/$_->{rootDevice}"
				),
			   unsafe => 1
			  }) if isNT($_) || isFat($_) && isFat({ type => fsedit::typeOfPart($_->{device}) });
	    }
	}
    }
    foreach ('secure', 'enterprise', 'smp') {
	if (get_label("linux-$_", $lilo)) {
	    $lilo->{default} ||= "linux-$_";
	    last;
	}
    }
    $lilo->{default} ||= "linux";

    my %l = (
	     yaboot => to_bool(arch() =~ /ppc/),
	     silo => to_bool(arch() =~ /sparc/),
	     lilo => to_bool(arch() !~ /sparc|ppc/) && !isLoopback(fsedit::get_root($fstab)),
	     grub => to_bool(arch() !~ /sparc|ppc/ && !isRAID(fsedit::get_root($fstab))),
	     loadlin => to_bool(arch() !~ /sparc|ppc/) && -e "/initrd/loopfs/lnx4win",
	    );
    unless ($lilo->{methods}) {
	$lilo->{methods} ||= { map { $_ => 1 } grep { $l{$_} } keys %l };
	if ($lilo->{methods}{lilo} && -e "$prefix/boot/lilo-graphic") {
	    $lilo->{methods}{lilo} = "lilo-graphic";
	    exists $lilo->{methods}{grub} and $lilo->{methods}{grub} = undef;
	}
    }
}

sub suggest_floppy {
    my ($bootloader) = @_;

    my $floppy = detect_devices::floppy() or return;
    $floppy eq 'fd0' or log::l("suggest_floppy: not adding $floppy"), return;

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

sub has_profiles { to_bool(get_label("office", $b)) }
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
	while (<FILE>){
		$of_dev = $_;
	}
	chop($of_dev);
	my @del_file = ($prefix . "/tmp/ofpath");
	unlink (@del_file);
	log::l("OF Device: $of_dev");
	$of_dev;
}

sub install_yaboot($$$) {
    my ($prefix, $lilo, $fstab, $hds) = @_;
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
	my $boot = "/dev/" . $lilo->{useboot} if $lilo->{useboot};
		
	foreach (@{$lilo->{entries}}) {

	    if ($_->{type} eq "image") {
		my $of_dev = '';
		if ($boot !~ /$_->{root}/) {
		    $of_dev = get_of_dev($prefix, $boot);
		    print F "$_->{type}=$of_dev," . substr($_->{kernel_or_dev}, 5);
		} else {
		    $of_dev = get_of_dev($prefix, $_->{root});    			
		    print F "$_->{type}=$of_dev,$_->{kernel_or_dev}";
		}
		print F "\tlabel=", substr($_->{label}, 0, 15); #- lilo doesn't handle more than 15 char long labels
		print F "\troot=$_->{root}";
		if ($boot !~ /$_->{root}/) {
		    print F "\tinitrd=$of_dev," . substr($_->{initrd}, 5) if $_->{initrd};
		} else {
		    print F "\tinitrd=$of_dev,$_->{initrd}" if $_->{initrd};
		}
		#- xfs module on PPC requires larger initrd - say 6MB?
		print F "\tinitrd-size=6144" if $lilo->{xfsroot};
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
    my $f = "$prefix/tmp/of_boot_dev";
    my $of_dev = get_of_dev($prefix, $lilo->{boot});
    output($f, "$of_dev\n");  
    $::testing and return;
    if (defined $install_steps_interactive::new_bootstrap) {
	run_program::run("hformat", "$lilo->{boot}") or die "hformat failed";
    }	
    run_program::rooted_or_die($prefix, "/sbin/ybin", "2>", "/tmp/.error");
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
	print F "password=", $silo->{password} if $silo->{restricted} && $silo->{password}; #- also done by msec
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
        run_program::rooted_or_die($prefix, "silo", "2>", "/tmp/.error", "-p", "2", $silo->{use_partition} ? ("-t") : ());
    unlink "$prefix/tmp/.error";

    #- try writing in the prom.
    log::l("setting promvars alias=$silo->{bootalias} bootdev=$silo->{bootdev}");
    require c;
    c::setPromVars($silo->{bootalias}, $silo->{bootdev});
}

sub make_label_lilo_compatible {
    my ($label) = @_; 
    $label = substr($label, 0, 15); #- lilo doesn't handle more than 15 char long labels
    $label =~ s/\s/_/g; #- lilo doesn't like spaces
    $label;
}

sub write_lilo_conf {
    my ($prefix, $lilo, $fstab, $hds) = @_;
    $lilo->{prompt} = $lilo->{timeout};

    delete $lilo->{linear} if $lilo->{lba32};

    my $file2fullname = sub {
	my ($file) = @_;
	if (arch() =~ /ia64/) {
	    (my $part, $file) = fsedit::file2part($prefix, $fstab, $file);
	    my %hds = map_index { $_ => "hd$::i" } map { $_->{device} } 
	      sort { isFat($b) <=> isFat($a) || $a->{device} cmp $b->{device} } fsedit::get_fstab(@$hds);
	    %hds->{$part->{device}} . ":" . $file;
	} else {
	    $file
	}
    };

    if ($lilo->{message}) {
 	local *F;
	-d "$prefix/boot/lilo-menu" and open F, ">$prefix/boot/lilo-menu/message" and print F $lilo->{message};
	-d "$prefix/boot/lilo-text" and open F, ">$prefix/boot/lilo-text/message" and print F $lilo->{message};
	-d "$prefix/boot/lilo-graphic" || -d "$prefix/boot/lilo-menu" || -d "$prefix/boot/lilo-text" or
	  open F, ">$prefix/boot/message" and print F $lilo->{message}; #- fallback in case of another lilo.
    }
    foreach ($lilo->{methods}{lilo}, "lilo-menu", "lilo-graphic", "lilo-text") {
	if (-e "$prefix/boot/$_/boot.b" && -e "$prefix/boot/$_/message") {
	    symlinkf $_, "$prefix/boot/lilo";
	    symlinkf "lilo/boot.b", "$prefix/boot/boot.b";
	    symlinkf "lilo/message", "$prefix/boot/message";
	    log::l("stage2 of lilo used is " . readlink "$prefix/boot/lilo");
	    last;
	}
    }
	if (arch() !~ /ia64/) {
		-e "$prefix/boot/boot.b" && -e "$prefix/boot/message" or die "unable to get right lilo configuration in $prefix/boot";
	}

    {
	local *F;
        local $\ = "\n";
	my $f = arch() =~ /ia64/ ? "$prefix/boot/efi/elilo.conf" : "$prefix/etc/lilo.conf";

	open F, ">$f" or die "cannot create lilo config file: $f";
	log::l("writing lilo config to $f");

	local $lilo->{default} = make_label_lilo_compatible($lilo->{default});
	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(boot map install vga default append keytable);
	$lilo->{$_} and print F $_ foreach qw(linear lba32 compact prompt restricted);
 	print F "password=", $lilo->{password} if $lilo->{restricted} && $lilo->{password}; #- also done by msec
	print F "timeout=", round(10 * $lilo->{timeout}) if $lilo->{timeout};
	print F "serial=", $1 if get_append($lilo, 'console') =~ /ttyS(.*)/;

	my $dev = $hds->[0]{device};
	my %bios2dev = map_index { $::i => $_ } dev2bios($hds, $lilo->{boot});
	my %dev2bios = reverse %bios2dev;
	my %done;
	if ($dev2bios{$dev}) {
	    print  F "disk=/dev/$bios2dev{0} bios=0x80";
	    printf F "disk=/dev/$dev bios=0x%x\n", 0x80 + $dev2bios{$dev};
	    $done{0} = $done{$dev2bios{$dev}} = 1;
	}
	foreach (0 .. 3) {
	    my ($letter) = $bios2dev{$_} =~ /hd([^ac])/; #- at least hda and hdc are handled correctly :-/
	    next if $done{$_} || !$letter;
	    next if 
	      $_ > 0 #- always print if first disk is hdb, hdd, hde...
		&& $bios2dev{$_ - 1} eq "hd" . chr(ord($letter) - 1);
		  #- no need to help lilo with hdb (resp. hdd, hdf...)
	    $done{$_} = 1;
	    printf F "disk=/dev/$bios2dev{1} bios=0x%x\n", 0x80 + $_;
	}

	print F "message=/boot/message" if (arch() !~ /ia64/);
	print F "menu-scheme=wb:bw:wb:bw" if (arch() !~ /ia64/);

	foreach (@{$lilo->{entries}}) {
	    print F "$_->{type}=", $file2fullname->($_->{kernel_or_dev});
	    print F "\tlabel=", make_label_lilo_compatible($_->{label});

	    if ($_->{type} eq "image") {		
		print F "\troot=$_->{root}";
		print F "\tinitrd=", $file2fullname->($_->{initrd}) if $_->{initrd};
		print F "\tappend=\"$_->{append}\"" if $_->{append};
		print F "\tvga=$_->{vga}" if $_->{vga};
		print F "\tread-write" if $_->{'read-write'};
		print F "\tread-only" if !$_->{'read-write'};
	    } else {
		print F "\ttable=$_->{table}" if $_->{table};
		print F "\tunsafe" if $_->{unsafe} && !$_->{table};
		
		if (my ($dev) = $_->{table} =~ m|/dev/(.*)|) {
		    if ($dev2bios{$dev}) {
			#- boot off the nth drive, so reverse the BIOS maps
			my $nb = sprintf("0x%x", 0x80 + $dev2bios{$dev});
			$_->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		    }
		}
		while (my ($from, $to) = each %{$_->{mapdrive} || {}}) {
		    print F "\tmap-drive=$from";
		    print F "\t   to=$to";
		}
	    }
	}
    }
}

sub install_lilo {
    my ($prefix, $lilo, $fstab, $hds) = @_;

    write_lilo_conf($prefix, $lilo, $fstab, $hds);

    log::l("Installing boot loader...");
    $::testing and return;
    run_program::rooted_or_die($prefix, "lilo", "2>", "/tmp/.error") if (arch() !~ /ia64/);
    unlink "$prefix/tmp/.error";
}

sub dev2bios {
    my ($hds, $where) = @_;
    $where =~ s|/dev/||;
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

    @dev;
}

sub dev2grub {
    my ($dev, $dev2bios) = @_;
    $dev =~ m|^(/dev/)?(...)(.*)$| or die "dev2grub (bad device $dev), caller is " . join(":", caller());
    my $grub = $dev2bios->{$2} or die "dev2grub ($2)";
    "($grub" . ($3 && "," . ($3 - 1)) . ")";
}

sub write_grub_config {
    my ($prefix, $lilo, $fstab, $hds) = @_;
    my %dev2bios = (
      (map_index { $_ => "fd$::i" } detect_devices::floppies_dev()),
      (map_index { $_ => "hd$::i" } dev2bios($hds, $lilo->{boot})),
    );

    {
	my %bios2dev = reverse %dev2bios;
	output "$prefix/boot/grub/device.map", 
	  join '', map { "($_) /dev/$bios2dev{$_}\n" } sort keys %bios2dev;
    }
    my $bootIsReiser = isThisFs("reiserfs", fsedit::get_root($fstab, 'boot'));
    my $file2grub = sub {
	my ($part, $file) = fsedit::file2part($prefix, $fstab, $_[0], 'keep_simple_symlinks');
	dev2grub($part->{device}, \%dev2bios) . $file;
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
	print F "serial --unit=$1 --speed=$2\nterminal serial console" if get_append($lilo, 'console') =~ /ttyS(\d),(\d+)/;

	#- since we use notail in reiserfs, altconfigfile is broken :-(
	unless ($bootIsReiser) {
	    print F "altconfigfile ", $file2grub->(my $once = "/boot/grub/menu.once");
	    output "$prefix$once", " " x 100;
	}

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
#-PO: and keep them smaller than 79 chars long
__("Welcome to GRUB the operating system chooser!"),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
__("Use the %c and %c keys for selecting which entry is highlighted."),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
__("Press enter to boot the selected OS, \'e\' to edit the"),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
__("commands before booting, or \'c\' for a command-line."),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
__("The highlighted entry will be booted automatically in %d seconds."),
);
   
    my $e = "$prefix/boot/.enough_space";
    output $e, 1; -s $e or die _("not enough room in /boot");
    unlink $e;
    $f;
}

sub install_grub {
    my ($prefix, $lilo, $fstab, $hds) = @_;

    my $f = write_grub_config($prefix, $lilo, $fstab, $hds);

    log::l("Installing boot loader...");
    $::testing and return;
    symlink "$prefix/boot", "/boot";
    run_program::run_or_die("sh", $f);
    unlink "$prefix/tmp/.error.grub", "/boot";
}

sub lnx4win_file { 
    my $lilo = shift;
    map { local $_ = $_; s,/,\\,g; "$lilo->{boot_drive}:\\lnx4win$_" } @_;
}

sub loadlin_cmd {
    my ($prefix, $lilo) = @_;
    my $e = get_label("linux", $lilo) || first(grep { $_->{type} eq "image" } @{$lilo->{entries}});

    cp_af("$prefix$e->{kernel_or_dev}", "$prefix/boot/vmlinuz") unless -e "$prefix/boot/vmlinuz";
    cp_af("$prefix$e->{initrd}", "$prefix/boot/initrd.img") unless -e "$prefix/boot/initrd.img";

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
echo Mandrake Linux
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
#-PO: so you may need to put them in English or in a different language if MS-windows doesn't exist in your language
    foreach (__("Desktop"),
#-PO: "Desktop" and "Start Menu" are the name of the directories found in c:\windows 
	     __("Start Menu")) {
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

    if (my ($p) = grep { $lilo->{boot} =~ /\Q$_->{device}/ } @$fstab) {
	die _("You can't install the bootloader on a %s partition\n", partition_table::type2fs($p))
	  if isThisFs('xfs', $p);
    }
    $lilo->{keytable} = keytable($prefix, $lilo->{keytable});

    if (exists $lilo->{methods}{grub}) {
	#- when lilo is selected, we don't try to install grub. 
	#- just create the config file in case it may be useful
	eval { write_grub_config($prefix, $lilo, $fstab, $hds) };
    }

    my %l = grep_each { $::b } %{$lilo->{methods}};
    my @rcs = map {
	c::is_secure_file('/tmp/.error') or die "can't ensure a safe /tmp/.error";
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
