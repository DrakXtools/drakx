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
use partition_table::raw;
use run_program;
use modules;


%vga_modes = (
'ask' => "Ask at boot",
'normal' => "Normal",
'0x0f01' => "80x50",
'0x0f02' => "80x43",
'0x0f03' => "80x28",
'0x0f05' => "80x30",
'0x0f06' => "80x34",
'0x0f07' => "80x60",
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
    $_->{label} && substr($_->{label}, 0, 15) eq substr($label, 0, 15) and return $_ foreach @{$bootloader->{entries}};
    undef;
}

sub mkinitrd {
    my ($kernelVersion, $initrdImage) = @_;

    $::testing || -e "$::prefix/$initrdImage" and return 1;

    my $loop_boot = loopback::prepare_boot();

    modules::load('loop');
    if (!run_program::rooted($::prefix, "mkinitrd", "-v", "-f", $initrdImage, "--ifneeded", $kernelVersion)) {
	unlink("$::prefix/$initrdImage");
	die "mkinitrd failed";
    }
    loopback::save_boot($loop_boot);

    -e "$::prefix/$initrdImage";
}

sub mkbootdisk {
    my ($kernelVersion, $dev, $append) = @_;

    modules::load(if_(arch() =~ /sparc/, 'romfs'), 'loop', 'vfat');
    my @l = if_($append, '--appendargs', $append);
    run_program::rooted_or_die($::prefix, 'mkbootdisk', '--noprompt', @l, '--device', "/dev/$dev", $kernelVersion);
}

sub read() {
    my $file = sprintf("/etc/%s.conf", arch() =~ /sparc/ ? 'silo' : arch() =~ /ppc/ ? 'yaboot' : 'lilo');
    my $global = 1;
    my ($e, $v, $f);
    my %b;
    foreach (cat_("$::prefix$file")) {
	next if /^\s*#/ || /^\s*$/;
	($_, $v) = /^\s*([^=\s]+)\s*(?:=\s*(.*?))?\s*$/ or log::l("unknown line in lilo.conf: $_"), next;

	if (/^(image|other)$/) {
	    if (arch() =~ /ppc/) {
		$v =~ s/hd:\d+,//g;
	    }   
	    push @{$b{entries}}, $e = { type => $_, kernel_or_dev => $v };
	    $global = 0;
	} elsif ($global) {
	    if ($_ eq 'disk' && $v =~ /(\S+)\s+bios\s*=\s*(\S+)/) {
		$b{bios}{$1} = $2;
	    } elsif ($_ eq 'bios') {
		$b{bios}{$b{disk}} = $v;
	    } elsif ($_ eq 'init-message') {
		$v =~ s/\\n//g; 
		$v =~ s/"//g;
		$b{'init-message'} = $v;
	    } else {
		$b{$_} = $v || 1;
	    }
	} else {
	    if ((/map-drive/ .. /to/) && /to/) {
		$e->{mapdrive}{$e->{'map-drive'}} = $v;
	    } else {
		if (arch() =~ /ppc/) {
		    $v =~ s/hd:\d+,//g;
		    $v =~ s/"//g;
		}
		$e->{$_} = $v || 1 if !member($_, 'read-only');
	    }
	}
    }
    if (arch() !~ /ppc/) {
	delete $b{timeout} unless $b{prompt};
	$_->{append} =~ s/^\s*"?(.*?)"?\s*$/$1/ foreach \%b, @{$b{entries}};
	$b{timeout} = $b{timeout} / 10 if $b{timeout};
	$b{message} = cat_("$::prefix$b{message}") if $b{message};
    }

    #- cleanup duplicate labels (in case file is corrupted)
    my %seen;
    @{$b{entries}} = grep { !$seen{$_->{label}}++ } @{$b{entries}};

    \%b;
}

sub suggest_onmbr {
    my ($hds) = @_;
    
    my $type = partition_table::raw::typeOfMBR($hds->[0]{device});
    !$type || member($type, qw(dos dummy lilo grub empty)), !$type;
}

sub same_entries {
    my ($a, $b) = @_;

    foreach (uniq(keys %$a, keys %$b)) {
	if ($_ eq 'label') {
	    next;
	} elsif ($_ eq 'append') {
	    next if join(' ', sort split(' ', $a->{$_})) eq join(' ', sort split(' ', $b->{$_}))
	} else {
	    next if $a->{$_} eq $b->{$_};

	    my ($inode_a, $inode_b) = map { (stat "$::prefix$_")[1] } ($a->{$_}, $b->{$_});
	    next if $inode_a && $inode_b && $inode_a == $inode_b;
	}

	log::l("entries $a->{label} don't have same $_: $a->{$_} ne $b->{$_}");
	return;
    }
    1;
}

sub add_entry {
    my ($bootloader, $v) = @_;

    my $to_add = $v;
    foreach my $label ($v->{label}, map { 'old' . $_ . '_' . $v->{label} } ('', 2..10)) {
	my $conflicting = get_label($label, $bootloader);

	$to_add->{label} = $label;

	if ($conflicting) {
	    #- replacing $conflicting with $to_add
	    @{$bootloader->{entries}} = map { $_ == $conflicting ? $to_add : $_ } @{$bootloader->{entries}};
	} else {
	    #- we have found an unused label
	    push @{$bootloader->{entries}}, $to_add;
	}

	if (!$conflicting || same_entries($conflicting, $to_add)) {
	    log::l("current labels: " . join(" ", map { $_->{label} } @{$bootloader->{entries}}));
	    return $v;
	}
	$to_add = $conflicting;
    }
    die 'add_entry';
}

sub add_kernel {
    my ($lilo, $version, $ext, $root, $v) = @_;

    #- new versions of yaboot don't handle symlinks
    my $ppcext = $ext;
    if (arch() =~ /ppc/) {
	$ext = "-$version";
    }

    log::l("adding vmlinuz$ext as vmlinuz-$version");
    -e "$::prefix/boot/vmlinuz-$version" or log::l("unable to find kernel image $::prefix/boot/vmlinuz-$version"), return;
    my $image = "/boot/vmlinuz" . ($ext ne "-$version" &&
				   symlinkf("vmlinuz-$version", "$::prefix/boot/vmlinuz$ext") ? $ext : "-$version");

    my $initrd = "/boot/initrd-$version.img";
    mkinitrd($version, $initrd) or undef $initrd;
    if ($initrd && $ext ne "-$version") {
	$initrd = "/boot/initrd$ext.img";
	symlinkf("initrd-$version.img", "$::prefix$initrd") or cp_af("$::prefix/boot/initrd-$version.img", "$::prefix$initrd");
    }

    my $label = $ext =~ /-(default)/ ? $1 : ($ext =~ /\d\./ ? sanitize_ver("linux$ext") : "linux$ext");

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
    add_entry($lilo, $v);
}

sub duplicate_kernel_entry {
    my ($bootloader, $new_label) = @_;

    get_label($new_label, $bootloader) and return;

    my $entry = { %{ get_label('linux', $bootloader) }, label => $new_label };
    add_entry($bootloader, $entry);
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

    foreach (\$b->{perImageAppend}, map { \$_->{append} } grep { $_->{type} eq 'image' } @{$b->{entries}}) {
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

sub configure_entry {
    my ($entry) = @_;
    if ($entry->{type} eq 'image') {
	my $specific_version;
	$entry->{kernel_or_dev} =~ /vmlinu.-(.*)/ and $specific_version = $1;
	readlink("$::prefix/$entry->{kernel_or_dev}") =~ /vmlinu.-(.*)/ and $specific_version = $1;

	if ($specific_version) {
	    $entry->{initrd} or $entry->{initrd} = "/boot/initrd-$specific_version.img";
	    mkinitrd($specific_version, $entry->{initrd}) or undef $entry->{initrd};
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

sub get_kernels_and_labels() {
    my $dir = "$::prefix/boot";
    my @l = grep { /^vmlinuz-/ } all($dir);
    my @kernels = grep { ! -l "$dir/$_" } @l;

    my @preferred = ('', 'secure', 'enterprise', 'smp');
    my %weights = map_index { $_ => $::i } @preferred;
    
    require pkgs;
    @kernels = 
      sort { c::rpmvercmp($b->[1], $a->[1]) || $weights{$a->[2]} <=> $weights{$b->[2]} } 
      grep { -d "$::prefix/lib/modules/$_->[0]" }
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

# sanitize_ver: long function when it could be shorter but we are sure
#		to catch everything and can be readable if we want to
#		add new scheme name.
# DUPLICATED from /usr/share/loader/common.pm
my $mdksub = "smp|enterprise|secure|linus|mosix|BOOT|custom";

sub sanitize_ver {
    my $string = shift;
    my $return;
    (my $ehad, my $chtaim, my $chaloch, my $arba, my $hamesh, my $chech); #where that names come from ;)

    $string =~ m|([^-]+)-([^-]+)(-([^-]+))?(-([^-]*))?|;
    $ehad = $1; $chtaim = $2; $chaloch = $3; $arba = $4; $hamesh = $5; $chech = $6;

    if ($chtaim =~ m|mdk| and $chech =~ m|mdk(${mdksub})|) { #new mdk with mdksub
	my $s = $1;
	$chtaim =~ m|^(\d+)\.(\d+)\.(\d+)\.(\d+)mdk|;
	$return = "$1$2$3-$4$s";
    } elsif ($chtaim =~ m|mdk$|) { #new mdk
	$chtaim =~ m|^(\d+)\.(\d+)\.(\d+)\.(\d+)mdk$|;
	$return = "$1$2$3-$4";
    } elsif ($chaloch =~ m|(\d+)mdk(${mdksub})$|) { #old mdk with mdksub
	my $s = "$1$2";
	$chtaim =~ m|^(\d+)\.(\d+)\.(\d+)|;
	$return = "$1$2$3-$s";
    } elsif ($chaloch =~ m|(\d+)mdk$|) { #old mdk
	my $s = $1;
	$chtaim =~ m|^(\d+)\.(\d+)\.(\d+)|;
	$return = "$1$2$3-$s";
    } elsif (not defined($chaloch)) { #linus/marcelo vanilla
	$chtaim =~ m|^(\d+)\.(\d+)\.(\d+)$|;
	$return = "$1$2$3";
    } else { #a pre ac vanilla or whatever with EXTRAVERSION
	$chtaim =~ m|^(\d+)\.(\d+)\.(\d+)$|;
	$return = "$1$2$3${chaloch}";
    }
    $return =~ s|\.||g; $return =~ s|mdk||; $return =~ s|secure|sec|; $return =~ s|enterprise|ent|;
    return $return;
}

sub suggest {
    my ($lilo, $hds, $fstab, %options) = @_;
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
	} : arch() =~ /ppc/ ?
	{
	 defaultos => "linux",
	 entries => [],
	 'init-message' => "Welcome to Mandrake Linux!",
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
	 nowarn => 1,
	   if_(arch() !~ /ia64/,
	 boot => "/dev/" . ($onmbr ? $hds->[0]{device} : fsedit::get_root($fstab, 'boot')->{device}),
	 map => "/boot/map",
         ),
	});

    if (!$lilo->{message} || $lilo->{message} eq "1") {
	$lilo->{message} = join('', cat_("$::prefix/boot/message"));
	if (!$lilo->{message}) {
	    my $msg_en =
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
N_("Welcome to %s the operating system chooser!

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
	any::set_login_serial_console($port, $speed);
    }

    my %labels = get_kernels_and_labels();
    $labels{''} or die "no kernel installed";

    while (my ($ext, $version) = each %labels) {
	my $entry = add_kernel($lilo, $version, $ext, $root,
	       {
		if_($options{vga_fb} && $ext eq '', vga => $options{vga_fb}), #- using framebuffer
	       });
	$entry->{append} .= " quiet" if $options{vga_fb} && $version !~ /smp|enterprise/ && $options{quiet};

	if ($options{vga_fb} && $ext eq '') {
	    add_kernel($lilo, $version, $ext, $root, { label => 'linux-nonfb' });
	}
    }

    #- remove existing libsafe, don't care if the previous one was modified by the user?
    @{$lilo->{entries}} = grep { $_->{label} ne 'failsafe' } @{$lilo->{entries}};

    my $failsafe = add_kernel($lilo, $labels{''}, '', $root, { label => 'failsafe' });
    $failsafe->{append} =~ s/devfs=mount/devfs=nomount/;
    $failsafe->{append} .= " failsafe";

    if (arch() =~ /sparc/) {
	#- search for SunOS, it could be a really better approach to take into account
	#- partition type for mounting point.
	my $sunos = 0;
	foreach (@$hds) {
	    foreach (@{$_->{primary}{normal}}) {
		my $path = $_->{device} =~ m|^/| && $_->{device} !~ m|^/dev/| ? $_->{device} : dev2prompath($_->{device});
		add_entry($lilo,
			  {
			   type => 'other',
			   kernel_or_dev => $path,
			   label => "sunos"   . ($sunos++ ? $sunos : ''),
			  }) if $path && isSunOS($_) && type2name($_->{type}) =~ /root/i;
	    }
	}
    } elsif (arch() =~ /ppc/) {
	#- if we identified a MacOS partition earlier - add it
	if (defined $partition_table::mac::macos_part) {
	    add_entry($lilo,
		      {
		       label => "macos",
		       kernel_or_dev => $partition_table::mac::macos_part
		      });
	}
    } elsif (arch() !~ /ia64/) {
	#- search for dos (or windows) boot partition. Don't look in extended partitions!
	my %nbs;
	foreach (@$hds) {
	    foreach (@{$_->{primary}{normal}}) {
		isNT($_) || isFat($_) or next;
		my $from_magic = { type => fsedit::typeOfPart($_->{device}) };
		isNT($from_magic) || isFat($from_magic) or next;
		my $label = isNT($_) ? 'NT' : isDos($_) ? 'dos' : 'windows';
		add_entry($lilo,
			  {
			   type => 'other',
			   kernel_or_dev => "/dev/$_->{device}",
			   label => $label . ($nbs{$label}++ ? $nbs{$label} : ''),
			     if_($_->{device} =~ /[1-4]$/, 
			   table => "/dev/$_->{rootDevice}"
				),
			   unsafe => 1
			  })
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
	if ($lilo->{methods}{lilo} && -e "$::prefix/boot/message-graphic") {
	    $lilo->{methods}{lilo} = "lilo-graphic";
	    exists $lilo->{methods}{grub} and $lilo->{methods}{grub} = undef;
	}
    }
}

sub suggest_floppy {
    my ($bootloader) = @_;

    my $floppy = detect_devices::floppy() or return;
    $floppy eq 'fd0' or log::l("suggest_floppy: not adding $floppy"), return;

    add_entry($bootloader,
      {
       type => 'other',
       kernel_or_dev => '/dev/fd0',
       label => 'floppy',
       unsafe => 1
      });
}

sub keytable {
    my ($f) = @_;
    $f or return;

    if ($f !~ /\.klt$/) {
	my $file = "/boot/$f.klt";
	run_program::rooted($::prefix, "keytab-lilo.pl", ">", $file, $f) or return;
	$f = $file;
    }
    -r "$::prefix/$f" && $f;
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

sub get_of_dev {
	my ($unix_dev) = @_;
	#- don't care much for this - need to run ofpath rooted, and I need the result
	#- In test mode, just run on "/", otherwise you can't get to the /proc files		
	run_program::rooted_or_die($::prefix, "/usr/sbin/ofpath $unix_dev", ">", "/tmp/ofpath");
	open(FILE, "$::prefix/tmp/ofpath") || die "Can't open $::prefix/tmp/ofpath";
	my $of_dev = "";
	local $_ = "";
	while (<FILE>){
		$of_dev = $_;
	}
	chop($of_dev);
	my @del_file = ($::prefix . "/tmp/ofpath");
	unlink (@del_file);
	log::l("OF Device: $of_dev");
	$of_dev;
}

sub install_yaboot {
    my ($lilo, $fstab, $hds) = @_;
    $lilo->{prompt} = $lilo->{timeout};

    if ($lilo->{message}) {
	local *F;
	open F, ">$::prefix/boot/message" and print F $lilo->{message} or $lilo->{message} = 0;
    }
    {
	local *F;
        local $\ = "\n";
	my $f = "$::prefix/etc/yaboot.conf";
	open F, ">$f" or die "cannot create yaboot config file: $f";
	log::l("writing yaboot config to $f");

	print F "#yaboot.conf - generated by DrakX";
	print F "init-message=\"\\n$lilo->{'init-message'}\\n\"" if $lilo->{'init-message'};

	if ($lilo->{boot}) {
	    print F "boot=$lilo->{boot}";
	    my $of_dev = get_of_dev($lilo->{boot});
	    print F "ofboot=$of_dev";
	} else {
	    die "no bootstrap partition defined."
	}
	
	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(delay timeout);
	print F "install=/usr/lib/yaboot/yaboot";
	print F "magicboot=/usr/lib/yaboot/ofboot";
	$lilo->{$_} and print F $_ foreach qw(enablecdboot enableofboot);
	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(defaultos default);
	#- print F "nonvram";
	my $boot = "/dev/" . $lilo->{useboot} if $lilo->{useboot};
		
	foreach (@{$lilo->{entries}}) {

	    if ($_->{type} eq "image") {
		my $of_dev = '';
		if (($boot !~ /$_->{root}/) && $boot) {
		    $of_dev = get_of_dev($boot);
		    print F "$_->{type}=$of_dev," . substr($_->{kernel_or_dev}, 5);
		} else {
		    $of_dev = get_of_dev($_->{root});    			
		    print F "$_->{type}=$of_dev,$_->{kernel_or_dev}";
		}
		print F "\tlabel=", substr($_->{label}, 0, 15); #- lilo doesn't handle more than 15 char long labels
		print F "\troot=$_->{root}";
		if (($boot !~ /$_->{root}/) && $boot) {
		    print F "\tinitrd=$of_dev," . substr($_->{initrd}, 5) if $_->{initrd};
		} else {
		    print F "\tinitrd=$of_dev,$_->{initrd}" if $_->{initrd};
		}
		#- xfs module on PPC requires larger initrd - say 6MB?
		print F "\tinitrd-size=6144" if $lilo->{xfsroot};
		print F "\tappend=\" $_->{append}\"" if $_->{append};
		print F "\tread-write" if $_->{'read-write'};
		print F "\tread-only" if !$_->{'read-write'};
	    } else {
		my $of_dev = get_of_dev($_->{kernel_or_dev});
		print F "$_->{label}=$of_dev";		
	    }
	}
    }
    log::l("Installing boot loader...");
    my $f = "$::prefix/tmp/of_boot_dev";
    my $of_dev = get_of_dev($lilo->{boot});
    output($f, "$of_dev\n");  
    $::testing and return;
    if (defined $install_steps_interactive::new_bootstrap) {
	run_program::run("hformat", "$lilo->{boot}") or die "hformat failed";
    }	
    run_program::rooted_or_die($::prefix, "/usr/sbin/ybin", "2>", "/tmp/.error");
    unlink "$::prefix/tmp/.error";	
}

sub install_silo {
    my ($silo, $fstab) = @_;
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
	open F, ">$::prefix/boot/message" and print F $silo->{message} or $silo->{message} = 0;
    }
    {
	local *F;
        local $\ = "\n";
	my $f = "$::prefix/boot/silo.conf"; #- always write the silo.conf file in /boot ...
	symlinkf "../boot/silo.conf", "$::prefix/etc/silo.conf"; #- ... and make a symlink from /etc.
	open F, ">$f" or die "cannot create silo config file: $f";
	log::l("writing silo config to $f");

	$silo->{$_} and print F "$_=$silo->{$_}" foreach qw(partition root default append);
	$silo->{$_} and print F $_ foreach qw(restricted);
	print F "password=", $silo->{password} if $silo->{restricted} && $silo->{password}; #- also done by msec
	print F "timeout=", round(10 * $silo->{timeout}) if $silo->{timeout};
	print F "message=$silo->{boot}/message" if $silo->{message};

	foreach (@{$silo->{entries}}) { #-my ($v, $e) = each %{$silo->{entries}}) {
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
    run_program::rooted($::prefix, "silo", "2>", "/tmp/.error", $silo->{use_partition} ? ("-t") : ()) or 
        run_program::rooted_or_die($::prefix, "silo", "2>", "/tmp/.error", "-p", "2", $silo->{use_partition} ? ("-t") : ());
    unlink "$::prefix/tmp/.error";

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
    my ($lilo, $fstab, $hds) = @_;
    $lilo->{prompt} = $lilo->{timeout};

    my $file2fullname = sub {
	my ($file) = @_;
	if (arch() =~ /ia64/) {
	    (my $part, $file) = fsedit::file2part($fstab, $file);
	    my %hds = map_index { $_ => "hd$::i" } map { $_->{device} } 
	      sort { isFat($b) <=> isFat($a) || $a->{device} cmp $b->{device} } fsedit::get_fstab(@$hds);
	    $hds->{$part->{device}} . ":" . $file;
	} else {
	    $file
	}
    };

    my %bios2dev = map_index { $::i => $_ } dev2bios($hds, $lilo->{first_hd_device} || $lilo->{boot});
    my %dev2bios = reverse %bios2dev;

    if (is_empty_hash_ref($lilo->{bios} ||= {})) {
	my $dev = $hds->[0]{device};
	if ($dev2bios{$dev}) {
	    log::l("Since we're booting on $bios2dev{0}, make it bios=0x80, whereas $dev is now " . (0x80 + $dev2bios{$dev}));
	    $lilo->{bios}{"/dev/$bios2dev{0}"} = '0x80';
	    $lilo->{bios}{"/dev/$dev"} = sprintf("0x%x", 0x80 + $dev2bios{$dev});
	}
	foreach (0 .. 3) {
	    my ($letter) = $bios2dev{$_} =~ /hd([^ac])/; #- at least hda and hdc are handled correctly :-/
	    next if $lilo->{bios}{"/dev/$bios2dev{$_}"} || !$letter;
	    next if 
	      $_ > 0	     #- always print if first disk is hdb, hdd, hde...
		&& $bios2dev{$_ - 1} eq "hd" . chr(ord($letter) - 1);
	    #- no need to help lilo with hdb (resp. hdd, hdf...)
	    log::l("Helping lilo: $bios2dev{$_} must be " . (0x80 + $_));
	    $lilo->{bios}{"/dev/$bios2dev{$_}"} = sprintf("0x%x", 0x80 + $_);
	}
    }

    {
	local *F;
        local $\ = "\n";
	my $f = arch() =~ /ia64/ ? "$::prefix/boot/efi/elilo.conf" : "$::prefix/etc/lilo.conf";

	open F, ">$f" or die "cannot create lilo config file: $f";
	log::l("writing lilo config to $f");

	chmod 0600, $f if $lilo->{password};

	#- normalize: RESTRICTED is only valid if PASSWORD is set
	delete $lilo->{restricted} if !$lilo->{password};

	local $lilo->{default} = make_label_lilo_compatible($lilo->{default});
	$lilo->{$_} and print F "$_=$lilo->{$_}" foreach qw(boot map install vga default keytable);
	$lilo->{$_} and print F $_ foreach qw(linear geometric compact prompt nowarn restricted);
	print F "append=\"$lilo->{append}\"" if $lilo->{append};
 	print F "password=", $lilo->{password} if $lilo->{password}; #- also done by msec
	print F "timeout=", round(10 * $lilo->{timeout}) if $lilo->{timeout};
	print F "serial=", $1 if get_append($lilo, 'console') =~ /ttyS(.*)/;

	print F "message=/boot/message" if (arch() !~ /ia64/);
	print F "menu-scheme=wb:bw:wb:bw" if (arch() !~ /ia64/);

	print F "ignore-table" if grep { $_->{unsafe} && $_->{table} } @{$lilo->{entries}};

	while (my ($dev, $bios) = each %{$lilo->{bios}}) {
	    print F "disk=$dev bios=$bios";
	}

	foreach (@{$lilo->{entries}}) {
	    print F "$_->{type}=", $file2fullname->($_->{kernel_or_dev});
	    print F "\tlabel=", make_label_lilo_compatible($_->{label});

	    if ($_->{type} eq "image") {		
		print F "\troot=$_->{root}" if $_->{root};
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
    my ($lilo, $fstab, $hds) = @_;

    $lilo->{install} = 'text' if $lilo->{methods}{lilo} eq 'lilo-text';
    output("$::prefix/boot/message-text", $lilo->{message}) if $lilo->{message};
    symlinkf "message-" . ($lilo->{methods}{lilo} eq 'lilo-graphic' ? 'graphic' : 'text'), "$::prefix/boot/message";

    write_lilo_conf($lilo, $fstab, $hds);

    log::l("Installing boot loader...");
    $::testing and return;
    run_program::rooted_or_die($::prefix, "lilo", "2>", "/tmp/.error") if (arch() !~ /ia64/);
    unlink "$::prefix/tmp/.error";
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
    my ($lilo, $fstab, $hds) = @_;
    my %dev2bios = (
      (map_index { $_ => "fd$::i" } detect_devices::floppies_dev()),
      (map_index { $_ => "hd$::i" } dev2bios($hds, $lilo->{first_hd_device} || $lilo->{boot})),
    );

    {
	my %bios2dev = reverse %dev2bios;
	output "$::prefix/boot/grub/device.map", 
	  join '', map { "($_) /dev/$bios2dev{$_}\n" } sort keys %bios2dev;
    }
    my $bootIsReiser = isThisFs("reiserfs", fsedit::get_root($fstab, 'boot'));
    my $file2grub = sub {
	my ($part, $file) = fsedit::file2part($fstab, $_[0], 'keep_simple_symlinks');
	dev2grub($part->{device}, \%dev2bios) . $file;
    };
    {
	local *F;
        local $\ = "\n";
	my $f = "$::prefix/boot/grub/menu.lst";
	open F, ">$f" or die "cannot create grub config file: $f";
	log::l("writing grub config to $f");

	$lilo->{$_} and print F "$_ $lilo->{$_}" foreach qw(timeout);

	print F "color black/cyan yellow/cyan";
	print F "i18n ", $file2grub->("/boot/grub/messages");
	print F "keytable ", $file2grub->($lilo->{keytable}) if $lilo->{keytable};
	print F "serial --unit=$1 --speed=$2\nterminal --timeout=" . ($lilo->{timeout} || 0) . " console serial" if get_append($lilo, 'console') =~ /ttyS(\d),(\d+)/;

	#- since we use notail in reiserfs, altconfigfile is broken :-(
	unless ($bootIsReiser) {
	    print F "altconfigfile ", $file2grub->(my $once = "/boot/grub/menu.once");
	    output "$::prefix$once", " " x 100;
	}

	each_index {
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
		      if $_->{table} && ($lilo->{first_hd_device} || $lilo->{boot}) !~ /$_->{table}/;
	    
		    map_each { print F "map ($::b) ($::a)" } %{$_->{mapdrive} || {}};

		    print F "makeactive";
		}
		print F "chainloader +1";
	    }
	}
    }
    my $hd = fsedit::get_root($fstab, 'boot')->{rootDevice};

    my $dev = dev2grub($lilo->{first_hd_device} || $lilo->{boot}, \%dev2bios);
    my ($s1, $s2, $m) = map { $file2grub->("/boot/grub/$_") } qw(stage1 stage2 menu.lst);
    my $f = "/boot/grub/install.sh";
    output "$::prefix$f",
"grub --device-map=/boot/grub/device.map --batch <<EOF
install $s1 d $dev $s2 p $m
quit
EOF
";

     output "$::prefix/boot/grub/messages", map { substr(translate($_) . "\n", 0, 78) } ( #- ensure the translated messages are not too big the hard way
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
N_("Welcome to GRUB the operating system chooser!"),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
N_("Use the %c and %c keys for selecting which entry is highlighted."),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
N_("Press enter to boot the selected OS, \'e\' to edit the"),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
N_("commands before booting, or \'c\' for a command-line."),
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
#-PO: and keep them smaller than 79 chars long
N_("The highlighted entry will be booted automatically in %d seconds."),
);
   
    my $e = "$::prefix/boot/.enough_space";
    output $e, 1; -s $e or die N("not enough room in /boot");
    unlink $e;
    $f;
}

sub install_grub {
    my ($lilo, $fstab, $hds) = @_;

    my $f = write_grub_config($lilo, $fstab, $hds);

    log::l("Installing boot loader...");
    $::testing and return;
    symlink "$::prefix/boot", "/boot";
    run_program::run_or_die("sh", $f);
    unlink "$::prefix/tmp/.error.grub", "/boot";
}

sub lnx4win_file { 
    my $lilo = shift;
    map { local $_ = $_; s,/,\\,g; "$lilo->{boot_drive}:\\lnx4win$_" } @_;
}

sub loadlin_cmd {
    my ($lilo) = @_;
    my $e = get_label("linux", $lilo) || first(grep { $_->{type} eq "image" } @{$lilo->{entries}});

    cp_af("$::prefix$e->{kernel_or_dev}", "$::prefix/boot/vmlinuz") unless -e "$::prefix/boot/vmlinuz";
    cp_af("$::prefix$e->{initrd}", "$::prefix/boot/initrd.img") unless -e "$::prefix/boot/initrd.img";

    $e->{label}, sprintf"%s %s initrd=%s root=%s $e->{append}", 
      lnx4win_file($lilo, "/loadlin.exe", "/boot/vmlinuz", "/boot/initrd.img"),
	$e->{root} =~ /loop7/ ? "0707" : $e->{root}; #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
}

sub install_loadlin {
    my ($lilo, $fstab) = @_;

    my $boot;
    ($boot) = grep { $lilo->{boot} eq "/dev/$_->{device}" } @$fstab;
    ($boot) = grep { loopback::carryRootLoopback($_) } @$fstab unless $boot && $boot->{device_windobe};
    ($boot) = grep { isFat($_) } @$fstab unless $boot && $boot->{device_windobe};
    log::l("loadlin device is $boot->{device} (windobe $boot->{device_windobe})");
    $lilo->{boot_drive} = $boot->{device_windobe};

    my ($winpart) = grep { $_->{device_windobe} eq 'C' } @$fstab;
    log::l("winpart is $winpart->{device}");
    my $winhandle = any::inspect($winpart, $::prefix, 'rw');
    my $windrive = $winhandle->{dir};
    log::l("windrive is $windrive");

    my ($label, $cmd) = loadlin_cmd($lilo);

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
    foreach (N_("Desktop"),
#-PO: "Desktop" and "Start Menu" are the name of the directories found in c:\windows 
	     N_("Start Menu")) {
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
    my ($lilo, $fstab, $hds) = @_;

    if (my ($p) = grep { $lilo->{boot} eq "/dev/$_->{device}" } @$fstab) {
	die N("You can't install the bootloader on a %s partition\n", partition_table::type2fs($p))
	  if isThisFs('xfs', $p);
    }
    $lilo->{keytable} = keytable($lilo->{keytable});

    if (exists $lilo->{methods}{grub}) {
	#- when lilo is selected, we don't try to install grub. 
	#- just create the config file in case it may be useful
	eval { write_grub_config($lilo, $fstab, $hds) };
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

1;
