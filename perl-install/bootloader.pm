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


#-#####################################################################################
#- Functions
#-#####################################################################################
my $vmlinuz_regexp = 'vmlinuz';
my $decompose_vmlinuz_name = qr/((?:$vmlinuz_regexp).*)-(\d+\.\d+.*)/;

sub expand_vmlinuz_symlink {
    my ($vmlinuz) = @_;
    my $f = $::prefix . ($vmlinuz =~ m!^/! ? $vmlinuz : "/boot/$vmlinuz");
    -l $f ? readlink($f) : $vmlinuz;
}

sub installed_vmlinuz_raw() { grep { /^($vmlinuz_regexp)/ } all("$::prefix/boot") }
sub installed_vmlinuz() { grep { ! -l "$::prefix/boot/$_" } installed_vmlinuz_raw() }
sub vmlinuz2version {
    my ($vmlinuz) = @_;
    expand_vmlinuz_symlink($vmlinuz) =~ /$decompose_vmlinuz_name/ && $2;
}
sub vmlinuz2basename {
    my ($vmlinuz) = @_;
    expand_vmlinuz_symlink($vmlinuz) =~ /$decompose_vmlinuz_name/ && $1;
}
sub basename2initrd_basename {
    my ($basename) = @_;
    $basename =~ s!vmlinuz-?!!; #- here we don't use $vmlinuz_regexp since we explictly want to keep all that is not "vmlinuz"
    'initrd' . ($basename ? "-$basename" : '');    
}
sub kernel_str2vmlinuz_long {
    my ($kernel) = @_;
    $kernel->{basename} . '-' . $kernel->{version};
}
sub kernel_str2initrd_long {
    my ($kernel) = @_;
    basename2initrd_basename($kernel->{basename}) . '-' . $kernel->{version} . '.img';
}
sub kernel_str2vmlinuz_short {
    my ($kernel) = @_;
    if ($kernel->{use_long_name}) {
	kernel_str2vmlinuz_long($kernel);
    } else {
	my $ext = $kernel->{ext} ? "-$kernel->{ext}" : '';
	$kernel->{basename} . $ext;
    }
}
sub kernel_str2initrd_short {
    my ($kernel) = @_;
    if ($kernel->{use_long_name}) {
	kernel_str2initrd_long($kernel);
    } else {
	my $ext = $kernel->{ext} ? "-$kernel->{ext}" : '';
	basename2initrd_basename($kernel->{basename}) . $ext . '.img';
    }
}

sub vmlinuz2kernel_str {
    my ($vmlinuz) = @_;
    my ($basename, $version) = expand_vmlinuz_symlink($vmlinuz) =~ /$decompose_vmlinuz_name/ or return;
    { 
	basename => $basename,
	version => $version, 
	$version =~ /(.*mdk)-?(.*)/ ? (ext => $2, version_no_ext => $1) : (version_no_ext => $version),
    };
}
sub kernel_str2label {
    my ($kernel, $o_use_long_name) = @_;
    $o_use_long_name || $kernel->{use_long_name} ?
      sanitize_ver("linux-$kernel->{version}") : 
        $kernel->{ext} ? "linux$kernel->{ext}" : 'linux';
}

sub get {
    my ($vmlinuz, $bootloader) = @_;
    $_->{kernel_or_dev} && $_->{kernel_or_dev} eq $vmlinuz and return $_ foreach @{$bootloader->{entries}};
    undef;
}
sub get_label {
    my ($label, $bootloader) = @_;
    $_->{label} && lc(make_label_lilo_compatible($_->{label})) eq lc(make_label_lilo_compatible($label)) and return $_ foreach @{$bootloader->{entries}};
    undef;
}

sub mkinitrd {
    my ($kernel_version, $initrd, $o_vga) = @_;

    $::testing || -e "$::prefix/$initrd" and return 1;

    my $loop_boot = loopback::prepare_boot();

    my $o_resolution = $o_vga && do {
	require Xconfig::resolution_and_depth;
	my $res = Xconfig::resolution_and_depth::from_bios($o_vga);
	$res && $res->{X};
    };
    modules::load('loop');
    if (!run_program::rooted($::prefix, "mkinitrd", "-v", "-f", $initrd, "--ifneeded", $kernel_version, if_($o_resolution, '--splash' => $o_resolution))) {
	unlink("$::prefix/$initrd");
	die "mkinitrd failed";
    }
    loopback::save_boot($loop_boot);

    -e "$::prefix/$initrd";
}

sub read {
    my ($fstab) = @_;
    my @methods = method_choices_raw();
    foreach my $main_method (uniq(map { main_method($_) } @methods)) {
	my $f = $bootloader::{"read_$main_method"} or die "unknown bootloader method $main_method (read)";
	my $bootloader = $f->($fstab);
	my $type = partition_table::raw::typeOfMBR($bootloader->{boot});
	if ($type eq $main_method) {
	    return $bootloader;
	}
    }
}

sub read_grub {
    my ($fstab) = @_;
    my $global = 1;
    my ($e, %b);

    my $grub2dev = read_grub_device_map();

    my $menu_lst_file = "$::prefix/boot/grub/menu.lst";
    -e $menu_lst_file or return;

    foreach (cat_($menu_lst_file)) {
        chomp;
	s/^\s*//; s/\s*$//;
        next if /^#/ || /^$/;
	my ($keyword, $v) = split(' ', $_, 2) or
	  warn qq(unknown line in /boot/grub/menu.lst: "$_"\n), next;

        if ($keyword eq 'title') {
            push @{$b{entries}}, $e = { label => $v };
            $global = 0;
        } elsif ($global) {
            $b{$keyword} = $v eq '' ? 1 : grub2file($v, $grub2dev, $fstab);
        } else {
            if ($keyword eq 'kernel') {
                $e->{type} = 'image';
                (my $kernel, $e->{append}) = split(' ', $v, 2);
		$e->{root} = $1 if $e->{append} =~ s/root=(\S*)\s*//;
		$e->{kernel_or_dev} = grub2file($kernel, $grub2dev, $fstab);
            } elsif ($keyword eq 'root') {
                $e->{type} = 'other';
		if ($v =~ /,/) {
		    $e->{table} = grub2dev($v, $grub2dev, 1);
		} else {
		    $e->{unsafe} = 1;
		}
                $e->{kernel_or_dev} = grub2dev($v, $grub2dev);
                $e->{append} = "";
            } elsif ($keyword eq 'initrd') {
                $e->{initrd} = grub2file($v, $grub2dev, $fstab);
            }
        }
    }
    foreach (cat_("$::prefix/boot/grub/install.sh")) {
        $b{boot} = grub2dev($1, $grub2dev) if /\s+d\s+(\(.*?\))/;
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
    $b{method} = 'grub';

    \%b;
}

sub read_yaboot() { &read_lilo }
sub read_lilo() {
    my $file = sprintf("$::prefix/etc/%s.conf", arch() =~ /ppc/ ? 'yaboot' : 'lilo');
    my $global = 1;
    my ($e, $v);
    my %b;
    -e $file or return;
    foreach (cat_($file)) {
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
	$b{method} = 'lilo-' . (member($b{install}, 'text', 'menu', 'graphic') ? $b{install} : 'graphic');
	delete $b{message};
    }

    if (my $default = find { $_ && $_->{append} } get_label($b{default}, \%b), @{$b{entries}}) {
	$b{perImageAppend} ||= $default->{append};
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
    my $label = $v->{label};
    for (my $i = 0; $i < 10;) {
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

	my $new_label = $v->{label} eq 'linux' && kernel_str2label(vmlinuz2kernel_str($to_add->{kernel_or_dev}), 'use_long_name');
	$label = $new_label && $label ne $new_label ? $new_label : 'old' . ($i++ ? $i : '') . "_$label";
    }
    die 'add_entry';
}

sub _do_the_symlink {
    my ($bootloader, $entry, $kind, $long_name) = @_;

    my $existing_link = readlink("$::prefix$entry->{$kind}");
    if ($existing_link && $existing_link eq $long_name) {
	#- nothing to do :)
	return;
    }

    #- the symlink is going to change! 
    #- replace all the {$kind} using this symlink to the real file
    my $old_long_name = $existing_link =~ m!^/! ? $existing_link : "/boot/$existing_link";
    if (-e "$::prefix$old_long_name") {
	foreach (@{$bootloader->{entries}}) {
	    $_->{$kind} eq $entry->{$kind} && $_->{label} ne 'failsafe' or next;
	    log::l("replacing $_->{$kind} with $old_long_name for bootloader label $_->{labe}");
	    $_->{$kind} = $old_long_name;
	}
    } else {
	log::l("ERROR: $entry->{$kind} points to $old_long_name which doesn't exist");
    }

    #- changing the symlink
    symlinkf($long_name, "$::prefix$entry->{$kind}")
      or cp_af("$::prefix/boot/$long_name", "$::prefix$entry->{$kind}");
}

sub add_kernel {
    my ($bootloader, $kernel_str, $nolink, $v) = @_;

    #- new versions of yaboot don't handle symlinks
    $nolink ||= arch() =~ /ppc/;

    $nolink ||= $kernel_str->{use_long_name};

    my $vmlinuz_long = kernel_str2vmlinuz_long($kernel_str);
    $v->{kernel_or_dev} = "/boot/$vmlinuz_long";
    -e "$::prefix$v->{kernel_or_dev}" or log::l("unable to find kernel image $::prefix$v->{kernel_or_dev}"), return;
    if (!$nolink) {
	$v->{kernel_or_dev} = '/boot/' . kernel_str2vmlinuz_short($kernel_str);
	_do_the_symlink($bootloader, $v, 'kernel_or_dev', $vmlinuz_long);
    }
    log::l("adding $v->{kernel_or_dev}");

    my $initrd_long = kernel_str2initrd_long($kernel_str);
    $v->{initrd} = "/boot/$initrd_long";
    mkinitrd($kernel_str->{version}, $v->{initrd}, $v->{vga}) or undef $v->{initrd};
    if ($v->{initrd} && !$nolink) {
	$v->{initrd} = '/boot/' . kernel_str2initrd_short($kernel_str);
	_do_the_symlink($bootloader, $v, 'initrd', $initrd_long);
    }

    add2hash($v,
	     {
	      type => 'image',
	      label => kernel_str2label($kernel_str),
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
    $entry->{type} eq 'image' or return;

    if (my $kernel_str = vmlinuz2kernel_str($entry->{kernel_or_dev})) {
	$entry->{initrd} ||= '/boot/' . kernel_str2initrd_short($kernel_str);
	mkinitrd($kernel_str->{version}, $entry->{initrd}, $entry->{vga}) or undef $entry->{initrd};
    }
}

sub get_kernels_and_labels {
    my ($b_prefer_24) = @_;

    my @kernels = installed_vmlinuz();
    
    require pkgs;
    my @kernels_str = 
      sort { c::rpmvercmp($b->{version_no_ext}, $a->{version_no_ext}) } 
      grep { -d "$::prefix/lib/modules/$_->{version}" }
      map { vmlinuz2kernel_str($_) } @kernels;

    if ($b_prefer_24) {
	my ($kernel_24, $other) = partition { $_->{ext} eq '' && $_->{version} =~ /^\Q2.4/ } @kernels_str;
	@kernels_str = (@$kernel_24, @$other);
    }

    $kernels_str[0]{ext} = '';

    my %labels;
    foreach (@kernels_str) {
	if ($labels{$_->{ext}}) {
	    $_->{use_long_name} = 1;
	} else {
	    $labels{$_->{ext}} = 1;
	}
    }
    @kernels_str;
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

    $return;
}

sub suggest {
    my ($bootloader, $hds, %options) = @_;
    my $fstab = [ fsedit::get_fstab(@$hds) ];
    my $root_part = fsedit::get_root($fstab);
    my $root = '/dev/' . (isLoopback($root_part) ? 'loop7' : $root_part->{device});
    my $boot = fsedit::get_root($fstab, 'boot')->{device};
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
	 color => 'black/cyan yellow/cyan',
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

    my @kernels = get_kernels_and_labels() or die "no kernel installed";

    foreach my $kernel (@kernels) {
	add_kernel($bootloader, $kernel, 0,
	       {
		root => $root,
		if_($options{vga_fb} && $kernel->{ext} eq '', vga => $options{vga_fb}), #- using framebuffer
		if_($options{vga_fb} && $options{quiet}, append => "splash=silent"),
	       });

	if ($options{vga_fb} && $kernel->{ext} eq '') {
	    add_kernel($bootloader, $kernel, 0, { root => $root, label => 'linux-nonfb' });
	}
    }

    #- remove existing libsafe, don't care if the previous one was modified by the user?
    @{$bootloader->{entries}} = grep { $_->{label} ne 'failsafe' } @{$bootloader->{entries}};

    add_kernel($bootloader, $kernels[0], 0,
	       { root => $root, label => 'failsafe', append => 'devfs=nomount failsafe' });

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
	my @windows_boot_parts =
	  grep { isFat_or_NTFS($_) && isFat_or_NTFS({ type => fsedit::typeOfPart($_->{device}) }) }
	    map { @{$_->{primary}{normal}} } @$hds;
	each_index {
	    add_entry($bootloader,
		      {
		       type => 'other',
		       kernel_or_dev => "/dev/$_->{device}",
		       label => 'windows' . ($::i || ''),
		       table => "/dev/$_->{rootDevice}"
		      });
	} @windows_boot_parts;
    }

    my @preferred = map { "linux-$_" } 'p3-smp-64GB', 'secure', 'enterprise', 'smp', 'i686-up-4GB';
    if (my $preferred = find { get_label($_, $bootloader) } @preferred) {
	$bootloader->{default} ||= $preferred;
    }
    $bootloader->{default} ||= "linux";
    $bootloader->{method} ||= first(method_choices($fstab));
}

sub detect_main_method {
    my ($fstab) = @_;
    my $bootloader = &read($fstab);
    $bootloader && main_method($bootloader->{method});
}

sub main_method {
    my ($method) = @_;
    $method =~ /(\w+)/ && $1;
}

sub method2text {
    my ($method) = @_;
    +{
	'lilo-graphic' => N("LILO with graphical menu"),
	'lilo-menu'    => N("LILO with text menu"),
	'grub'         => N("Grub"),
	'yaboot'       => N("Yaboot"),
    }->{$method};
}

sub method_choices_raw() {
    arch() =~ /ppc/ ? 'yaboot' : 
      (
       if_(whereis_binary('lilo'), 'lilo-graphic', 'lilo-menu'),
       if_(whereis_binary('grub'), 'grub'),
      );
}
sub method_choices {
    my ($fstab) = @_;

    grep {
	!(/lilo/ && isLoopback(fsedit::get_root($fstab)))
	  && !(/lilo-graphic/ && detect_devices::matching_desc('ProSavageDDR'))
	  && !(/grub/ && isRAID(fsedit::get_root($fstab)));
    } method_choices_raw();
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
    my ($bootloader, $_hds) = @_;
    $bootloader->{prompt} = $bootloader->{timeout};

    if ($bootloader->{message}) {
	eval { output("$::prefix/boot/message", $bootloader->{message}) }
	  or $bootloader->{message} = 0;
    }
    {
	my @conf;
	push @conf, "#yaboot.conf - generated by DrakX";
	push @conf, qq(init-message="\\n$bootloader->{'init-message'}\\n") if $bootloader->{'init-message'};

	if ($bootloader->{boot}) {
	    push @conf, "boot=$bootloader->{boot}";
	    push @conf, "ofboot=", get_of_dev($bootloader->{boot})
	} else {
	    die "no bootstrap partition defined."
	}
	
	push @conf, map { "$_=$bootloader->{$_}" } grep { $bootloader->{$_} } qw(delay timeout defaultos default);
	push @conf, "install=/usr/lib/yaboot/yaboot";
	push @conf, "magicboot=/usr/lib/yaboot/ofboot";
	push @conf, grep { $bootloader->{$_} } qw(enablecdboot enableofboot);
	#- push @conf, "nonvram";
	my $boot = "/dev/" . $bootloader->{useboot} if $bootloader->{useboot};
		
	foreach (@{$bootloader->{entries}}) {

	    if ($_->{type} eq "image") {
		my $of_dev = '';
		if ($boot !~ /$_->{root}/ && $boot) {
		    $of_dev = get_of_dev($boot);
		    push @conf, "$_->{type}=$of_dev," . substr($_->{kernel_or_dev}, 5);
		} else {
		    $of_dev = get_of_dev($_->{root});    			
		    push @conf, "$_->{type}=$of_dev,$_->{kernel_or_dev}";
		}
		push @conf, "\tlabel=", make_label_lilo_compatible($_->{label});
		push @conf, "\troot=$_->{root}";
		if ($boot !~ /$_->{root}/ && $boot) {
		    push @conf, "\tinitrd=$of_dev," . substr($_->{initrd}, 5) if $_->{initrd};
		} else {
		    push @conf, "\tinitrd=$of_dev,$_->{initrd}" if $_->{initrd};
		}
		#- xfs module on PPC requires larger initrd - say 6MB?
		push @conf, "\tinitrd-size=6144" if $bootloader->{xfsroot};
		push @conf, qq(\tappend=" $_->{append}") if $_->{append};
		push @conf, "\tread-write" if $_->{'read-write'};
		push @conf, "\tread-only" if !$_->{'read-write'};
	    } else {
		my $of_dev = get_of_dev($_->{kernel_or_dev});
		push @conf, "$_->{label}=$of_dev";		
	    }
	}
	my $f = "$::prefix/etc/yaboot.conf";
	log::l("writing yaboot config to $f");
	output($f, map { "$_\n" } @conf);
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
    my ($bootloader, $hds) = @_;
    $bootloader->{prompt} = $bootloader->{timeout};

    my $file2fullname = sub {
	my ($file) = @_;
	if (arch() =~ /ia64/) {
	    my $fstab = [ fsedit::get_fstab(@$hds) ];
	    (my $part, $file) = fsedit::file2part($fstab, $file);
	    my %hds = map_index { $_ => "hd$::i" } map { $_->{device} } 
	      sort { isFat($b) <=> isFat($a) || $a->{device} cmp $b->{device} } @$fstab;
	    $hds{$part->{device}} . ":" . $file;
	} else {
	    $file
	}
    };

    my @sorted_hds = sort_hds_according_to_bios($bootloader, $hds);

    if (is_empty_hash_ref($bootloader->{bios} ||= {}) && $hds->[0] != $sorted_hds[0]) {
	log::l("Since we're booting on $sorted_hds[0]{device}, make it bios=0x80");
	$bootloader->{bios} = { "/dev/$sorted_hds[0]{device}" => '0x80' };
    }

    my @conf;

    #- normalize: RESTRICTED is only valid if PASSWORD is set
    delete $bootloader->{restricted} if !$bootloader->{password};

    if (every { $_->{label} ne $bootloader->{default} } @{$bootloader->{entries}}) {
	log::l("default bootloader entry $bootloader->{default} is invalid, choose another one");
	$bootloader->{default} = $bootloader->{entries}[0]{label};
    }
    push @conf, "# File generated by DrakX/drakboot";
    push @conf, "# WARNING: do not forget to run lilo after modifying this file\n";
    push @conf, "default=" . make_label_lilo_compatible($bootloader->{default}) if $bootloader->{default};
    push @conf, map { "$_=$bootloader->{$_}" } grep { $bootloader->{$_} } qw(boot map install vga keytable);
    push @conf, grep { $bootloader->{$_} } qw(linear geometric compact prompt nowarn restricted);
    push @conf, qq(append="$bootloader->{append}") if $bootloader->{append};
    push @conf, "password=" . $bootloader->{password} if $bootloader->{password}; #- also done by msec
    push @conf, "timeout=" . round(10 * $bootloader->{timeout}) if $bootloader->{timeout};
    push @conf, "serial=" . $1 if get_append($bootloader, 'console') =~ /ttyS(.*)/;
    
    push @conf, "message=/boot/message" if arch() !~ /ia64/;
    push @conf, "menu-scheme=wb:bw:wb:bw" if arch() !~ /ia64/;

    push @conf, "ignore-table" if any { $_->{unsafe} && $_->{table} } @{$bootloader->{entries}};

    push @conf, map_each { "disk=$::a bios=$::b" } %{$bootloader->{bios}};

    foreach (@{$bootloader->{entries}}) {
	push @conf, "$_->{type}=" . $file2fullname->($_->{kernel_or_dev});
	push @conf, "\tlabel=" . make_label_lilo_compatible($_->{label});

	if ($_->{type} eq "image") {		
	    push @conf, "\troot=$_->{root}" if $_->{root};
	    push @conf, "\tinitrd=" . $file2fullname->($_->{initrd}) if $_->{initrd};
	    push @conf, qq(\tappend="$_->{append}") if $_->{append};
	    push @conf, "\tvga=$_->{vga}" if $_->{vga};
	    push @conf, "\tread-write" if $_->{'read-write'};
	    push @conf, "\tread-only" if !$_->{'read-write'};
	} else {
	    push @conf, "\ttable=$_->{table}" if $_->{table};
	    push @conf, "\tunsafe" if $_->{unsafe} && !$_->{table};
		
	    if ($_->{table}) {
		my $hd = fs::device2part($_->{table}, $hds);
		if ($hd != $sorted_hds[0]) {		       
		    #- boot off the nth drive, so reverse the BIOS maps
		    my $nb = sprintf("0x%x", 0x80 + (find_index { $hd == $_ } @sorted_hds));
		    $_->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		}
	    }
	    while (my ($from, $to) = each %{$_->{mapdrive} || {}}) {
		push @conf, "\tmap-drive=$from";
		push @conf, "\t   to=$to";
	    }
	}
    }
    my $f = arch() =~ /ia64/ ? "$::prefix/boot/efi/elilo.conf" : "$::prefix/etc/lilo.conf";

    log::l("writing lilo config to $f");
    output_with_perm($f, $bootloader->{password} ? 0600 : 0644, map { "$_\n" } @conf);
}

sub install_lilo {
    my ($bootloader, $hds, $method) = @_;

    if (my ($install) = $method =~ /lilo-(text|menu)/) {
	$bootloader->{install} = $install;
    } else {
	delete $bootloader->{install};
    }
    output("$::prefix/boot/message-text", $bootloader->{message}) if $bootloader->{message};
    symlinkf "message-" . ($method ne 'lilo-graphic' ? 'text' : 'graphic'), "$::prefix/boot/message";

    write_lilo_conf($bootloader, $hds);

    if (!$::testing && arch() !~ /ia64/ && $bootloader->{method} =~ /lilo/) {
	log::l("Installing boot loader on $bootloader->{boot}...");
	my $error;
	run_program::rooted($::prefix, "lilo", "2>", \$error) or die "lilo failed: $error";
    }
}

#- NB: ide is lower than scsi, this is important for sort_hds_according_to_bios()
sub hd2bios_kind {
    my ($hd) = @_;
    lc(join('_', $hd->{bus}, $hd->{host}));
}

sub mixed_kind_of_disks {
    my ($hds) = @_;
    (uniq_ { hd2bios_kind($_) } @$hds) > 1;
}

sub sort_hds_according_to_bios {
    my ($bootloader, $hds) = @_;
    my $boot_hd = fs::device2part($bootloader->{first_hd_device} || $bootloader->{boot}, $hds) or die "sort_hds_according_to_bios: unknown hd"; #- if not on mbr
    my $boot_kind = hd2bios_kind($boot_hd);

    my $translate = sub {
	my ($hd) = @_;
	my $kind = hd2bios_kind($hd);
	($hd == $boot_hd ? 0 : $kind eq $boot_kind ? 1 : 2) . "_$kind";
    };
    sort { $translate->($a) cmp $translate->($b) } @$hds;
}

sub device_string2grub {
    my ($dev, $legacy_floppies, $sorted_hds) = @_;
    if (my $device = fs::device2part($dev, [ @$sorted_hds, fsedit::get_fstab(@$sorted_hds) ])) {
	device2grub($device, $sorted_hds);
    } elsif (my $floppy = fs::device2part($dev, @$legacy_floppies)) {
	my $bios = find_index { $floppy eq $_ } @$legacy_floppies;
	"(fd$bios)";
    } else {
	internal_error("unknown device $dev");
    }
}
sub device2grub {
    my ($device, $sorted_hds) = @_;
    my ($hd, $part_nb) = 
      $device->{rootDevice} ?
	(fs::device2part($device->{rootDevice}, $sorted_hds), $device->{device} =~ /(\d+)$/) :
	$device;
    my $bios = find_index { $hd eq $_ } @$sorted_hds;
    my $part_string = defined $part_nb ? ',' . ($part_nb - 1) : '';    
    "(hd$bios$part_string)";
}

sub read_grub_device_map() {
    my %grub2dev = map { m!\((.*)\) /dev/(.*)$! } cat_("$::prefix/boot/grub/device.map");
    \%grub2dev;
}
sub write_grub_device_map {
    my ($legacy_floppies, $sorted_hds) = @_;
    output("$::prefix/boot/grub/device.map",
	   (map_index { "(fd$::i) /dev/$_->{device}\n" } @$legacy_floppies),
	   (map_index { "(hd$::i) /dev/$_->{device}\n" } @$sorted_hds));
}

sub grub2dev_and_file {
    my ($grub_file, $grub2dev, $o_block_device) = @_;
    my ($grub_dev, $rel_file) = $grub_file =~ m!\((.*?)\)/?(.*)! or return;
    my ($hd, $part) = split(',', $grub_dev);
    $part = $o_block_device ? '' : defined $part && $part + 1; #- grub wants "(hdX,Y)" where lilo just want "hdY+1"
    my $device = '/dev/' . $grub2dev->{$hd} . $part;
    $device, $rel_file;
}
sub grub2dev {
    my ($grub_file, $grub2dev, $o_block_device) = @_;
    first(grub2dev_and_file($grub_file, $grub2dev, $o_block_device));
}

# replace dummy "(hdX,Y)" in "(hdX,Y)/boot/vmlinuz..." by appropriate path if needed
sub grub2file {
    my ($grub_file, $grub2dev, $fstab) = @_;
    if (my ($device, $rel_file) = grub2dev_and_file($grub_file, $grub2dev)) {	
	my $part = fs::device2part($device, $fstab) or log::l("ERROR: unknown device $device (computed from $grub_file)");
	my $mntpoint = $part->{mntpoint} || '';
	($mntpoint eq '/' ? '' : $mntpoint) . '/' . $rel_file;
    } else {
	$grub_file;
    }
}

sub write_grub_config {
    my ($bootloader, $hds) = @_;

    my $fstab = [ fsedit::get_fstab(@$hds) ]; 
    my @legacy_floppies = detect_devices::floppies();
    my @sorted_hds = sort_hds_according_to_bios($bootloader, $hds);

    write_grub_device_map(\@legacy_floppies, \@sorted_hds);

    my $file2grub = sub {
	my ($part, $file) = fsedit::file2part($fstab, $_[0], 'keep_simple_symlinks');
	device2grub($part, \@sorted_hds) . $file;
    };
    {
	my @conf;

	push @conf, map { "$_ $bootloader->{$_}" } grep { $bootloader->{$_} } qw(timeout color);
	push @conf, "serial --unit=$1 --speed=$2\nterminal --timeout=" . ($bootloader->{timeout} || 0) . " console serial" if get_append($bootloader, 'console') =~ /ttyS(\d),(\d+)/;

	eval {
	    push @conf, "default " . (find_index { $_->{label} eq $bootloader->{default} } @{$bootloader->{entries}});
	};

	foreach (@{$bootloader->{entries}}) {
	    push @conf, "\ntitle $_->{label}";

	    if ($_->{type} eq "image") {
		my $vga = $_->{vga} || $bootloader->{vga};
		push @conf, sprintf "kernel %s root=%s %s%s%s",
		  $file2grub->($_->{kernel_or_dev}),
		  $_->{root} =~ /loop7/ ? "707" : $_->{root}, #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
		  $_->{append},
		  $_->{'read-write'} && " rw",
		  $vga && $vga ne "normal" && " vga=$vga";
		push @conf, "initrd " . $file2grub->($_->{initrd}) if $_->{initrd};
	    } else {
		push @conf, "root " . device_string2grub($_->{kernel_or_dev}, \@legacy_floppies, \@sorted_hds);

		if ($_->{table}) {
		    if (my $hd = fs::device2part($_->{table}, \@sorted_hds)) {
			if (my $bios = find_index { $hd eq $_ } @sorted_hds) {
			    #- boot off the nth drive, so reverse the BIOS maps
			    my $nb = sprintf("0x%x", 0x80 + $bios);
			    $_->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
			}
		    }
		}
		if ($_->{mapdrive}) {
		    push @conf, map_each { "map ($::b) ($::a)" } %{$_->{mapdrive}};
		    push @conf, "makeactive";
		}
		push @conf, "chainloader +1";
	    }
	}
	my $f = "$::prefix/boot/grub/menu.lst";
	log::l("writing grub config to $f");
	output("/tmp$f", map { "$_\n" } @conf);
    }
    my $dev = device_string2grub($bootloader->{boot}, \@legacy_floppies, \@sorted_hds);
    my ($stage1, $stage2, $menu_lst) = map { $file2grub->("/boot/grub/$_") } qw(stage1 stage2 menu.lst);
    output "$::prefix/boot/grub/install.sh",
"grub --device-map=/boot/grub/device.map --batch <<EOF
install $stage1 d $dev $stage2 p $menu_lst
quit
EOF
";  

    check_enough_space();
}

sub install_grub {
    my ($bootloader, $hds) = @_;

    write_grub_config($bootloader, $hds);

    if (!$::testing) {
	log::l("Installing boot loader...");
	symlink "$::prefix/boot", "/boot";
	my $error;
	run_program::run("sh", '/boot/grub/install.sh', "2>", \$error) or die "grub failed: $error";
	unlink "/boot";
    }
}

sub install {
    my ($bootloader, $hds) = @_;

    if (my $part = fs::device2part($bootloader->{boot}, [ fsedit::get_fstab(@$hds) ])) {
	die N("You can't install the bootloader on a %s partition\n", partition_table::type2fs($part))
	  if isThisFs('xfs', $part);
    }
    $bootloader->{keytable} = keytable($bootloader->{keytable});

    my $main_method = main_method($bootloader->{method});
    my $f = $bootloader::{"install_$main_method"} or die "unknown bootloader method $bootloader->{method} (install)";
    $f->($bootloader, $hds, $bootloader->{method});
}

sub update_for_renumbered_partitions {
    my ($in, $renumbering, $hds) = @_;

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

    my @sorted_hds; {
 	my $grub2dev = read_grub_device_map();
	map_each {
	    $sorted_hds[$1] = fs::device2part($::b, $hds) if $::a =~ /hd(\d+)/;
	} %$grub2dev;
    };

    foreach (@$renumbering) {
	my ($old, $new) = @$_;
	log::l("renaming $old -> $new");
	$_->{new} =~ s/\b$old/$new/g foreach values %configs;

	$configs{grub} or next;

	my ($old_grub, $new_grub) = map { device_string2grub($_, [], \@sorted_hds) } $old, $new;
	log::l("renaming $old_grub -> $new_grub");
	$_->{new} =~ s/\Q$old_grub/$new_grub/g foreach values %configs;
    }

    any { $_->{orig} ne $_->{new} } values %configs or return 1; # no need to update

    $in->ask_okcancel('', N("Your bootloader configuration must be updated because partition has been renumbered")) or return;

    foreach (values %configs) {
	output("$::prefix/$_->{file}", $_->{new}) if $_->{new} ne $_->{orig};
    }

    my $main_method = detect_main_method([ fsedit::get_fstab(@$hds) ]);
    my @needed = $main_method ? $main_method : ('lilo', 'grub');
    if (find {
	my $config = $_ eq 'grub' ? 'grub_install' : $_;
	$configs{$config} && $configs{$config}{orig} ne $configs{$config}{new};
    } @needed) {
	$in->ask_warn('', N("The bootloader can't be installed correctly. You have to boot rescue and choose \"%s\"", 
			    N("Re-install Boot Loader")));
    }
    1;
}

1;
