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


our %vga_modes = (
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
    $_->{label} && lc(make_label_lilo_compatible($_->{label})) eq lc(make_label_lilo_compatible($label)) and return $_ foreach @{$bootloader->{entries}};
    undef;
}

sub mkinitrd {
    my ($kernelVersion, $initrdImage, $o_vga) = @_;

    $::testing || -e "$::prefix/$initrdImage" and return 1;

    my $loop_boot = loopback::prepare_boot();

    my $o_resolution = $o_vga && do {
	require Xconfig::resolution_and_depth;
	my $res = Xconfig::resolution_and_depth::from_bios($o_vga);
	$res && $res->{X};
    };
    modules::load('loop');
    if (!run_program::rooted($::prefix, "mkinitrd", "-v", "-f", $initrdImage, "--ifneeded", $kernelVersion, if_($o_resolution, '--splash' => $o_resolution))) {
	unlink("$::prefix/$initrdImage");
	die "mkinitrd failed";
    }
    loopback::save_boot($loop_boot);

    -e "$::prefix/$initrdImage";
}

sub read() {
    my $file = sprintf("/etc/%s.conf", arch() =~ /sparc/ ? 'silo' : arch() =~ /ppc/ ? 'yaboot' : 'lilo');
    my $bootloader = $file =~ /lilo/ && detect_bootloader() =~ /GRUB/ && -f "/boot/grub/menu.lst" ? read_grub() : read_lilo($file);
    if (my $default = find { $_ && $_->{append} } get_label($bootloader->{default}, $bootloader), @{$bootloader->{entries}}) {
	$bootloader->{perImageAppend} ||= $default->{append};
    }
    $bootloader;
}

sub read_grub() {
    my $global = 1;
    my ($e, %b);

    my %mnt_pts = (
	"/dev/" . devices::from_devfs(readlink('/dev/root')) => "/", #- is this useful???
	map { (split)[0..1] } cat_("/proc/mounts")
    );

    foreach (cat_("$::prefix/boot/grub/menu.lst")) {
        chomp;
	s/^\s*//; s/\s*$//;
        next if /^#/ || /^$/;
	my ($keyword, $v) = split(' ', $_, 2) or
	  warn qq(unknown line in /boot/grub/menu.lst: "$_"\n), next;

        if ($keyword eq 'title') {
            push @{$b{entries}}, $e = { label => $v };
            $global = 0;
        } elsif ($global) {
            $b{$keyword} = $v eq '' ? 1 : ungrubify($v, \%mnt_pts);
        } else {
            $e->{root} = $1 if $v =~ s/root=(\S*)\s*//;
            if ($keyword eq 'kernel') {
                $e->{type} = 'image';
                (my $kernel, $e->{append}) = split(' ', $v, 2);
		$e->{kernel_or_dev} = ungrubify($kernel, \%mnt_pts);
            } elsif ($keyword eq 'root') {
                $e->{type} = 'other';
		if ($v =~ /,/) {
		    $e->{table} = grub2dev($v, 1);
		} else {
		    $e->{unsafe} = 1;
		}
                $e->{kernel_or_dev} = grub2dev($v);
                $e->{append} = "";
            } elsif ($keyword eq 'initrd') {
                $e->{initrd} = ungrubify($v, \%mnt_pts);
            }
        }
    }
    # Generating /etc/lilo.conf require having a boot device:
    foreach (cat_("$::prefix/boot/grub/install.sh")) {
        $b{boot} = grub2dev($1) if /\s+d\s+(\(.*?\))/;
    }

    #- sanitize
    foreach (@{$b{entries}}) {
	my ($vga, $other) = partition { /^vga=/ } split(' ', $_->{append});
	if (@$vga) {
	    $_->{vga} = $vga->[0] =~ /vga=(.*)/ && $1;
	    $_->{append} = join(' ', @$other);
	}
    }

    $b{nowarn} = 1;
    # handle broken installkernel -r:
    $b{default} = min($b{default}, scalar(@{$b{entries}}) - 1);
    $b{default} = $b{entries}[$b{default}]{label};

    \%b;
}

sub read_lilo {
    my ($file) = @_;
    my $global = 1;
    my ($e, $v);
    my %b;
    foreach (cat_("$::prefix$file")) {
	next if /^\s*#/ || /^\s*$/;
	($_, $v) = /^\s*([^=\s]+)\s*(?:=\s*(.*?))?\s*$/ or log::l("unknown line in $file: $_"), next;

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
		$b{$_} = $v eq '' ? 1 : $v;
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
	sub remove_quotes_and_spaces {
	    local ($_) = @_;
	    s/^\s*//; s/\s*$//;
	    s/^"(.*?)"$/$1/;
	    $_;
	}
	$_->{append} = remove_quotes_and_spaces($_->{append}) foreach \%b, @{$b{entries}};
	$_->{label}  = remove_quotes_and_spaces($_->{label})  foreach @{$b{entries}};
	$b{default} = remove_quotes_and_spaces($b{default}) if $b{default};
	$b{timeout} = $b{timeout} / 10 if $b{timeout};
	delete $b{message};
    }

    #- cleanup duplicate labels & bad entries (in case file is corrupted)
    my %seen;
    @{$b{entries}} = 
	grep { !$seen{$_->{label}}++ }
	grep { $_->{type} ne 'image' || -e "$::prefix$_->{kernel_or_dev}" } @{$b{entries}};

    \%b;
}

sub suggest_onmbr {
    my ($hd) = @_;
    
    my ($onmbr, $unsafe) = (1, 1);

    if (my $type = partition_table::raw::typeOfMBR($hd->{device})) {
	if (member($type, qw(dos dummy empty))) {
	    $unsafe = 0;
	} elsif (!member($type, qw(lilo grub))) {
	    $onmbr = 0;
	}
	log::l("bootloader::suggest_onmbr: type $type, onmbr $onmbr, unsafe $unsafe");
    }
    ($onmbr, $unsafe);
}

sub mixed_kind_of_disks {
    my ($hds) = @_;

    (find { $_->{device} =~ /^sd/ } @$hds) && (find { $_->{device} =~ /^hd/ } @$hds) ||
      (find { $_->{device} =~ /^hd[e-z]/ } @$hds) && (find { $_->{device} =~ /^hd[a-d]/ } @$hds);
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
    my ($bootloader, $version, $ext, $root, $v) = @_;

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
    mkinitrd($version, $initrd, $v->{vga}) or undef $initrd;
    if ($initrd && $ext ne "-$version") {
	$initrd = "/boot/initrd$ext.img";
	symlinkf("initrd-$version.img", "$::prefix$initrd") or cp_af("$::prefix/boot/initrd-$version.img", "$::prefix$initrd");
    }

    my $label = $ext =~ /-(default)/ ? $1 : $ext =~ /\d\./ && sanitize_ver("linux-$version") || "linux$ext";

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
	     });
    $v->{append} = normalize_append("$bootloader->{perImageAppend} $v->{append}");
    add_entry($bootloader, $v);
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

    #- normalize
    $simple = [ reverse(uniq(reverse @$simple)) ];
    $dict = [ reverse(uniq_ { my ($k, $v) = @$_; $k eq 'mem' ? "$k=$v" : $k } reverse @$dict) ];

    join(' ', @$simple, map { "$_->[0]=$_->[1]" } @$dict);
}

sub normalize_append {
    my ($s) = @_;
    my ($simple, $dict) = unpack_append($s);
    pack_append($simple, $dict);
}

sub append__mem_is_memsize { $_[0] =~ /^\d+[kM]?$/i }

sub get_append {
    my ($b, $key) = @_;
    my ($simple, $dict) = unpack_append($b->{perImageAppend});
    if (member($key, @$simple)) {
	return 1;
    }
    my @l = map { $_->[1] } grep { $_->[0] eq $key } @$dict;

    #- suppose we want the memsize
    @l = grep { append__mem_is_memsize($_) } @l if $key eq 'mem';

    log::l("more than one $key in $b->{perImageAppend}") if @l > 1;
    $l[0];
}
sub modify_append {
    my ($b, $f) = @_;

    foreach (\$b->{perImageAppend}, map { \$_->{append} } grep { $_->{type} eq 'image' } @{$b->{entries}}) {
	my ($simple, $dict) = unpack_append($$_);
	$f->($simple, $dict);
	$$_ = pack_append($simple, $dict);
	log::l("modify_append: $$_");
    }
}
sub remove_append_simple {
    my ($b, $key) = @_;
    modify_append($b, sub {
	my ($simple, $_dict) = @_;
	@$simple = grep { $_ ne $key } @$simple;
    });
}
sub set_append {
    my $has_val = @_ > 2;
    my ($b, $key, $val) = @_;

    modify_append($b, sub {
	my ($simple, $dict) = @_;
	if ($has_val) {
	    @$dict = grep { $_->[0] ne $key || $key eq 'mem' && append__mem_is_memsize($_->[1]) != append__mem_is_memsize($val) } @$dict;
	    push @$dict, [ $key, $val ] if !($val eq '' || $key eq 'mem' && !$val);
	} else {
	    @$simple = grep { $_ ne $key } @$simple;
	    push @$simple, $key;
	}
    });
}
sub may_append {
    my ($b, $key, $val) = @_;
    set_append($b, $key, $val) if !get_append($b, $key);
}

sub configure_entry {
    my ($entry) = @_;
    if ($entry->{type} eq 'image') {
	my $specific_version;
	$entry->{kernel_or_dev} =~ /vmlinu.-(.*)/ and $specific_version = $1;
	readlink("$::prefix/$entry->{kernel_or_dev}") =~ /vmlinu.-(.*)/ and $specific_version = $1;

	if ($specific_version) {
	    $entry->{initrd} or $entry->{initrd} = "/boot/initrd-$specific_version.img";
	    mkinitrd($specific_version, $entry->{initrd}, $entry->{vga}) or undef $entry->{initrd};
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
    my ($b_prefer_24) = @_;

    my $dir = "$::prefix/boot";
    my @l = grep { /^vmlinuz-/ } all($dir);
    my @kernels = grep { ! -l "$dir/$_" } @l;
    
    require pkgs;
    @kernels = 
      sort { c::rpmvercmp($b->{version}, $a->{version}) } 
      grep { -d "$::prefix/lib/modules/$_->{complete_version}" }
      map {
	  s/vmlinuz-//;
	  { complete_version => $_, /(.*mdk)-?(.*)/ ? (ext => $2, version => $1) : (version => $_) };
      } @kernels;

    if ($b_prefer_24) {
	my ($kernel_24, $other) = partition { $_->{ext} eq '' && $_->{version} =~ /^\Q2.4/ } @kernels;
	@kernels = (@$kernel_24, @$other);
    }

    my %labels = ('' => $kernels[0]{complete_version});    
    foreach (@kernels) {
	my @propositions = (
			    if_($_->{ext}, '-' . $_->{ext}), 
			    '-' . $_->{version} . $_->{ext},
			   );
	my $label = find { ! exists $labels{$_} } @propositions;
	$labels{$label} = $_->{complete_version};
    }
    %labels;
}

# sanitize_ver: long function when it could be shorter but we are sure
#		to catch everything and can be readable if we want to
#		add new scheme name.
# DUPLICATED from /usr/share/loader/common.pm
sub sanitize_ver {
    my ($string) = @_;

    my ($main_version, undef, $extraversion, $rest) = 
      $string =~ m!(\d+\.\d+\.\d+)(-((?:pre|rc)\d+))?(.*)!;

    if (my ($mdkver, $cpu, $nproc, $mem) = $rest =~ m|-(.+)-(.+)-(.+)-(.+)|) {
	$rest = "$cpu$nproc$mem-$mdkver";
    }

    my $return = "$main_version$extraversion$rest";

    $return =~ s|\.||g;
    $return =~ s|mdk||;
    $return =~ s|64GB|64G|;
    $return =~ s|4GB|4G|;
    $return =~ s|secure|sec|;
    $return =~ s|enterprise|ent|;

    return $return;
}

sub suggest {
    my ($bootloader, $hds, $fstab, %options) = @_;
    my $root_part = fsedit::get_root($fstab);
    my $root = isLoopback($root_part) ? "loop7" : $root_part->{device};
    my $boot = fsedit::get_root($fstab, 'boot')->{device};
    my $partition = first($boot =~ /\D*(\d*)/);
    #- PPC xfs module requires enlarged initrd
    my $xfsroot = isThisFs("xfs", $root_part);

    my ($onmbr, $unsafe) = $bootloader->{crushMbr} ? (1, 0) : suggest_onmbr($hds->[0]);
    add2hash_($bootloader, arch() =~ /ppc/ ?
	{
	 defaultos => "linux",
	 entries => [],
	 'init-message' => "Welcome to Mandrakelinux!",
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

    if (!$bootloader->{message} || $bootloader->{message} eq "1") {
	my $msg_en =
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
N_("Welcome to the operating system chooser!

Choose an operating system from the list above or
wait for default boot.

");
	my $msg = translate($msg_en);
	#- use the english version if more than 20% of 8bits chars
	$msg = $msg_en if int(grep { $_ & 0x80 } unpack "c*", $msg) / length($msg) > 0.2;
	$bootloader->{message} = $msg;
    }

    add2hash_($bootloader, { memsize => $1 }) if cat_("/proc/cmdline") =~ /\bmem=(\d+[KkMm]?)(?:\s.*)?$/;
    if (my ($s, $port, $speed) = cat_("/proc/cmdline") =~ /console=(ttyS(\d),(\d+)\S*)/) {
	log::l("serial console $s $port $speed");
	set_append($bootloader, 'console' => $s);
	any::set_login_serial_console($port, $speed);
    }

    #- add a restore entry if installation is done from disk, in order to allow redoing it.
    if (my $hd_install_path = any::hdInstallPath()) {
	my ($cmdline, $vga);
	if ($::restore && -e "/tmp/image/boot/vmlinuz" && -e "/tmp/image/boot/all.rdz" &&
	    ($cmdline = cat_("/tmp/image/boot/grub/menu.lst") =~ m|kernel \S+/boot/vmlinuz (.*)$|m)) {
	    #- cmdline should'n have any reference to vga=...
	    $cmdline =~ s/vga=(\S+)//g and $vga = $1;
	    log::l("copying kernel and stage1 install to $::prefix/boot/restore");
	    eval { mkdir "$::prefix/boot/restore";
		   cp_af("/tmp/image/boot/vmlinuz", "$::prefix/boot/restore/vmlinuz");
		   cp_af("/tmp/image/boot/all.rdz", "$::prefix/boot/restore/all.rdz") };
	    unless ($@) {
		log::l("adding a restore bootloader entry on $hd_install_path (remapped to $::prefix/boot/restore)");
		add_entry($bootloader, {
					type => 'image',
					label => 'restore',
					kernel_or_dev => "/boot/restore/vmlinuz",
					initrd => "/boot/restore/all.rdz",
					append => "$cmdline recovery", #- the restore entry is a recovery entry
					if_($vga, vga => $vga),
				       });
	    }
	} else {
	    log::l("no restore bootloader need to be used on $hd_install_path");
	}
    }

    my %labels = get_kernels_and_labels();
    $labels{''} or die "no kernel installed";

    while (my ($ext, $version) = each %labels) {
	add_kernel($bootloader, $version, $ext, $root,
	       {
		if_($options{vga_fb} && $ext eq '', vga => $options{vga_fb}), #- using framebuffer
		if_($options{vga_fb} && $options{quiet}, append => "splash=silent"),
	       });

	if ($options{vga_fb} && $ext eq '') {
	    add_kernel($bootloader, $version, $ext, $root, { label => 'linux-nonfb' });
	}
    }

    #- remove existing libsafe, don't care if the previous one was modified by the user?
    @{$bootloader->{entries}} = grep { $_->{label} ne 'failsafe' } @{$bootloader->{entries}};

    add_kernel($bootloader, $labels{''}, '', $root,
	       { label => 'failsafe', append => 'devfs=nomount failsafe' });

    if (arch() =~ /ppc/) {
	#- if we identified a MacOS partition earlier - add it
	if (defined $partition_table::mac::macos_part) {
	    add_entry($bootloader,
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
		isFat_or_NTFS($_) or next;
		my $from_magic = { type => fsedit::typeOfPart($_->{device}) };
		isFat_or_NTFS($from_magic) or next;
		my $label = 'windows';
		add_entry($bootloader,
			  {
			   type => 'other',
			   kernel_or_dev => "/dev/$_->{device}",
			   label => $label . ($nbs{$label}++ ? $nbs{$label} : ''),
			     $_->{device} =~ /[1-4]$/ ? (
			   table => "/dev/$_->{rootDevice}"
			     ) : (
			   unsafe => 1
                             ),
			  })
	    }
	}
    }

    my @preferred = map { "linux-$_" } 'p3-smp-64GB', 'secure', 'enterprise', 'smp', 'i686-up-4GB';
    if (my $preferred = find { get_label($_, $bootloader) } @preferred) {
	$bootloader->{default} ||= $preferred;
    }
    $bootloader->{default} ||= "linux";
    $bootloader->{method} ||= first(method_choices($fstab, $bootloader));
}

sub detect_bootloader() {
    chomp_(run_program::rooted_get_stdout($::prefix, 'detectloader'));
}

sub method_choices {
    my ($fstab, $bootloader) = @_;
    my %choices = (
	if_(arch() !~ /ppc/ && !isLoopback(fsedit::get_root($fstab)) && whereis_binary('lilo'),
	    if_(!detect_devices::matching_desc('ProSavageDDR'), 'lilo-graphic' => N("LILO with graphical menu")),
	    'lilo-menu'    => N("LILO with text menu"),
	), if_(arch() !~ /ppc/ && !isRAID(fsedit::get_root($fstab)) && whereis_binary('grub'),
	    'grub' => N("Grub"),
        ), if_(arch() =~ /ppc/,
	    'yaboot' => N("Yaboot"),
        ),
    );
    my $prefered;
    $prefered ||= 'grub' if $::isStandalone && detect_bootloader() =~ /GRUB/;
    $prefered ||= 'lilo-' . (member($bootloader->{install}, 'text', 'menu', 'graphic') ? $bootloader->{install} : 'graphic');
    my $default = exists $choices{$prefered} ? $prefered : first(keys %choices);

    $default, \%choices;
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

sub has_profiles { my ($b) = @_; to_bool(get_label("office", $b)) }
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
    my $of_dev;
    run_program::rooted_or_die($::prefix, "/usr/sbin/ofpath", ">", \$of_dev, $unix_dev);
    chomp($of_dev);
    log::l("OF Device: $of_dev");
    $of_dev;
}

sub check_enough_space() {
    my $e = "$::prefix/boot/.enough_space";
    output $e, 1; -s $e or die N("not enough room in /boot");
    unlink $e;
}

sub install_yaboot {
    my ($bootloader, $_fstab, $_hds) = @_;
    $bootloader->{prompt} = $bootloader->{timeout};

    if ($bootloader->{message}) {
	eval { output("$::prefix/boot/message", $bootloader->{message}) }
	  or $bootloader->{message} = 0;
    }
    {
        local $\ = "\n";
	my $f = "$::prefix/etc/yaboot.conf";
	local *F;
	open F, ">$f" or die "cannot create yaboot config file: $f";
	log::l("writing yaboot config to $f");

	print F "#yaboot.conf - generated by DrakX";
	print F qq(init-message="\\n$bootloader->{'init-message'}\\n") if $bootloader->{'init-message'};

	if ($bootloader->{boot}) {
	    print F "boot=$bootloader->{boot}";
	    my $of_dev = get_of_dev($bootloader->{boot});
	    print F "ofboot=$of_dev";
	} else {
	    die "no bootstrap partition defined."
	}
	
	$bootloader->{$_} and print F "$_=$bootloader->{$_}" foreach qw(delay timeout);
	print F "install=/usr/lib/yaboot/yaboot";
	print F "magicboot=/usr/lib/yaboot/ofboot";
	$bootloader->{$_} and print F $_ foreach qw(enablecdboot enableofboot);
	$bootloader->{$_} and print F "$_=$bootloader->{$_}" foreach qw(defaultos default);
	#- print F "nonvram";
	my $boot = "/dev/" . $bootloader->{useboot} if $bootloader->{useboot};
		
	foreach (@{$bootloader->{entries}}) {

	    if ($_->{type} eq "image") {
		my $of_dev = '';
		if ($boot !~ /$_->{root}/ && $boot) {
		    $of_dev = get_of_dev($boot);
		    print F "$_->{type}=$of_dev," . substr($_->{kernel_or_dev}, 5);
		} else {
		    $of_dev = get_of_dev($_->{root});    			
		    print F "$_->{type}=$of_dev,$_->{kernel_or_dev}";
		}
		print F "\tlabel=", make_label_lilo_compatible($_->{label});
		print F "\troot=$_->{root}";
		if ($boot !~ /$_->{root}/ && $boot) {
		    print F "\tinitrd=$of_dev," . substr($_->{initrd}, 5) if $_->{initrd};
		} else {
		    print F "\tinitrd=$of_dev,$_->{initrd}" if $_->{initrd};
		}
		#- xfs module on PPC requires larger initrd - say 6MB?
		print F "\tinitrd-size=6144" if $bootloader->{xfsroot};
		print F qq(\tappend=" $_->{append}") if $_->{append};
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
    my $of_dev = get_of_dev($bootloader->{boot});
    output($f, "$of_dev\n");  
    $::testing and return;
    if (defined $install_steps_interactive::new_bootstrap) {
	run_program::run("hformat", $bootloader->{boot}) or die "hformat failed";
    }	
    my $error;
    run_program::rooted($::prefix, "/usr/sbin/ybin", "2>", \$error) or die "ybin failed: $error";
}


sub make_label_lilo_compatible {
    my ($label) = @_; 
    $label = substr($label, 0, 31); #- lilo doesn't handle more than 31 char long labels
    $label =~ s/ /_/g; #- lilo does not support blank character in image names, labels or aliases
    qq("$label");
}

sub write_lilo_conf {
    my ($bootloader, $fstab, $hds) = @_;
    $bootloader->{prompt} = $bootloader->{timeout};

    my $file2fullname = sub {
	my ($file) = @_;
	if (arch() =~ /ia64/) {
	    (my $part, $file) = fsedit::file2part($fstab, $file);
	    my %hds = map_index { $_ => "hd$::i" } map { $_->{device} } 
	      sort { isFat($b) <=> isFat($a) || $a->{device} cmp $b->{device} } fsedit::get_fstab(@$hds);
	    $hds{$part->{device}} . ":" . $file;
	} else {
	    $file
	}
    };

    my %bios2dev = map_index { $::i => $_ } dev2bios($hds, $bootloader->{first_hd_device} || $bootloader->{boot});
    my %dev2bios = reverse %bios2dev;

    if (is_empty_hash_ref($bootloader->{bios} ||= {})) {
	my $dev = $hds->[0]{device};
	if ($dev2bios{$dev}) {
	    log::l("Since we're booting on $bios2dev{0}, make it bios=0x80, whereas $dev is now " . (0x80 + $dev2bios{$dev}));
	    $bootloader->{bios}{"/dev/$bios2dev{0}"} = '0x80';
	    $bootloader->{bios}{"/dev/$dev"} = sprintf("0x%x", 0x80 + $dev2bios{$dev});
	}
	foreach (0 .. 3) {
	    my ($letter) = $bios2dev{$_} =~ /hd([^ac])/; #- at least hda and hdc are handled correctly :-/
	    next if $bootloader->{bios}{"/dev/$bios2dev{$_}"} || !$letter;
	    next if 
	      $_ > 0	     #- always print if first disk is hdb, hdd, hde...
		&& $bios2dev{$_ - 1} eq "hd" . chr(ord($letter) - 1);
	    #- no need to help lilo with hdb (resp. hdd, hdf...)
	    log::l("Helping lilo: $bios2dev{$_} must be " . (0x80 + $_));
	    $bootloader->{bios}{"/dev/$bios2dev{$_}"} = sprintf("0x%x", 0x80 + $_);
	}
    }

    {
        local $\ = "\n";
	my $f = arch() =~ /ia64/ ? "$::prefix/boot/efi/elilo.conf" : "$::prefix/etc/lilo.conf";

	open(my $F, ">$f") or die "cannot create lilo config file: $f";
	log::l("writing lilo config to $f");

	chmod 0600, $f if $bootloader->{password};

	#- normalize: RESTRICTED is only valid if PASSWORD is set
	delete $bootloader->{restricted} if !$bootloader->{password};

	if (every { $_->{label} ne $bootloader->{default} } @{$bootloader->{entries}}) {
	    log::l("default bootloader entry $bootloader->{default} is invalid, choose another one");
	    $bootloader->{default} = $bootloader->{entries}[0]{label};
	}
	local $bootloader->{default} = make_label_lilo_compatible($bootloader->{default});
	print $F "# File generated by DrakX/drakboot";
	print $F "# WARNING: do not forget to run lilo after modifying this file\n";
	$bootloader->{$_} and print $F "$_=$bootloader->{$_}" foreach qw(boot map install vga default keytable);
	$bootloader->{$_} and print $F $_ foreach qw(linear geometric compact prompt nowarn restricted);
	print $F qq(append="$bootloader->{append}") if $bootloader->{append};
 	print $F "password=", $bootloader->{password} if $bootloader->{password}; #- also done by msec
	print $F "timeout=", round(10 * $bootloader->{timeout}) if $bootloader->{timeout};
	print $F "serial=", $1 if get_append($bootloader, 'console') =~ /ttyS(.*)/;

	print $F "message=/boot/message" if arch() !~ /ia64/;
	print $F "menu-scheme=wb:bw:wb:bw" if arch() !~ /ia64/;

	print $F "ignore-table" if any { $_->{unsafe} && $_->{table} } @{$bootloader->{entries}};

	while (my ($dev, $bios) = each %{$bootloader->{bios}}) {
	    print $F "disk=$dev bios=$bios";
	}

	foreach (@{$bootloader->{entries}}) {
	    print $F "$_->{type}=", $file2fullname->($_->{kernel_or_dev});
	    print $F "\tlabel=", make_label_lilo_compatible($_->{label});

	    if ($_->{type} eq "image") {		
		print $F "\troot=$_->{root}" if $_->{root};
		print $F "\tinitrd=", $file2fullname->($_->{initrd}) if $_->{initrd};
		print $F qq(\tappend="$_->{append}") if $_->{append};
		print $F "\tvga=$_->{vga}" if $_->{vga};
		print $F "\tread-write" if $_->{'read-write'};
		print $F "\tread-only" if !$_->{'read-write'};
	    } else {
		print $F "\ttable=$_->{table}" if $_->{table};
		print $F "\tunsafe" if $_->{unsafe} && !$_->{table};
		
		if (my ($dev) = $_->{table} =~ m|/dev/(.*)|) {
		    if ($dev2bios{$dev}) {
			#- boot off the nth drive, so reverse the BIOS maps
			my $nb = sprintf("0x%x", 0x80 + $dev2bios{$dev});
			$_->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		    }
		}
		while (my ($from, $to) = each %{$_->{mapdrive} || {}}) {
		    print $F "\tmap-drive=$from";
		    print $F "\t   to=$to";
		}
	    }
	}
    }
}

sub install_lilo {
    my ($bootloader, $fstab, $hds, $method) = @_;

    if (my ($install) = $method =~ /lilo-(text|menu)/) {
	$bootloader->{install} = $install;
    } else {
	delete $bootloader->{install};
    }
    output("$::prefix/boot/message-text", $bootloader->{message}) if $bootloader->{message};
    symlinkf "message-" . ($method ne 'lilo-graphic' ? 'text' : 'graphic'), "$::prefix/boot/message";

    write_lilo_conf($bootloader, $fstab, $hds);

    if (!$::testing && arch() !~ /ia64/ && $bootloader->{method} =~ /lilo/) {
	log::l("Installing boot loader on $bootloader->{boot}...");
	my $error;
	run_program::rooted($::prefix, "lilo", "2>", \$error) or die "lilo failed: $error";
    }
}

sub dev2bios {
    my ($hds, $where) = @_;
    $where =~ s|/dev/||;
    my @dev = map { $_->{device} } @$hds;
    member($where, @dev) or ($where) = @dev; #- if not on mbr, 

    s/h(d[e-g])/x$1/ foreach $where, @dev; #- emulates ultra66 as xd_

    my $start = substr($where, 0, 2);

    my $translate = sub {
	my ($dev) = @_;
	$dev eq $where ? "aaa" : #- if exact match, value it first
	  $dev =~ /^$start(.*)/ ? "ad$1" : #- if same class (ide/scsi/ultra66), value it before other classes
	  $dev;
    };
    @dev = map { $_->[0] }
           sort { $a->[1] cmp $b->[1] }
	   map { [ $_, $translate->($_) ] } @dev;

    s/x(d.)/h$1/ foreach @dev; #- switch back;

    @dev;
}

sub dev2grub {
    my ($dev, $dev2bios) = @_;
    $dev =~ m|^(/dev/)?(...)(.*)$| or die "dev2grub (bad device $dev), caller is " . join(":", caller());
    my $grub = $dev2bios->{$2} or die "dev2grub ($2)";
    "($grub" . ($3 && "," . ($3 - 1)) . ")";
}

sub read_grub_device_map() {
    my %grub2dev = map { m!\((.*)\) /dev/(.*)$! } cat_("$::prefix/boot/grub/device.map");
    \%grub2dev;
}

sub grub2dev {
    my ($grub_file, $o_block_device) = @_;
    my ($grub_dev, $rel_file) = $grub_file =~ m!\((.*?)\)/?(.*)! or return;
    my ($hd, $part) = split(',', $grub_dev);
    $part = $o_block_device ? '' : defined $part && $part + 1; #- grub wants "(hdX,Y)" where lilo just want "hdY+1"
    my $device = '/dev/' . read_grub_device_map()->{$hd} . $part;
    wantarray() ? ($device, $rel_file) : $device;
}

# replace dummy "(hdX,Y)" in "(hdX,Y)/boot/vmlinuz..." by appropriate path if needed
sub ungrubify {
    my ($grub_file, $mnt_pts) = @_;
    my ($device, $rel_file) = grub2dev($grub_file) or return $grub_file;
    ($mnt_pts->{$device} || '') . '/' . $rel_file;
}

sub write_grub_config {
    my ($bootloader, $fstab, $hds) = @_;
    my %dev2bios = (
      (map_index { $_ => "fd$::i" } detect_devices::floppies_dev()),
      (map_index { $_ => "hd$::i" } dev2bios($hds, $bootloader->{first_hd_device} || $bootloader->{boot})),
    );

    {
	my %bios2dev = reverse %dev2bios;
	output "$::prefix/boot/grub/device.map", 
	  join '', map { "($_) /dev/$bios2dev{$_}\n" } sort keys %bios2dev;
    }
    my $file2grub = sub {
	my ($part, $file) = fsedit::file2part($fstab, $_[0], 'keep_simple_symlinks');
	dev2grub($part->{device}, \%dev2bios) . $file;
    };
    {
	my @grub_config;

	$bootloader->{$_} and push @grub_config, "$_ $bootloader->{$_}" foreach qw(timeout);

	push @grub_config, "color black/cyan yellow/cyan";
	push @grub_config, "serial --unit=$1 --speed=$2\nterminal --timeout=" . ($bootloader->{timeout} || 0) . " console serial" if get_append($bootloader, 'console') =~ /ttyS(\d),(\d+)/;

	each_index {
	    push @grub_config, "default $::i" if $_->{label} eq $bootloader->{default};
	} @{$bootloader->{entries}};

	foreach (@{$bootloader->{entries}}) {
	    push @grub_config, "\ntitle $_->{label}";

	    if ($_->{type} eq "image") {
		my $vga = $_->{vga} || $bootloader->{vga};
		push @grub_config, sprintf "kernel %s root=%s %s%s%s",
		  $file2grub->($_->{kernel_or_dev}),
		  $_->{root} =~ /loop7/ ? "707" : $_->{root}, #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
		  $_->{append},
		  $_->{'read-write'} && " rw",
		  $vga && $vga ne "normal" && " vga=$vga";
		push @grub_config, join("", "initrd ", $file2grub->($_->{initrd})) if $_->{initrd};
	    } else {
		push @grub_config, join("", "root ", dev2grub($_->{kernel_or_dev}, \%dev2bios));

		if (my ($dev) = $_->{table} =~ m|/dev/(.*)|) {
		    if ($dev2bios{$dev} =~ /hd([1-9])/) {
			#- boot off the nth drive, so reverse the BIOS maps
			my $nb = sprintf("0x%x", 0x80 + $1);
			$_->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		    }
		}
		if ($_->{mapdrive}) {
		    map_each { push @grub_config, "map ($::b) ($::a)" } %{$_->{mapdrive}};
		    push @grub_config, "makeactive";
		}
		push @grub_config, "chainloader +1";
	    }
	}
	my $f = "$::prefix/boot/grub/menu.lst";
	log::l("writing grub config to $f");
	output($f, join("\n", @grub_config));
    }
    my $dev = dev2grub($bootloader->{boot}, \%dev2bios);
    my ($s1, $s2, $m) = map { $file2grub->("/boot/grub/$_") } qw(stage1 stage2 menu.lst);
    my $f = "/boot/grub/install.sh";
    output "$::prefix$f",
"grub --device-map=/boot/grub/device.map --batch <<EOF
install $s1 d $dev $s2 p $m
quit
EOF
";
   
    check_enough_space();
    $f;
}

sub install_grub {
    my ($bootloader, $fstab, $hds) = @_;

    my $f = write_grub_config($bootloader, $fstab, $hds);

    if (!$::testing) {
	log::l("Installing boot loader...");
	symlink "$::prefix/boot", "/boot";
	my $error;
	run_program::run("sh", $f, "2>", \$error) or die "grub failed: $error";
	unlink "/boot";
    }
}

sub lnx4win_file { 
    my $bootloader = shift;
    map { local $_ = $_; s,/,\\,g; "$bootloader->{boot_drive}:\\lnx4win$_" } @_;
}

sub install {
    my ($bootloader, $fstab, $hds) = @_;

    if (my $p = find { $bootloader->{boot} eq "/dev/$_->{device}" } @$fstab) {
	die N("You can't install the bootloader on a %s partition\n", partition_table::type2fs($p))
	  if isThisFs('xfs', $p);
    }
    $bootloader->{keytable} = keytable($bootloader->{keytable});

    my ($main_method) = $bootloader->{method} =~ /(\w+)/;
    my $f = $bootloader::{"install_$main_method"} or die "unknown bootloader method $bootloader->{method}";
    $f->($bootloader, $fstab, $hds, $bootloader->{method});
}

sub update_for_renumbered_partitions {
    my ($in, $renumbering) = @_;

    my %files = (
		 lilo => '/etc/lilo.conf',
		 grub => '/boot/grub/menu.lst',
		 grub_install => '/boot/grub/install.sh',
		 );

    my %configs = map {
	my $file = "$::prefix/$files{$_}";
	if (-e $file) {
	    my $f = cat_($file);
	    $_ => { orig => $f, new => $f, file => $files{$_} };
	} else { () }
    } keys %files;

    my %dev2grub = $configs{grub} ? do {
	my $grub2dev = read_grub_device_map();
	reverse %$grub2dev;
    } : ();

    foreach (@$renumbering) {
	my ($old, $new) = @$_;
	my ($old_grub, $new_grub) = eval { map { dev2grub($_, \%dev2grub) } $old, $new };
	log::l("renaming $old -> $new  and $old_grub -> $new_grub");
	foreach (values %configs) {
	    $_->{new} =~ s/\b$old/$new/g;
	    $_->{new} =~ s/\Q$old_grub/$new_grub/g if $old_grub;
	}
    }

    any { $_->{orig} ne $_->{new} } values %configs or return 1; # no need to update

    $in->ask_okcancel('', N("Your bootloader configuration must be updated because partition has been renumbered")) or return;

    foreach (values %configs) {
	output("$::prefix/$_->{file}", $_->{new}) if $_->{new} ne $_->{orig};
    }
    if ($configs{lilo} && $configs{lilo}{orig} ne $configs{lilo}{new} && detect_bootloader() =~ /LILO/ ||
	$configs{grub_install} && $configs{grub_install}{orig} ne $configs{grub_install}{new} && detect_bootloader() =~ /GRUB/) {
	$in->ask_warn('', N("The bootloader can't be installed correctly. You have to boot rescue and choose \"%s\"", 
			    N("Re-install Boot Loader")));
    }
    1;
}

1;
