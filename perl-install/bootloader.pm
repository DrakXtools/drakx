package bootloader; # $Id$

use diagnostics;
use strict;
use vars qw(%vga_modes);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use partition_table;
use fs::type;
use fs::get;
use log;
use any;
use devices;
use loopback;
use detect_devices;
use partition_table::raw;
use run_program;
use modules;


#-#####################################################################################
#- Functions
#-#####################################################################################
my $vmlinuz_regexp = 'vmlinuz|win4lin';
my $decompose_vmlinuz_name = qr/((?:$vmlinuz_regexp).*?)-(\d+\.\d+.*)/;

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
    my $base = $kernel->{basename} eq 'vmlinuz' ? 'linux' : $kernel->{basename};
    $o_use_long_name || $kernel->{use_long_name} ?
      sanitize_ver("$base-$kernel->{version}") : 
        $kernel->{ext} ? "$base-$kernel->{ext}" : $base;
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
    my ($kernel_version, $entry) = @_;

    my $initrd = $entry->{initrd};
    $::testing || -e "$::prefix/$initrd" and return 1;

    my $loop_boot = loopback::prepare_boot();

    modules::load('loop');
    my @options = (
		   "-v", "-f", $initrd, "--ifneeded", $kernel_version, 
		   if_($entry->{initrd_options}, split(' ', $entry->{initrd_options})),
		  );
    if (!run_program::rooted($::prefix, 'mkinitrd', @options)) {
	unlink("$::prefix/$initrd");
	die "mkinitrd failed:\n(mkinitrd @options))";
    }
    add_boot_splash($entry->{initrd}, $entry->{vga});

    loopback::save_boot($loop_boot);

    -e "$::prefix/$initrd";
}

sub remove_boot_splash {
    my ($initrd) = @_;
    run_program::rooted($::prefix, '/usr/share/bootsplash/scripts/remove-boot-splash', $initrd);
}
sub add_boot_splash {
    my ($initrd, $vga) = @_;

    $vga or return;

    require Xconfig::resolution_and_depth;
    if (my $res = Xconfig::resolution_and_depth::from_bios($vga)) {
	run_program::rooted($::prefix, '/usr/share/bootsplash/scripts/make-boot-splash', $initrd, $res->{X});
    } else {
	log::l("unknown vga bios mode $vga");
    }
}

sub read {
    my ($all_hds) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    my @methods = method_choices_raw();
    foreach my $main_method (uniq(map { main_method($_) } @methods)) {
	my $f = $bootloader::{"read_$main_method"} or die "unknown bootloader method $main_method (read)";
	my $bootloader = $f->($fstab);

	my @devs = $bootloader->{boot};
	if ($bootloader->{'raid-extra-boot'} =~ /mbr/ && 
	    (my $md = fs::get::device2part($bootloader->{boot}, $all_hds->{raids}))) {
	    @devs = map { $_->{rootDevice} } @{$md->{disks}};
	} elsif ($bootloader->{'raid-extra-boot'} =~ m!/dev/!) {
	    @devs = split(',', $bootloader->{'raid-extra-boot'});
	}

	my ($type) = map {
	    if (my $type = partition_table::raw::typeOfMBR($_)) {
		warn "typeOfMBR $type on $_ for method $main_method\n" if $ENV{DEBUG};
		$type;
	    } else { () }
	} @devs;

	if ($type eq $main_method) {
	    my @prefered_entries = map { get_label($_, $bootloader) } $bootloader->{default}, 'linux';

	    if (my $default = find { $_ && $_->{append} } (@prefered_entries, @{$bootloader->{entries}})) {
		$bootloader->{default_vga} = $default->{vga};
		$bootloader->{perImageAppend} ||= $default->{append};
	    }
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

# assumes file is in /boot
sub yaboot2file {
    my ($of_path) = @_;

    #- example of of_path: /pci@f4000000/ata-6@d/disk@0:3,/initrd-2.6.8.1-8mdk.img

    "$::prefix/boot/" . basename($of_path);
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
	    $v = yaboot2file($v) if arch() =~ /ppc/;
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
		if (arch() =~ /ppc/ && $_ eq 'initrd') {
		    $v = yaboot2file($v);
		}
		$e->{$_} = $v || 1 if !member($_, 'read-only');
	    }
	}
    }

    sub remove_quotes_and_spaces {
	local ($_) = @_;
	s/^\s*//; s/\s*$//;
	s/^"(.*?)"$/$1/;
	s/^\s*//; s/\s*$//; #- do it again for append=" foo"
	$_;
    }

    $_->{append} = remove_quotes_and_spaces($_->{append}) foreach \%b, @{$b{entries}};
    $_->{label}  = remove_quotes_and_spaces($_->{label})  foreach @{$b{entries}};
    $b{default} = remove_quotes_and_spaces($b{default}) if $b{default};
    if (arch() =~ /ppc/) {
	$b{method} = 'yaboot';
    } else {
	delete $b{timeout} unless $b{prompt};
	$b{timeout} = $b{timeout} / 10 if $b{timeout};
	$b{method} = 'lilo-' . (member($b{install}, 'text', 'menu', 'graphic') ? $b{install} : 'graphic');
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

sub allowed_boot_parts {
    my ($bootloader, $all_hds) = @_;
    (
     @{$all_hds->{hds}},
     if_($bootloader->{method} =~ /lilo/,
	 grep { $_->{level} eq '1' } @{$all_hds->{raids}}
	),
     (grep { !isFat_or_NTFS($_) } fs::get::hds_fstab(@{$all_hds->{hds}})),
     detect_devices::floppies(),
    );
}

sub same_entries {
    my ($a, $b) = @_;

    foreach (uniq(keys %$a, keys %$b)) {
	if ($_ eq 'label') {
	    next;
	} elsif ($_ eq 'append') {
	    next;
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

	if ($to_add->{label} eq 'linux') {
	    expand_entry_symlinks($bootloader, $to_add);
	    $label = kernel_str2label(vmlinuz2kernel_str($to_add->{kernel_or_dev}), 'use_long_name');
	} else {
	    $label =~ s/^alt\d*_//;
	    $label = 'alt' . ($i++ ? $i : '') . "_$label";
	}
    }
    die 'add_entry';
}

sub expand_entry_symlinks {
    my ($bootloader, $entry) = @_;

    foreach my $kind ('kernel_or_dev', 'initrd') {
	my $old_long_name = $bootloader->{old_long_names} && $bootloader->{old_long_names}{$entry->{$kind}} or next;

	#- replace all the {$kind} using this symlink to the real file
	log::l("replacing $entry->{$kind} with $old_long_name for bootloader label $entry->{label}");
	$entry->{$kind} = $old_long_name;
    }
}

sub _do_the_symlink {
    my ($bootloader, $link, $long_name) = @_;

    my $existing_link = readlink("$::prefix$link");
    if ($existing_link && $existing_link eq $long_name) {
	#- nothing to do :)
	return;
    }

    #- the symlink is going to change! 
    #- replace all the {$kind} using this symlink to the real file
    my $old_long_name = $existing_link =~ m!^/! ? $existing_link : "/boot/$existing_link";
    if (-e "$::prefix$old_long_name") {
	$bootloader->{old_long_names}{$link} = $old_long_name;
    } else {
	log::l("ERROR: $link points to $old_long_name which doesn't exist");
    }

    #- changing the symlink
    symlinkf($long_name, "$::prefix$link")
      or cp_af("$::prefix/boot/$long_name", "$::prefix$link");
}

sub add_kernel {
    my ($bootloader, $kernel_str, $v, $b_nolink, $b_no_initrd) = @_;

    add2hash($v,
	     {
	      type => 'image',
	      label => kernel_str2label($kernel_str),
	     });

    #- normalize append and handle special options
    {
	my ($simple, $dict) = unpack_append("$bootloader->{perImageAppend} $v->{append}");
	if (-e "$::prefix/sbin/udev" && $kernel_str->{version} =~ /^2\.(\d+\.\d+)/ && $1 >= 6.8) {
	    log::l("it is a recent kernel, so we remove any existing devfs= kernel option to enable udev");
	    @$dict = grep { $_->[0] ne 'devfs' } @$dict;
	}
	$v->{append} = pack_append($simple, $dict);
    }

    #- new versions of yaboot don't handle symlinks
    $b_nolink ||= arch() =~ /ppc/;

    $b_nolink ||= $kernel_str->{use_long_name};

    my $vmlinuz_long = kernel_str2vmlinuz_long($kernel_str);
    $v->{kernel_or_dev} = "/boot/$vmlinuz_long";
    -e "$::prefix$v->{kernel_or_dev}" or log::l("unable to find kernel image $::prefix$v->{kernel_or_dev}"), return;
    if (!$b_nolink) {
	$v->{kernel_or_dev} = '/boot/' . kernel_str2vmlinuz_short($kernel_str);
	_do_the_symlink($bootloader, $v->{kernel_or_dev}, $vmlinuz_long);
    }
    log::l("adding $v->{kernel_or_dev}");

    if (!$b_no_initrd) {
	my $initrd_long = kernel_str2initrd_long($kernel_str);
	$v->{initrd} = "/boot/$initrd_long";
	mkinitrd($kernel_str->{version}, $v) or undef $v->{initrd};
	if ($v->{initrd} && !$b_nolink) {
	    $v->{initrd} = '/boot/' . kernel_str2initrd_short($kernel_str);
	    _do_the_symlink($bootloader, $v->{initrd}, $initrd_long);
	}
    }

    add_entry($bootloader, $v);
}

sub duplicate_kernel_entry {
    my ($bootloader, $new_label) = @_;

    get_label($new_label, $bootloader) and return;

    my $entry = { %{ get_label('linux', $bootloader) }, label => $new_label };
    add_entry($bootloader, $entry);
}

my $uniq_dict_appends = join('|', qw(devfs acpi pci resume PROFILE XFree));

sub unpack_append {
    my ($s) = @_;
    my @l = split(' ', $s);
    [ grep { !/=/ } @l ], [ map { if_(/(.*?)=(.*)/, [$1, $2]) } @l ];
}
sub pack_append {
    my ($simple, $dict) = @_;

    #- normalize
    $simple = [ reverse(uniq(reverse @$simple)) ];
    $dict = [ reverse(uniq_ { 
	my ($k, $v) = @$_; 
	$k =~ /^($uniq_dict_appends)$/ ? $k : "$k=$v";
    } reverse @$dict) ];

    join(' ', @$simple, map { "$_->[0]=$_->[1]" } @$dict);
}

sub normalize_append {
    my ($s) = @_;
    my ($simple, $dict) = unpack_append($s);
    pack_append($simple, $dict);
}

sub modify_append {
    my ($b, $f) = @_;

    my @l = grep { $_->{type} eq 'image' && !($::isStandalone && $_->{label} eq 'failsafe') } @{$b->{entries}};

    foreach (\$b->{perImageAppend}, map { \$_->{append} } @l) {
	my ($simple, $dict) = unpack_append($$_);
	$f->($simple, $dict);
	$$_ = pack_append($simple, $dict);
	log::l("modify_append: $$_");
    }
}

sub append__mem_is_memsize { $_[0] =~ /^\d+[kM]?$/i }

sub get_append_simple {
    my ($b, $key) = @_;
    my ($simple, $_dict) = unpack_append($b->{perImageAppend});
    member($key, @$simple);
}
sub get_append_with_key {
    my ($b, $key) = @_;
    my ($_simple, $dict) = unpack_append($b->{perImageAppend});
    my @l = map { $_->[1] } grep { $_->[0] eq $key } @$dict;

    log::l("more than one $key in $b->{perImageAppend}") if @l > 1;
    $l[0];
}
sub remove_append_simple {
    my ($b, $key) = @_;
    modify_append($b, sub {
	my ($simple, $_dict) = @_;
	@$simple = grep { $_ ne $key } @$simple;
    });
}
sub set_append_with_key {
    my ($b, $key, $val) = @_;

    modify_append($b, sub {
	my ($_simple, $dict) = @_;

	if ($val eq '') {
	    @$dict = grep { $_ ne $key } @$dict;
	} else {
	    push @$dict, [ $key, $val ];
	}
    });
}
sub set_append_simple {
    my ($b, $key) = @_;

    modify_append($b, sub {
	my ($simple, $_dict) = @_;
	@$simple = uniq(@$simple, $key);
    });
}
sub may_append_with_key {
    my ($b, $key, $val) = @_;
    set_append_with_key($b, $key, $val) if !get_append_with_key($b, $key);
}

sub get_append_memsize {
    my ($b) = @_;
    my ($_simple, $dict) = unpack_append($b->{perImageAppend});
    find { $_->[0] eq 'mem' && append__mem_is_memsize($_->[1]) } @$dict;
}

sub set_append_memsize {
    my ($b, $memsize) = @_;

    modify_append($b, sub {
	my ($_simple, $dict) = @_;

	@$dict = grep { $_->[0] ne 'mem' || !append__mem_is_memsize($_->[1]) } @$dict;
	push @$dict, [ mem => $memsize ] if $memsize;
    });
}

sub get_append_netprofile {
    my ($e) = @_;
    my ($simple, $dict) = unpack_append($e->{append});
    my ($p, $dict_) = partition { $_->[0] eq 'PROFILE' } @$dict;
    pack_append($simple, $dict_), $p->[0][1];
}
sub set_append_netprofile {
    my ($e, $append, $profile) = @_;
    my ($simple, $dict) = unpack_append($append);
    push @$dict, [ 'PROFILE', $profile ] if $profile;
    $e->{append} = pack_append($simple, $dict);
}

sub configure_entry {
    my ($entry) = @_;
    $entry->{type} eq 'image' or return;

    if (my $kernel_str = vmlinuz2kernel_str($entry->{kernel_or_dev})) {
	$entry->{initrd} ||= '/boot/' . kernel_str2initrd_short($kernel_str);
	mkinitrd($kernel_str->{version}, $entry) or undef $entry->{initrd};
    }
}

sub get_kernels_and_labels_before_kernel_remove {
    my ($to_remove_kernel) = @_;
    my @kernels = grep { $_ ne $to_remove_kernel } installed_vmlinuz();
    map { kernel_str2label($_) => $_ } get_kernel_labels(\@kernels);
}

sub get_kernels_and_labels {
    my ($b_prefer_24) = @_;
    get_kernel_labels([ installed_vmlinuz() ], $b_prefer_24);
}

sub get_kernel_labels {
    my ($kernels, $b_prefer_24) = @_;
    
    my @kernels_str = 
      sort { c::rpmvercmp($b->{version_no_ext}, $a->{version_no_ext}) } 
      grep { -d "$::prefix/lib/modules/$_->{version}" }
      map { vmlinuz2kernel_str($_) } @$kernels;

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

    my ($name, $main_version, undef, $extraversion, $rest) = 
      $string =~ m!^(.*?-)(\d+(?:\.\d+)*)(-((?:pre|rc)\d+))?(.*)$!;

    if (my ($mdkver, $cpu, $nproc, $mem) = $rest =~ m|-(.+)-(.+)-(.+)-(.+)|) {
	$rest = "$cpu$nproc$mem-$mdkver";
    }
    $name = '' if $name eq 'linux-';

    my $return = "$name$main_version$extraversion$rest";

    $return =~ s|\.||g;
    $return =~ s|mdk||;
    $return =~ s|64GB|64G|;
    $return =~ s|4GB|4G|;
    $return =~ s|secure|sec|;
    $return =~ s|enterprise|ent|;

    $return;
}

sub suggest {
    my ($bootloader, $all_hds, %options) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    my $root_part = fs::get::root($fstab);
    my $root = '/dev/' . (isLoopback($root_part) ? 'loop7' : $root_part->{device});
    my $boot = fs::get::root($fstab, 'boot')->{device};
    #- PPC xfs module requires enlarged initrd
    my $xfsroot = $root_part->{fs_type} eq 'xfs';

    my ($onmbr, $unsafe) = $bootloader->{crushMbr} ? (1, 0) : suggest_onmbr($all_hds->{hds}[0]);
    add2hash_($bootloader, arch() =~ /ppc/ ?
	{
	 defaultos => "linux",
	 entries => [],
	 'init-message' => "Welcome to Mandrakelinux!",
	 delay => 30,	#- OpenFirmware delay
	 timeout => 50,
	 enableofboot => 1,
	 enablecdboot => 1,
	   if_(detect_devices::get_mac_model() =~ /IBM/,
	 boot => "/dev/sda1",
           ),
	 xfsroot => $xfsroot,
	} :
	{
	 bootUnsafe => $unsafe,
	 entries => [],
	 timeout => $onmbr && 10,
	 nowarn => 1,
	   if_(arch() !~ /ia64/,
	 boot => "/dev/" . ($onmbr ? $all_hds->{hds}[0]{device} : $boot),
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
	set_append_with_key($bootloader, console => $s);
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
	my $e = add_kernel($bootloader, $kernel,
	       {
		root => $root,
		if_($options{vga_fb} && $kernel->{ext} eq '', vga => $options{vga_fb}), #- using framebuffer
		if_($options{vga_fb} && $options{quiet}, append => "splash=silent"),
	       });

	if ($options{vga_fb} && $e->{label} eq 'linux') {
	    add_kernel($bootloader, $kernel, { root => $root, label => 'linux-nonfb' });
	}
    }

    #- remove existing libsafe, don't care if the previous one was modified by the user?
    @{$bootloader->{entries}} = grep { $_->{label} ne 'failsafe' } @{$bootloader->{entries}};

    add_kernel($bootloader, $kernels[0],
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
	  grep { isFat_or_NTFS($_) && member(fs::type::fs_type_from_magic($_), 'vfat', 'ntfs') }
	    map { @{$_->{primary}{normal}} } @{$all_hds->{hds}};
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
    my ($all_hds) = @_;
    my $bootloader = &read($all_hds);
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
    my $root_part = fs::get::root($fstab);

    grep {
	!(/lilo/ && isLoopback($root_part))
	  && !(/lilo-graphic/ && detect_devices::matching_desc__regexp('ProSavageDDR'))
	  && !(/grub/ && isRAID($root_part));
    } method_choices_raw();
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


sub create_link_source() {
    #- we simply do it for all kernels :)
    #- so this can be used in %post of kernel and also of kernel-source
    foreach (all("$::prefix/usr/src")) {
	my ($version) = /^linux-(\d+\.\d+.*)/ or next;
	foreach (glob("$::prefix/lib/modules/$version*")) {
	    -d $_ or next;
	    log::l("creating symlink $_/build");
	    symlink "/usr/src/linux-$version", "$_/build";
	}
    }
}

sub dev2yaboot {
    my ($dev) = @_;

    devices::make("$::prefix$dev"); #- create it in the chroot

    my $of_dev;
    run_program::rooted_or_die($::prefix, "/usr/sbin/ofpath", ">", \$of_dev, $dev);
    chomp($of_dev);
    log::l("OF Device: $of_dev");
    $of_dev;
}

sub check_enough_space() {
    my $e = "$::prefix/boot/.enough_space";
    output $e, 1; -s $e or die N("not enough room in /boot");
    unlink $e;
}

sub write_yaboot {
    my ($bootloader, $all_hds) = @_;

    my $fstab = [ fs::get::fstab($all_hds) ]; 

    my $file2yaboot = sub {
	my ($part, $file) = fs::get::file2part($fstab, $_[0]);
	dev2yaboot('/dev/' . $part->{device}) . "," . $file;
    };

    #- do not write yaboot.conf for old-world macs
    my $mac_type = detect_devices::get_mac_model();
    return if $mac_type =~ /Power Macintosh/;

    $bootloader->{prompt} ||= $bootloader->{timeout};

    if ($bootloader->{message}) {
	eval { output("$::prefix/boot/message", $bootloader->{message}) }
	  or $bootloader->{message} = 0;
    }

    my @conf;

    if (!get_label($bootloader->{default}, $bootloader)) {
	log::l("default bootloader entry $bootloader->{default} is invalid, choose another one");
	$bootloader->{default} = $bootloader->{entries}[0]{label};
    }
    push @conf, "# yaboot.conf - generated by DrakX/drakboot";
    push @conf, "# WARNING: do not forget to run ybin after modifying this file\n";
    push @conf, "default=" . make_label_lilo_compatible($bootloader->{default}) if $bootloader->{default};
    push @conf, sprintf('init-message="\n%s\n"', $bootloader->{'init-message'}) if $bootloader->{'init-message'};

    if ($bootloader->{boot}) {
	push @conf, "boot=$bootloader->{boot}";
	push @conf, "ofboot=" . dev2yaboot($bootloader->{boot}) if $mac_type !~ /IBM/;
    } else {
	die "no bootstrap partition defined.";
    }

    push @conf, map { "$_=$bootloader->{$_}" } grep { $bootloader->{$_} } (qw(delay timeout), if_($mac_type !~ /IBM/, 'defaultos'));
    push @conf, "install=/usr/lib/yaboot/yaboot";
    if ($mac_type =~ /IBM/) {
	push @conf, 'nonvram';
    } else {
	push @conf, 'magicboot=/usr/lib/yaboot/ofboot';
	push @conf, grep { $bootloader->{$_} } qw(enablecdboot enableofboot);
    }
    foreach my $entry (@{$bootloader->{entries}}) {

	if ($entry->{type} eq "image") {
	    push @conf, "$entry->{type}=" . $file2yaboot->($entry->{kernel_or_dev});
	    my @entry_conf;
	    push @entry_conf, "label=" . make_label_lilo_compatible($entry->{label});
	    push @entry_conf, "root=$entry->{root}";
	    push @entry_conf, "initrd=" . $file2yaboot->($entry->{initrd}) if $entry->{initrd};
	    #- xfs module on PPC requires larger initrd - say 6MB?
	    push @entry_conf, "initrd-size=6144" if $bootloader->{xfsroot};
	    push @entry_conf, qq(append=" $entry->{append}") if $entry->{append};
	    push @entry_conf, $entry->{'read-write'} ? "read-write" : "read-only";
	    push @conf, map { "\t$_" } @entry_conf;
	} else {
	    my $of_dev = dev2yaboot($entry->{kernel_or_dev});
	    push @conf, "$entry->{label}=$of_dev";
	}
    }
    my $f = "$::prefix/etc/yaboot.conf";
    log::l("writing yaboot config to $f");
    rename $f, "$f.old";
    output($f, map { "$_\n" } @conf);
}

sub install_yaboot {
    my ($bootloader, $all_hds) = @_;
    log::l("Installing boot loader...");
    write_yaboot($bootloader, $all_hds);
    when_config_changed_yaboot($bootloader);
}
sub when_config_changed_yaboot {
    my ($bootloader) = @_;
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

sub write_lilo {
    my ($bootloader, $all_hds) = @_;
    $bootloader->{prompt} ||= $bootloader->{timeout};

    my $file2fullname = sub {
	my ($file) = @_;
	if (arch() =~ /ia64/) {
	    my $fstab = [ fs::get::fstab($all_hds) ];
	    (my $part, $file) = fs::get::file2part($fstab, $file);
	    my %hds = map_index { $_ => "hd$::i" } map { $_->{device} } 
	      sort { 
		  my ($a_is_fat, $b_is_fat) = ($a->{fs_type} eq 'vfat', $b->{fs_type} eq 'vfat');
		  $a_is_fat <=> $b_is_fat || $a->{device} cmp $b->{device};
	      } @$fstab;
	    $hds{$part->{device}} . ":" . $file;
	} else {
	    $file
	}
    };

    my @sorted_hds = sort_hds_according_to_bios($bootloader, $all_hds);

    if (is_empty_hash_ref($bootloader->{bios} ||= {}) && $all_hds->{hds}[0] != $sorted_hds[0]) {
	log::l("Since we're booting on $sorted_hds[0]{device}, make it bios=0x80");
	$bootloader->{bios} = { "/dev/$sorted_hds[0]{device}" => '0x80' };
    }

    my @conf;

    #- normalize: RESTRICTED is only valid if PASSWORD is set
    delete $bootloader->{restricted} if !$bootloader->{password};

    if (!get_label($bootloader->{default}, $bootloader)) {
	log::l("default bootloader entry $bootloader->{default} is invalid, choose another one");
	$bootloader->{default} = $bootloader->{entries}[0]{label};
    }
    push @conf, "# File generated by DrakX/drakboot";
    push @conf, "# WARNING: do not forget to run lilo after modifying this file\n";
    push @conf, "default=" . make_label_lilo_compatible($bootloader->{default}) if $bootloader->{default};
    push @conf, map { "$_=$bootloader->{$_}" } grep { $bootloader->{$_} } qw(boot map install vga keytable raid-extra-boot);
    push @conf, grep { $bootloader->{$_} } qw(linear geometric compact prompt nowarn restricted static-bios-codes);
    push @conf, qq(append="$bootloader->{append}") if $bootloader->{append};
    push @conf, "password=" . $bootloader->{password} if $bootloader->{password}; #- also done by msec
    push @conf, "timeout=" . round(10 * $bootloader->{timeout}) if $bootloader->{timeout};
    push @conf, "serial=" . $1 if get_append_with_key($bootloader, 'console') =~ /ttyS(.*)/;
    
    push @conf, "message=/boot/message" if arch() !~ /ia64/;
    push @conf, "menu-scheme=wb:bw:wb:bw" if arch() !~ /ia64/;

    push @conf, "ignore-table" if any { $_->{unsafe} && $_->{table} } @{$bootloader->{entries}};

    push @conf, map_each { "disk=$::a bios=$::b" } %{$bootloader->{bios}};

    foreach my $entry (@{$bootloader->{entries}}) {
	push @conf, "$entry->{type}=" . $file2fullname->($entry->{kernel_or_dev});
	my @entry_conf;
	push @entry_conf, "label=" . make_label_lilo_compatible($entry->{label});

	if ($entry->{type} eq "image") {		
	    push @entry_conf, "root=$entry->{root}" if $entry->{root};
	    push @entry_conf, "initrd=" . $file2fullname->($entry->{initrd}) if $entry->{initrd};
	    push @entry_conf, qq(append="$entry->{append}") if $entry->{append};
	    push @entry_conf, "vga=$entry->{vga}" if $entry->{vga};
	    push @entry_conf, $entry->{'read-write'} ? "read-write" : "read-only";
	    push @entry_conf, grep { $entry->{$_} } qw(optional);
	} else {
	    push @entry_conf, "table=$entry->{table}" if $entry->{table};
	    push @entry_conf, "unsafe" if $entry->{unsafe} && !$entry->{table};
		
	    if ($entry->{table}) {
		my $hd = fs::get::device2part($entry->{table}, $all_hds->{hds});
		if ($hd != $sorted_hds[0]) {		       
		    #- boot off the nth drive, so reverse the BIOS maps
		    my $nb = sprintf("0x%x", 0x80 + (find_index { $hd == $_ } @sorted_hds));
		    $entry->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		}
	    }
	    if ($entry->{mapdrive}) {
		push @entry_conf, map_each { "map-drive=$::a", "   to=$::b" } %{$entry->{mapdrive}};
	    }
	}
	push @conf, map { "\t$_" } @entry_conf;
    }
    my $f = arch() =~ /ia64/ ? "$::prefix/boot/efi/elilo.conf" : "$::prefix/etc/lilo.conf";

    log::l("writing lilo config to $f");
    rename $f, "$f.old";
    output_with_perm($f, $bootloader->{password} ? 0600 : 0644, map { "$_\n" } @conf);
}

sub install_lilo {
    my ($bootloader, $all_hds) = @_;

    if (my ($install) = $bootloader->{method} =~ /lilo-(text|menu)/) {
	$bootloader->{install} = $install;
    } else {
	delete $bootloader->{install};
    }
    output("$::prefix/boot/message-text", $bootloader->{message}) if $bootloader->{message};
    symlinkf "message-" . ($bootloader->{method} ne 'lilo-graphic' ? 'text' : 'graphic'), "$::prefix/boot/message";

    write_lilo($bootloader, $all_hds);

    when_config_changed_lilo($bootloader);
}

sub when_config_changed_lilo {
    my ($bootloader) = @_;

    if (!$::testing && arch() !~ /ia64/ && $bootloader->{method} =~ /lilo/) {
	log::l("Installing boot loader on $bootloader->{boot}...");
	my $error;
	my $answer = $bootloader->{force_lilo_answer} || '';
	run_program::rooted($::prefix, "echo $answer | lilo", '2>', \$error) or die "lilo failed: $error";
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
    my ($bootloader, $all_hds) = @_;
    my $boot_hd = fs::get::device2part($bootloader->{first_hd_device} || $bootloader->{boot}, $all_hds->{hds}); #- $boot_hd is undefined when installing on floppy
    my $boot_kind = $boot_hd && hd2bios_kind($boot_hd);

    my $translate = sub {
	my ($hd) = @_;
	my $kind = hd2bios_kind($hd);
	$boot_hd ? ($hd == $boot_hd ? 0 : $kind eq $boot_kind ? 1 : 2) . "_$kind" : $kind;
    };
    sort { $translate->($a) cmp $translate->($b) } @{$all_hds->{hds}};
}

sub device_string2grub {
    my ($dev, $legacy_floppies, $sorted_hds) = @_;
    if (my $device = fs::get::device2part($dev, [ @$sorted_hds, fs::get::hds_fstab(@$sorted_hds) ])) {
	device2grub($device, $sorted_hds);
    } elsif (my $floppy = fs::get::device2part($dev, $legacy_floppies)) {
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
	(fs::get::device2part($device->{rootDevice}, $sorted_hds), $device->{device} =~ /(\d+)$/) :
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
    my $f = "$::prefix/boot/grub/device.map";
    rename $f, "$f.old";
    output($f,
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
	my $part = fs::get::device2part($device, $fstab) or log::l("ERROR: unknown device $device (computed from $grub_file)");
	my $mntpoint = $part->{mntpoint} || '';
	($mntpoint eq '/' ? '' : $mntpoint) . '/' . $rel_file;
    } else {
	$grub_file;
    }
}

sub write_grub {
    my ($bootloader, $all_hds) = @_;

    my $fstab = [ fs::get::fstab($all_hds) ]; 
    my @legacy_floppies = detect_devices::floppies();
    my @sorted_hds = sort_hds_according_to_bios($bootloader, $all_hds);
    write_grub_device_map(\@legacy_floppies, \@sorted_hds);

    if (get_append_with_key($bootloader, 'console') =~ /ttyS(\d),(\d+)/) {
	$bootloader->{serial} ||= "--unit=$1 --speed=$2";
	$bootloader->{terminal} ||= "--timeout=" . ($bootloader->{timeout} || 0) . " console serial";
    }

    my $file2grub = sub {
	my ($part, $file) = fs::get::file2part($fstab, $_[0], 'keep_simple_symlinks');
	device2grub($part, \@sorted_hds) . $file;
    };
    {
	my @conf;

	push @conf, map { "$_ $bootloader->{$_}" } grep { $bootloader->{$_} } qw(timeout color serial terminal);
	push @conf, map { $_ . ' ' . $file2grub->($bootloader->{$_}) } grep { $bootloader->{$_} } qw(splashimage);

	eval {
	    push @conf, "default " . (find_index { $_->{label} eq $bootloader->{default} } @{$bootloader->{entries}});
	};

	foreach (@{$bootloader->{entries}}) {
	    my $title = "\ntitle $_->{label}";

	    if ($_->{type} eq "image") {
		my $vga = $_->{vga} || $bootloader->{vga};
		push @conf, $title,
		  join(' ', 'kernel', $file2grub->($_->{kernel_or_dev}),
		       if_($_->{root}, $_->{root} =~ /loop7/ ? "root=707" : "root=$_->{root}"), #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
		       $_->{append},
		       if_($_->{'read-write'}, 'rw'),
		       if_($vga && $vga ne "normal", "vga=$vga"));
		push @conf, "initrd " . $file2grub->($_->{initrd}) if $_->{initrd};
	    } else {
		my $dev = eval { device_string2grub($_->{kernel_or_dev}, \@legacy_floppies, \@sorted_hds) };
		if (!$dev) {
		    log::l("dropping bad entry $_->{label} for unknown device $_->{kernel_or_dev}");
		    next;
		}
		push @conf, $title, "root $dev";

		if ($_->{table}) {
		    if (my $hd = fs::get::device2part($_->{table}, \@sorted_hds)) {
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
	rename $f, "$f.old";
	output($f, map { "$_\n" } @conf);
    }
    {
	my $f = "$::prefix/boot/grub/install.sh";
	my $dev = device_string2grub($bootloader->{boot}, \@legacy_floppies, \@sorted_hds);
	my ($stage1, $stage2, $menu_lst) = map { $file2grub->("/boot/grub/$_") } qw(stage1 stage2 menu.lst);
	rename $f, "$f.old";
	output "$::prefix/boot/grub/install.sh",
"grub --device-map=/boot/grub/device.map --batch <<EOF
install $stage1 d $dev $stage2 p $menu_lst
quit
EOF
";
    }

    check_enough_space();
}

sub install_grub {
    my ($bootloader, $all_hds) = @_;

    write_grub($bootloader, $all_hds);

    if (!$::testing) {
	log::l("Installing boot loader...");
	my $error;
	run_program::rooted($::prefix, "sh", '/boot/grub/install.sh', "2>", \$error) or die "grub failed: $error";
    }
}
sub when_config_changed_grub {
    my ($_bootloader) = @_;
    #- don't do anything
}

sub action {
    my ($bootloader, $action, @para) = @_;

    my $main_method = main_method($bootloader->{method});
    my $f = $bootloader::{$action . '_' . $main_method} or die "unknown bootloader method $bootloader->{method} ($action)";
    $f->($bootloader, @para);
}

sub install {
    my ($bootloader, $all_hds) = @_;

    if (my $part = fs::get::device2part($bootloader->{boot}, [ fs::get::fstab($all_hds) ])) {
	die N("You can't install the bootloader on a %s partition\n", $part->{fs_type})
	  if $part->{fs_type} eq 'xfs';
    }
    $bootloader->{keytable} = keytable($bootloader->{keytable});
    action($bootloader, 'install', $all_hds);
}

sub update_for_renumbered_partitions {
    my ($in, $renumbering, $all_hds) = @_;

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
	    $sorted_hds[$1] = fs::get::device2part($::b, $all_hds->{hds}) if $::a =~ /hd(\d+)/;
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
	if ($_->{new} ne $_->{orig}) {
	    rename "$::prefix/$_->{file}", "$::prefix/$_->{file}.old";
	    output("$::prefix/$_->{file}", $_->{new});
	}
    }

    my $main_method = detect_main_method($all_hds);
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
