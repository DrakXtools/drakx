package bootloader; # $Id$

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use fs::type;
use fs::get;
use fs::loopback;
use fs::proc_partitions;
use log;
use any;
use devices;
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
sub vmlinuz2kernel_str {
    my ($vmlinuz) = @_;
    my ($basename, $version) = expand_vmlinuz_symlink($vmlinuz) =~ /$decompose_vmlinuz_name/ or return;
    { 
	basename => $basename,
	version => $version, 
	$version =~ /(.*md[kv])-?(.*)/ ? (ext => $2, version_no_ext => $1) : (version_no_ext => $version),
    };
}

sub basename2initrd_basename {
    my ($basename) = @_;
    $basename =~ s!vmlinuz-?!!; #- here we do not use $vmlinuz_regexp since we explictly want to keep all that is not "vmlinuz"
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

sub kernel_str2label {
    my ($kernel, $o_use_long_name) = @_;
    my $base = $kernel->{basename} eq 'vmlinuz' ? 'linux' : $kernel->{basename};
    $o_use_long_name || $kernel->{use_long_name} ?
      sanitize_ver($base, $kernel) : 
        $kernel->{ext} ? "$base-" . short_ext($kernel) : $base;
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
    my ($kernel_version, $bootloader, $entry, $initrd) = @_;

    $::testing || -e "$::prefix/$initrd" and return $initrd;

    my $loop_boot = fs::loopback::prepare_boot();

    modules::load('loop');
    my @options = (
		   "-v", "-f", $initrd, "--ifneeded", $kernel_version, 
		   if_($entry->{initrd_options}, split(' ', $entry->{initrd_options})),
		  );
    if (!run_program::rooted($::prefix, 'mkinitrd', @options)) {
	unlink("$::prefix/$initrd");
	die "mkinitrd failed:\n(mkinitrd @options))";
    }
    add_boot_splash($initrd, $entry->{vga} || $bootloader->{vga});

    fs::loopback::save_boot($loop_boot);

    -e "$::prefix/$initrd" && $initrd;
}

sub rebuild_initrd {
    my ($kernel_version, $bootloader, $entry, $initrd) = @_;

    my $old = $::prefix . $entry->{initrd} . '.old';
    unlink $old;
    rename "$::prefix$initrd", $old;
    if (!mkinitrd($kernel_version, $bootloader, $entry, $initrd)) {
	log::l("rebuilding initrd failed, putting back the old one");
	rename $old, "$::prefix$initrd";
    }
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
sub update_splash {
    my ($bootloader) = @_;

    foreach (@{$bootloader->{entries}}) {
	bootloader::add_boot_splash($_->{initrd}, $_->{vga} || $bootloader->{vga}) if $_->{initrd};
    }
}

sub read {
    my ($all_hds) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    foreach my $main_method (main_method_choices()) {
	my $f = $bootloader::{"read_$main_method"} or die "unknown bootloader method $main_method (read)";
	my $bootloader = $f->($fstab);

	cleanup_entries($bootloader);

	my @devs = $bootloader->{boot};
	if ($bootloader->{'raid-extra-boot'} =~ /mbr/ && 
	    (my $md = fs::get::device2part($bootloader->{boot}, $all_hds->{raids}))) {
	    @devs = map { $_->{rootDevice} } @{$md->{disks}};
	} elsif ($bootloader->{'raid-extra-boot'} =~ m!/dev/!) {
	    @devs = split(',', $bootloader->{'raid-extra-boot'});
	}

	my ($type) = map {
	    if (m!/fd\d+$!) {
		warn "not checking the method on floppy, assuming $main_method is right\n";
		$main_method;
	    } elsif (member($main_method, qw(yaboot cromwell silo))) {
		#- not checking, there's only one bootloader anyway :)
		$main_method;
	    } elsif (my $type = partition_table::raw::typeOfMBR($_)) {
		warn "typeOfMBR $type on $_ for method $main_method\n" if $ENV{DEBUG};
		$type;
	    } else { () }
	} @devs;

	if ($type eq $main_method) {
	    my @prefered_entries = map { get_label($_, $bootloader) } $bootloader->{default}, 'linux';

	    if (my $default = find { $_ && $_->{type} eq 'image' } (@prefered_entries, @{$bootloader->{entries}})) {
		$bootloader->{default_options} = $default;
		$bootloader->{perImageAppend} ||= $default->{append};
		log::l("perImageAppend is now $bootloader->{perImageAppend}");
	    } else {
		$bootloader->{default_options} = {};
	    }
	    return $bootloader;
	}
    }
}

sub read_grub {
    my ($fstab) = @_;

    my $grub2dev = read_grub_device_map();

    my $bootloader = read_grub_menu_lst($fstab, $grub2dev) or return;

    read_grub_install_sh($bootloader, $grub2dev);

    $bootloader;
}

sub read_grub_install_sh {
    my ($bootloader, $grub2dev) = @_;

    #- matches either:
    #-   setup (hd0)
    #-   install (hd0,0)/boot/grub/stage1 d (hd0) (hd0,0)/boot/grub/stage2 p (hd0,0)/boot/grub/menu.lst
    if (cat_("$::prefix/boot/grub/install.sh") =~ /^(?:setup.*|install\s.*\sd)\s+(\(.*?\))/m) {
	$bootloader->{boot} = grub2dev($1, $grub2dev);
    }    
}

sub read_grub_menu_lst {
    my ($fstab, $grub2dev) = @_;
    my $global = 1;
    my ($e, %b);

    my $menu_lst_file = "$::prefix/boot/grub/menu.lst";
    -e $menu_lst_file or return;

    foreach (cat_($menu_lst_file)) {
        chomp;
	s/^\s*//; s/\s*$//;
        next if /^#/ || /^$/;
	my ($keyword, $v) = split('[ \t=]+', $_, 2) or
	  warn qq(unknown line in /boot/grub/menu.lst: "$_"\n), next;

        if ($keyword eq 'title') {
            push @{$b{entries}}, $e = { label => $v };
            $global = 0;
        } elsif ($global) {
            $b{$keyword} = $v eq '' ? 1 : grub2file($v, $grub2dev, $fstab);
        } else {
            if ($keyword eq 'kernel') {
                $e->{type} = 'image';
		$e->{kernel} = $v;
            } elsif ($keyword eq 'root' || $keyword eq 'rootnoverify') {
                $e->{type} = 'other';
		$e->{grub_noverify} = 1 if $keyword eq 'rootnoverify';
                $e->{kernel_or_dev} = grub2dev($v, $grub2dev);
                $e->{append} = "";
            } elsif ($keyword eq 'initrd') {
                $e->{initrd} = grub2file($v, $grub2dev, $fstab);
            } elsif ($keyword eq 'map') {
		$e->{mapdrive}{$2} = $1 if $v =~ m/\((.*)\) \((.*)\)/;
            } elsif ($keyword eq 'module') {
		push @{$e->{modules}}, $v;
	    } else {
		$e->{$keyword} = $v eq '' ? 1 : $v;
	    }
        }
    }

    #- sanitize
    foreach my $e (@{$b{entries}}) {
	if ($e->{kernel} =~ /xen/ && @{$e->{modules}} == 2 && $e->{modules}[1] =~ /initrd/) {
	    (my $xen, $e->{xen_append}) = split(' ', $e->{kernel}, 2);
	    ($e->{kernel}, my $initrd) = @{delete $e->{modules}};
	    $e->{xen} = grub2file($xen, $grub2dev, $fstab);
	    $e->{initrd} = grub2file($initrd, $grub2dev, $fstab);
	}
	if (my $v = delete $e->{kernel}) {
	    (my $kernel, $e->{append}) = split(' ', $v, 2);
	    $e->{append} = join(' ', grep { !/^BOOT_IMAGE=/ } split(' ', $e->{append}));
	    $e->{root} = $1 if $e->{append} =~ s/root=(\S*)\s*//;
	    $e->{kernel_or_dev} = grub2file($kernel, $grub2dev, $fstab);
	}
	my ($vga, $other) = partition { /^vga=/ } split(' ', $e->{append});
	if (@$vga) {
	    $e->{vga} = $vga->[0] =~ /vga=(.*)/ && $1;
	    $e->{append} = join(' ', @$other);
	}
    }

    $b{nowarn} = 1;
    # handle broken installkernel -r:
    if (@{$b{entries}}) {
	$b{default} = min($b{default}, scalar(@{$b{entries}}) - 1);
	$b{default} = $b{entries}[$b{default}]{label};
    }
    $b{method} = $b{gfxmenu} ? 'grub-graphic' :  'grub-menu';

    \%b;
}

sub yaboot2dev {
    my ($of_path) = @_;
    find { dev2yaboot($_) eq $of_path } map { "/dev/$_->{dev}" } fs::proc_partitions::read_raw();
}

# assumes file is in /boot
# to do: use yaboot2dev for files as well
#- example of of_path: /pci@f4000000/ata-6@d/disk@0:3,/initrd-2.6.8.1-8mdk.img
sub yaboot2file {
    my ($of_path) = @_;
    
    if ($of_path =~ /,/) {
	"$::prefix/boot/" . basename($of_path);
    } else {
	yaboot2dev($of_path);
    }
}

sub read_silo() {
    my $bootloader = read_lilo_like("/boot/silo.conf", sub {
					my ($f) = @_;
					"/boot$f";
				    });
    $bootloader->{method} = 'silo';
    $bootloader;
}
sub read_cromwell() {
    my %b;
    $b{method} = 'cromwell';
    \%b;
}
sub read_yaboot() { 
    my $bootloader = read_lilo_like("/etc/yaboot.conf", \&yaboot2file);
    $bootloader->{method} = 'yaboot';
    $bootloader;
}
sub read_lilo() {
    my $bootloader = read_lilo_like("/etc/lilo.conf", sub { $_[0] });

    delete $bootloader->{timeout} unless $bootloader->{prompt};
    $bootloader->{timeout} = $bootloader->{timeout} / 10 if $bootloader->{timeout};

    my $submethod = member($bootloader->{install}, 'text', 'menu') ? $bootloader->{install} : 'menu';
    $bootloader->{method} = "lilo-$submethod";
    
    $bootloader;
}
sub read_lilo_like {
    my ($file, $filter_file) = @_;

    my $global = 1;
    my ($e);
    my %b;
    -e "$::prefix$file" or return;
    foreach my $line (cat_("$::prefix$file")) {
	next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
	my ($cmd, $v) = $line =~ /^\s*([^=\s]+)\s*(?:=\s*(.*?))?\s*$/ or log::l("unknown line in $file: $line"), next;

	if ($cmd =~ /^(?:image|other|macos|macosx|bsd|darwin)$/) {
	    $v = $filter_file->($v);
	    push @{$b{entries}}, $e = { type => $cmd, kernel_or_dev => $v };
	    $global = 0;
	} elsif ($global) {
	    if ($cmd eq 'disk' && $v =~ /(\S+)\s+bios\s*=\s*(\S+)/) {
		$b{bios}{$1} = $2;
	    } elsif ($cmd eq 'bios') {
		$b{bios}{$b{disk}} = $v;
	    } elsif ($cmd eq 'init-message') {
		$v =~ s/\\n//g; 
		$v =~ s/"//g;
		$b{'init-message'} = $v;
	    } else {
		$b{$cmd} = $v eq '' ? 1 : $v;
	    }
	} else {
	    if (($cmd eq 'map-drive' .. $cmd eq 'to') && $cmd eq 'to') {
		$e->{mapdrive}{$e->{'map-drive'}} = $v;
	    } else {
		if ($cmd eq 'initrd') {
		    $v = $filter_file->($v);
		}
		$e->{$cmd} = $v || 1;
	    }
	}
    }

    sub remove_quotes_and_spaces {
	local ($_) = @_;
	s/^\s*//; s/\s*$//;
	s/^"(.*?)"$/$1/;
	s/\\"/"/g;
	s/^\s*//; s/\s*$//; #- do it again for append=" foo"
	$_;
    }

    foreach ('append', 'root', 'default', 'raid-extra-boot') {
	$b{$_} = remove_quotes_and_spaces($b{$_}) if $b{$_};
    }
    foreach my $entry (@{$b{entries}}) {
	foreach ('append', 'root', 'label') {
	    $entry->{$_} = remove_quotes_and_spaces($entry->{$_}) if $entry->{$_};
	}
	if ($entry->{kernel_or_dev} =~ /\bmbootpack\b/) {
	    $entry->{initrd} = $entry->{kernel_or_dev};
	    $entry->{initrd} =~ s/\bmbootpack/initrd/;
	    $entry->{kernel_or_dev} =~ s/\bmbootpack/vmlinuz/;
	    $entry->{kernel_or_dev} =~ s/.img$//;
	    #- assume only xen is configured with mbootpack
	    $entry->{xen} = '/boot/xen.gz';
	    $entry->{root} = $1 if $entry->{append} =~ s/root=(\S*)\s*//;
	    ($entry->{xen_append}, $entry->{append}) = split '\s*--\s*', $entry->{append}, 2;
	}
    }

    # cleanup duplicate labels (in case file is corrupted)
    @{$b{entries}} = uniq_ { $_->{label} } @{$b{entries}};

    \%b;
}

sub cleanup_entries {
    my ($bootloader) = @_;

    #- cleanup bad entries (in case file is corrupted)
    @{$bootloader->{entries}} = 
	grep { 
	    my $pb = $_->{type} eq 'image' && dirname($_->{kernel_or_dev}) eq '/boot' && ! -e "$::prefix$_->{kernel_or_dev}";
	    log::l("dropping bootloader entry $_->{label} since $_->{kernel_or_dev} doesn't exist") if $pb;
	    !$pb;
	} @{$bootloader->{entries}};
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
	if (member($_, 'label', 'append', 'mapdrive', 'readonly', 'makeactive')) {
	    next;
	} else {
	    next if $a->{$_} eq $b->{$_};

	    my ($inode_a, $inode_b) = map { (stat "$::prefix$_")[1] } ($a->{$_}, $b->{$_});
	    next if $inode_a && $inode_b && $inode_a == $inode_b;
	}

	log::l("entries $a->{label} do not have same $_: $a->{$_} ne $b->{$_}");
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

	    #- we will keep $conflicting, but not with same symlinks if used by the entry to add
	    expand_entry_symlinks($bootloader, $conflicting);
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

    if ($existing_link) {
	#- the symlink is going to change! 
	#- replace all the {$kind} using this symlink to the real file
	my $old_long_name = $existing_link =~ m!^/! ? $existing_link : "/boot/$existing_link";
	if (-e "$::prefix$old_long_name") {
	    $bootloader->{old_long_names}{$link} = $old_long_name;
	} else {
	    log::l("ERROR: $link points to $old_long_name which does not exist");
	}
    } elsif (-e "$::prefix$link") {
	log::l("ERROR: $link is not a symbolic link");
    }

    #- changing the symlink
    symlinkf($long_name, "$::prefix$link")
      or cp_af("$::prefix/boot/$long_name", "$::prefix$link");
}

sub cmp_kernel_versions {
    my ($va, $vb) = @_;
    my $rel_a = $va =~ s/-(.*)$// && $1;
    my $rel_b = $vb =~ s/-(.*)$// && $1;
    ($va, $vb) = map { [ split /[.-]/ ] } $va, $vb;
    my $r = 0;
    mapn_ {
	$r ||= $_[0] <=> $_[1];
    } $va, $vb;
    $r || $rel_a <=> $rel_b || $rel_a cmp $rel_b;
}

sub get_mbootpack_filename {
    my ($entry) = @_;
    my $mbootpack_file = $entry->{initrd};
    $mbootpack_file =~ s/\binitrd/mbootpack/;
    $entry->{xen} && $mbootpack_file;
}

sub build_mbootpack {
    my ($entry) = @_;

    my $mbootpack = '/usr/bin/mbootpack';
    -f $::prefix . $entry->{kernel_or_dev} && -f $::prefix . $entry->{initrd} or return;

    my $mbootpack_file = get_mbootpack_filename($entry);
    -f ($::prefix . $mbootpack_file) and return 1;

    my $error;
    my $xen_kernel = '/tmp/xen_kernel';
    my $xen_vmlinux = '/tmp/xen_vmlinux';
    my $_b = before_leaving { unlink $::prefix . $_ foreach $xen_kernel, $xen_vmlinux };
    run_program::rooted($::prefix, '/bin/gzip', '>', $xen_kernel, '2>', \$error, '-dc', $entry->{xen})
      or die "unable to uncompress xen kernel";
    run_program::rooted($::prefix, '/bin/gzip', '>', $xen_vmlinux, '2>', \$error, '-dc', $entry->{kernel_or_dev})
      or die "unable to uncompress xen vmlinuz";

    run_program::rooted($::prefix, $mbootpack,
                        "2>", \$error,
                        '-o', $mbootpack_file,
                        '-m', $xen_vmlinux,
                        '-m', $entry->{initrd},
                        $xen_kernel)
      or die "mbootpack failed: $error";

    1;
}

sub add_kernel {
    my ($bootloader, $kernel_str, $v, $b_nolink, $b_no_initrd) = @_;

    if (short_ext($kernel_str) eq 'xen' && -f '/boot/xen.gz') {
	$v->{xen} = '/boot/xen.gz';
    }

    add2hash($v,
	     {
	      type => 'image',
	      label => kernel_str2label($kernel_str),
	     });

    #- normalize append and handle special options
    {
	my ($simple, $dict) = unpack_append("$bootloader->{perImageAppend} $v->{append}");
	if ($v->{label} eq 'failsafe') {
	    #- perImageAppend contains resume=/dev/xxx which we don't want
	    @$dict = grep { $_->[0] ne 'resume' } @$dict;
	}
	if (-e "$::prefix/sbin/udev" && cmp_kernel_versions($kernel_str->{version_no_ext}, '2.6.8') >= 0) {
	    log::l("it is a recent kernel, so we remove any existing devfs= kernel option to enable udev");
	    @$dict = grep { $_->[0] ne 'devfs' } @$dict;
	}
	$v->{append} = pack_append($simple, $dict);
    }

    #- new versions of yaboot do not handle symlinks
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
	$v->{initrd} = mkinitrd($kernel_str->{version}, $bootloader, $v, "/boot/$initrd_long");
	if ($v->{initrd} && !$b_nolink) {
	    $v->{initrd} = '/boot/' . kernel_str2initrd_short($kernel_str);
	    _do_the_symlink($bootloader, $v->{initrd}, $initrd_long);
	}
    }

    add_entry($bootloader, $v);
}

sub rebuild_initrds {
    my ($bootloader) = @_;

    my %done;
    foreach my $v (grep { $_->{initrd} } @{$bootloader->{entries}}) {
	my $kernel_str = vmlinuz2kernel_str($v->{kernel_or_dev});
	my $initrd_long = '/boot/' . kernel_str2initrd_long($kernel_str);
	next if $done{$initrd_long}++;

	rebuild_initrd($kernel_str->{version}, $bootloader, $v, $initrd_long);
    }
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
    my @l = "$s " =~ /((?:[^"\s]+|".*?")*)\s+/g;
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
	    @$dict = grep { $_->[0] ne $key } @$dict;
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
    my $e = find { $_->[0] eq 'mem' && append__mem_is_memsize($_->[1]) } @$dict;
    $e && $e->[1];
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
    my ($bootloader, $entry) = @_;
    $entry->{type} eq 'image' or return;

    if (my $kernel_str = vmlinuz2kernel_str($entry->{kernel_or_dev})) {
	$entry->{initrd} = 
	  mkinitrd($kernel_str->{version}, $bootloader, $entry,
		   $entry->{initrd} || '/boot/' . kernel_str2initrd_short($kernel_str));
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
      sort { cmp_kernel_versions($b->{version_no_ext}, $a->{version_no_ext}) } 
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

sub short_ext {
    my ($kernel_str) = @_;

    my $short_ext = {
	'i586-up-1GB' => 'i586',
	'i686-up-4GB' => '4GB',
	'xen0' => 'xen',
    }->{$kernel_str->{ext}};

    $short_ext || $kernel_str->{ext};
}
sub sanitize_ver {
    my ($name, $kernel_str) = @_;

    $name = '' if $name eq 'linux';

    my $v = $kernel_str->{version_no_ext};
    if ($v =~ s/-\d+\.mm\././) {
	$name = join(' ', grep { $_ } $name, 'multimedia');
    } elsif ($v =~ s/-(desktop|server|laptop)-/-/) {
	$name = join(' ', grep { $_ } $name, $1);
    }

    $v =~ s!md[kv]$!!;
    $v =~ s!-0\.(pre|rc)(\d+)\.!$1$2-!;

    my $return = join(' ', grep { $_ } $name, short_ext($kernel_str), $v);

    length($return) < 30 or $return =~ s!secure!sec!;
    length($return) < 30 or $return =~ s!enterprise!ent!;
    length($return) < 30 or $return =~ s!multimedia!mm!;

    $return;
}

sub suggest_message_text {
    my ($bootloader) = @_;

    if (!$bootloader->{message} && !$bootloader->{message_text} && arch() !~ /ia64/) {
	my $msg_en =
#-PO: these messages will be displayed at boot time in the BIOS, use only ASCII (7bit)
N_("Welcome to the operating system chooser!

Choose an operating system from the list above or
wait for default boot.

");
	my $msg = translate($msg_en);
	#- use the english version if more than 40% of 8bits chars
	#- else, use the translation but force a conversion to ascii
	#- to be sure there won't be undisplayable characters
	if (int(grep { $_ & 0x80 } unpack "c*", $msg) / length($msg) > 0.4) {
	    $msg = $msg_en;
	} else {
	    $msg = Locale::gettext::iconv($msg, "utf-8", "ascii//TRANSLIT");
	}
	$bootloader->{message_text} = $msg;
    }
}

sub suggest {
    my ($bootloader, $all_hds, %options) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    my $root_part = fs::get::root($fstab);
    my $root = isLoopback($root_part) ? '/dev/loop7' : fs::wild_device::from_part('', $root_part);
    my $boot = fs::get::root($fstab, 'boot')->{device};
    #- PPC xfs module requires enlarged initrd
    my $xfsroot = $root_part->{fs_type} eq 'xfs';

    my ($onmbr, $unsafe) = $bootloader->{crushMbr} ? (1, 0) : suggest_onmbr($all_hds->{hds}[0]);
    add2hash_($bootloader, arch() =~ /ppc/ ?
	{
	 defaultos => "linux",
	 entries => [],
	 'init-message' => "Welcome to Mandriva Linux!",
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
	 compact => 1,
	 color => 'black/cyan yellow/cyan',
	 'menu-scheme' => 'wb:bw:wb:bw'
         ),
	});

    suggest_message_text($bootloader);

    add2hash_($bootloader, { memsize => $1 }) if cat_("/proc/cmdline") =~ /\bmem=(\d+[KkMm]?)(?:\s.*)?$/;
    if (my ($s, $port, $speed) = cat_("/proc/cmdline") =~ /console=(ttyS(\d),(\d+)\S*)/) {
	log::l("serial console $s $port $speed");
	set_append_with_key($bootloader, console => $s);
	any::set_login_serial_console($port, $speed);
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

    #- remove existing failsafe, do not care if the previous one was modified by the user?
    @{$bootloader->{entries}} = grep { $_->{label} ne 'failsafe' } @{$bootloader->{entries}};

    add_kernel($bootloader, $kernels[0],
	       { root => $root, label => 'failsafe', append => 'failsafe' });

    if (arch() =~ /ppc/) {
	#- if we identified a MacOS partition earlier - add it
	if (defined $partition_table::mac::macos_part) {
	    add_entry($bootloader,
		      {
		       type => "macos",
		       kernel_or_dev => $partition_table::mac::macos_part
		      });
	}
    } elsif (arch() !~ /ia64/) {
	#- search for dos (or windows) boot partition. Do not look in extended partitions!
	my @windows_boot_parts =
	  grep { isFat_or_NTFS($_) && member(fs::type::fs_type_from_magic($_), 'vfat', 'ntfs') }
	    map { @{$_->{primary}{normal}} } @{$all_hds->{hds}};
	each_index {
	    add_entry($bootloader,
		      {
		       type => 'other',
		       kernel_or_dev => "/dev/$_->{device}",
		       label => 'windows' . ($::i || ''),
		       table => "/dev/$_->{rootDevice}",
		       makeactive => 1,
		      });
	} @windows_boot_parts;
    }

    my @preferred = map { "linux-$_" } 'p3-smp-64GB', 'secure', 'enterprise', 'smp', 'i686-up-4GB';
    if (my $preferred = find { get_label($_, $bootloader) } @preferred) {
	$bootloader->{default} ||= $preferred;
    }
    $bootloader->{default} ||= "linux";
    $bootloader->{method} ||= first(method_choices($all_hds, 1));
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

sub config_files() {
    my %files = (
	lilo => '/etc/lilo.conf',
	grub => '/boot/grub/menu.lst',
	grub_install => '/boot/grub/install.sh',
    );
    
    map_each { 
	my $content = cat_("$::prefix/$::b");
	{ main_method => main_method($::a), name => $::a, file => $::b, content => $content };
    } %files;
}

sub method2text {
    my ($method) = @_;
    +{
	'lilo-menu'    => N("LILO with text menu"),
	'grub-graphic' => N("GRUB with graphical menu"),
	'grub-menu'    => N("GRUB with text menu"),
	'yaboot'       => N("Yaboot"),
	'silo'         => N("SILO"),
    }->{$method};
}

sub method_choices_raw {
    my ($b_prefix_mounted) = @_;
    detect_devices::is_xbox() ? 'cromwell' :
    arch() =~ /ppc/ ? 'yaboot' : 
    arch() =~ /ia64/ ? 'lilo' : 
    arch() =~ /sparc/ ? 'silo' : 
      (
       if_(!$b_prefix_mounted || whereis_binary('grub', $::prefix), 
	   'grub-graphic', 'grub-menu'),
       if_(!$b_prefix_mounted || whereis_binary('lilo', $::prefix), 
	   'lilo-menu'),
      );
}
sub method_choices {
    my ($all_hds, $b_prefix_mounted) = @_;
    my $fstab = [ fs::get::fstab($all_hds) ];
    my $root_part = fs::get::root($fstab);
    my $have_dmraid = find { fs::type::is_dmraid($_) } @{$all_hds->{hds}};

    grep {
	(!/lilo/ || !isLoopback($root_part) && !$have_dmraid)
	  && (!/grub/ || !isRAID($root_part))
	  && (!/grub-graphic/ || cat_("/proc/cmdline") !~ /console=ttyS/);
    } method_choices_raw($b_prefix_mounted);
}
sub main_method_choices {
    my ($b_prefix_mounted) = @_;
    uniq(map { main_method($_) } method_choices_raw($b_prefix_mounted));
}
sub configured_main_methods() {
    my @bad_main_methods = map { if_(!$_->{content}, $_->{main_method}) } config_files();
    difference2([ main_method_choices(1) ], \@bad_main_methods);
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
	    log::l("creating symlink $_/source");
	    symlink "/usr/src/linux-$version", "$_/source";
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

    if ($bootloader->{message_text}) {
	eval { output("$::prefix/boot/message", $bootloader->{message_text}) }
	  and $bootloader->{message} = '/boot/message';
    }

    my @conf;

    if (!get_label($bootloader->{default}, $bootloader)) {
	log::l("default bootloader entry $bootloader->{default} is invalid, choosing another one");
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
	    push @entry_conf, grep { $entry->{$_} } qw(read-write read-only);
	    push @conf, map { "\t$_" } @entry_conf;
	} else {
	    my $of_dev = dev2yaboot($entry->{kernel_or_dev});
	    push @conf, "$entry->{type}=$of_dev";
	}
    }
    my $f = "$::prefix/etc/yaboot.conf";
    log::l("writing yaboot config to $f");
    renamef($f, "$f.old");
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
    if (defined $partition_table::mac::new_bootstrap) {
	run_program::run("hformat", $bootloader->{boot}) or die "hformat failed";
    }	
    my $error;
    run_program::rooted($::prefix, "/usr/sbin/ybin", "2>", \$error) or die "ybin failed: $error";
}

sub install_cromwell { 
    my ($_bootloader, $_all_hds) = @_;
    log::l("XBox/Cromwell - nothing to install...");
}
sub write_cromwell { 
    my ($_bootloader, $_all_hds) = @_;
    log::l("XBox/Cromwell - nothing to write...");
}
sub when_config_changed_cromwell {
    my ($_bootloader) = @_;
    log::l("XBox/Cromwell - nothing to do...");
}

sub simplify_label {
    my ($label) = @_;

    length($label) < 31 or $label =~ s/\.//g;

    $label = substr($label, 0, 31); #- lilo does not handle more than 31 char long labels
    $label =~ s/ /_/g; #- lilo does not support blank character in image names, labels or aliases
    $label;
}

sub make_label_lilo_compatible {
    my ($label) = @_;
    '"' . simplify_label($label) . '"';
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
	    $file;
	}
    };

    my $quotes = sub {
	my ($s) = @_;
	$s =~ s/"/\\"/g;
	qq("$s");
    };

    my $quotes_if_needed = sub {
	my ($s) = @_;
	$s =~ /["=\s]/ ? $quotes->($s) : $s;
    };
    

    my @sorted_hds = sort_hds_according_to_bios($bootloader, $all_hds);

    if (is_empty_hash_ref($bootloader->{bios} ||= {}) && $all_hds->{hds}[0] != $sorted_hds[0]) {
	log::l("Since we're booting on $sorted_hds[0]{device}, make it bios=0x80");
	$bootloader->{bios} = { "/dev/$sorted_hds[0]{device}" => '0x80' };
    }

    my @conf;

    #- normalize: RESTRICTED is only valid if PASSWORD is set
    delete $bootloader->{restricted} if !$bootloader->{password};
    foreach my $entry (@{$bootloader->{entries}}) {
	delete $entry->{restricted} if !$entry->{password} && !$bootloader->{password};
    }
    if (get_append_with_key($bootloader, 'console') =~ /ttyS(.*)/) {
	$bootloader->{serial} ||= $1;
    }

    if (!get_label($bootloader->{default}, $bootloader)) {
	log::l("default bootloader entry $bootloader->{default} is invalid, choosing another one");
	$bootloader->{default} = $bootloader->{entries}[0]{label};
    }
    push @conf, "# File generated by DrakX/drakboot";
    push @conf, "# WARNING: do not forget to run lilo after modifying this file\n";
    push @conf, "default=" . make_label_lilo_compatible($bootloader->{default}) if $bootloader->{default};
    push @conf, map { $_ . '=' . $quotes_if_needed->($bootloader->{$_}) } grep { $bootloader->{$_} } qw(boot root map install serial vga keytable raid-extra-boot menu-scheme);
    push @conf, grep { $bootloader->{$_} } qw(linear geometric compact prompt nowarn restricted static-bios-codes);
    push @conf, "append=" . $quotes->($bootloader->{append}) if $bootloader->{append};
    push @conf, "password=" . $bootloader->{password} if $bootloader->{password}; #- also done by msec
    push @conf, "timeout=" . round(10 * $bootloader->{timeout}) if $bootloader->{timeout};
    
    push @conf, "message=$bootloader->{message}" if $bootloader->{message};

    push @conf, "ignore-table" if any { $_->{unsafe} && $_->{table} } @{$bootloader->{entries}};

    push @conf, map_each { "disk=$::a bios=$::b" } %{$bootloader->{bios}};

    foreach my $entry (@{$bootloader->{entries}}) {
	my $mbootpack_file = get_mbootpack_filename($entry);
        if ($mbootpack_file && !build_mbootpack($entry)) {
	    warn "mbootpack is required for xen but unavailable, skipping\n";
	    next;
	}

	push @conf, "$entry->{type}=" . $file2fullname->($mbootpack_file || $entry->{kernel_or_dev});
	my @entry_conf;
	push @entry_conf, "label=" . make_label_lilo_compatible($entry->{label}) if $entry->{label};

	if ($entry->{type} eq "image") {		
	    push @entry_conf, 'root=' . $quotes_if_needed->($entry->{root}) if $entry->{root} && !$entry->{xen};
	    push @entry_conf, "initrd=" . $file2fullname->($entry->{initrd}) if $entry->{initrd} && !$mbootpack_file;
	    my $append = join(' ', if_($entry->{xen_append}, $entry->{xen_append}),
	                           if_($entry->{xen}, '--', 'root=' . $entry->{root}),
	                           if_($entry->{append}, $entry->{append}));
	    push @entry_conf, "append=" . $quotes->($append) if $append;
	    push @entry_conf, "vga=$entry->{vga}" if $entry->{vga};
	    push @entry_conf, grep { $entry->{$_} } qw(read-write read-only optional);
	} else {
	    delete $entry->{unsafe} if $entry->{table}; #- we can't have both
	    push @entry_conf, map { "$_=$entry->{$_}" } grep { $entry->{$_} } qw(table boot-as);
	    push @entry_conf, grep { $entry->{$_} } qw(unsafe master-boot);
		
	    if ($entry->{table}) {
		#- hum, things like table=c: are needed for some os2 cases,
		#- in that case $hd below is undef
		my $hd = fs::get::device2part($entry->{table}, $all_hds->{hds});
		if ($hd && $hd != $sorted_hds[0]) {		       
		    #- boot off the nth drive, so reverse the BIOS maps
		    my $nb = sprintf("0x%x", 0x80 + (find_index { $hd == $_ } @sorted_hds));
		    $entry->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
		}
	    }
	    if ($entry->{mapdrive}) {
		push @entry_conf, map_each { "map-drive=$::a", "   to=$::b" } %{$entry->{mapdrive}};
	    }
	}
	push @entry_conf, "password=$entry->{password}" if $entry->{password};
	push @entry_conf, "restricted" if $entry->{restricted};

	push @conf, map { "\t$_" } @entry_conf;
    }
    my $f = arch() =~ /ia64/ ? "$::prefix/boot/efi/elilo.conf" : "$::prefix/etc/lilo.conf";

    log::l("writing lilo config to $f");
    renamef($f, "$f.old");
    output_with_perm($f, $bootloader->{password} ? 0600 : 0644, map { "$_\n" } @conf);
}

sub install_lilo {
    my ($bootloader, $all_hds) = @_;

    if (my ($install) = $bootloader->{method} =~ /lilo-(text|menu)/) {
	$bootloader->{install} = $install;
    } else {
	delete $bootloader->{install};
    }
    if ($bootloader->{message_text}) {
	output("$::prefix/boot/message-text", $bootloader->{message_text});
    }
    my $message = "message-text";
    if (-r "$::prefix/boot/$message") {
	symlinkf $message, "$::prefix/boot/message";
	$bootloader->{message} = '/boot/message';
    }

    #- ensure message does not contain the old graphic format
    if ($bootloader->{message} && -s "$::prefix$bootloader->{message}" > 65_000) {
	output("$::prefix$bootloader->{message}", '');
    }

    write_lilo($bootloader, $all_hds);

    when_config_changed_lilo($bootloader);

    configure_kdm_BootManager('Lilo');
}

sub install_raw_lilo {
    my ($o_force_answer) = @_;

    my $error;
    my $answer = $o_force_answer || '';
    run_program::rooted($::prefix, "echo $answer | lilo", '2>', \$error) or die "lilo failed: $error";
}

sub when_config_changed_lilo {
    my ($bootloader) = @_;
    if (!$::testing && arch() !~ /ia64/ && $bootloader->{method} =~ /lilo/) {
	log::l("Installing boot loader on $bootloader->{boot}...");
	install_raw_lilo($bootloader->{force_lilo_answer});
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
    my $bios = eval { find_index { $hd eq $_ } @$sorted_hds };
    if (defined $bios) {
	my $part_string = defined $part_nb ? ',' . ($part_nb - 1) : '';    
	"(hd$bios$part_string)";
    } else {
	undef;
    }
}

sub read_grub_device_map() {
    my %grub2dev = map { m!\((.*)\)\s+/dev/(.*)$! } cat_("$::prefix/boot/grub/device.map");
    \%grub2dev;
}
sub write_grub_device_map {
    my ($legacy_floppies, $sorted_hds) = @_;
    my $f = "$::prefix/boot/grub/device.map";
    renamef($f, "$f.old");
    output($f,
	   (map_index { "(fd$::i) /dev/$_->{device}\n" } @$legacy_floppies),
	   (map_index { "(hd$::i) /dev/$_->{device}\n" } @$sorted_hds));
}

sub grub2dev_and_file {
    my ($grub_file, $grub2dev, $o_block_device) = @_;
    my ($grub_dev, $rel_file) = $grub_file =~ m!\((.*?)\)/?(.*)! or return;
    my ($hd, $part) = split(',', $grub_dev);
    $grub2dev->{$hd} or internal_error("$hd has no mapping in device.map (when translating $grub_file)");
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
	if (my $part = fs::get::device2part($device, $fstab)) {
	    my $mntpoint = $part->{mntpoint} || '';
	    ($mntpoint eq '/' ? '' : $mntpoint) . '/' . $rel_file;
	} else {
	    log::l("ERROR: unknown device $device (computed from $grub_file)");
	    $grub_file;
	}
    } else {
	$grub_file;
    }
}

sub boot_copies_dir() { '/boot/copied' }
sub create_copy_in_boot {
    my ($file) = @_;

    my $s = $file;
    $s =~ s!/!_!g;
    my $file2 = boot_copies_dir() . "/$s";

    log::l("$file is not available at boot time, creating a copy ($file2)");
    mkdir_p(boot_copies_dir());
    output("$file2.link", $file . "\n");
    update_copy_in_boot("$file2.link");

    $file2;
}
sub update_copy_in_boot {
    my ($link) = @_;
    my $orig = chomp_(cat_("$::prefix$link"));
    (my $dest = $link) =~ s/\.link$// or internal_error("update_copy_in_boot: $link");
    if (-e "$::prefix$orig") {
	log::l("updating $dest from $orig");
	cp_af("$::prefix$orig", "$::prefix$dest");
    } else {
	log::l("removing $dest since $orig does not exist anymore");
	unlink "$::prefix$link", "$::prefix$orig";
    }
}

sub write_grub {
    my ($bootloader, $all_hds) = @_;

    my $fstab = [ fs::get::fstab($all_hds) ]; 
    my @legacy_floppies = detect_devices::floppies();
    my @sorted_hds = sort_hds_according_to_bios($bootloader, $all_hds);
    write_grub_device_map(\@legacy_floppies, \@sorted_hds);

    my $file2grub; $file2grub = sub {
	my ($file) = @_;
	if ($file =~ m!^\(.*\)/!) {
	    $file; #- it's already in grub format
	} else {
	    my ($part, $rel_file) = fs::get::file2part($fstab, $file, 'keep_simple_symlinks');
	    if (my $grub = device2grub($part, \@sorted_hds)) {
		$grub . $rel_file;
	    } elsif (!begins_with($file, '/boot/')) {
		log::l("$file is on device $part->{device} which is not available at boot time. Copying it");
		$file2grub->(create_copy_in_boot($file));
	    } else {
		log::l("ERROR: $file is on device $part->{device} which is not available at boot time. Defaulting to a dumb value");
		"(hd0,0)$file";
	    }
	}
    };

    if (get_append_with_key($bootloader, 'console') =~ /ttyS(\d),(\d+)/) {
	$bootloader->{serial} ||= "--unit=$1 --speed=$2";
	$bootloader->{terminal} ||= "--timeout=" . ($bootloader->{timeout} || 0) . " console serial";
    } elsif ($bootloader->{method} eq 'grub-graphic') {
	my $bin = '/usr/sbin/grub-gfxmenu';
	if ($bootloader->{gfxmenu} eq '' && -x "$::prefix/usr/sbin/grub-gfxmenu") {
	    my $locale = $::o->{locale} || do { require lang; lang::read() };
	    run_program::rooted($::prefix, $bin, '--lang', $locale->{lang}, '--update-gfxmenu');
	    $bootloader->{gfxmenu} ||= '/boot/gfxmenu';
	}
	#- not handled anymore
	delete $bootloader->{$_} foreach qw(splashimage viewport shade);
    } else {
	delete $bootloader->{gfxmenu};
    }

    {
	my @conf;

	push @conf, map { "$_ $bootloader->{$_}" } grep { $bootloader->{$_} } qw(timeout color password serial shade terminal viewport background foreground);
	push @conf, map { $_ . ' ' . $file2grub->($bootloader->{$_}) } grep { $bootloader->{$_} } qw(gfxmenu);

	eval {
	    push @conf, "default " . (find_index { $_->{label} eq $bootloader->{default} } @{$bootloader->{entries}});
	};

	foreach my $entry (@{$bootloader->{entries}}) {
	    my $title = "\ntitle $entry->{label}";

	    if ($entry->{type} eq "image") {
		push @conf, $title;
		push @conf, grep { $entry->{$_} } 'lock';
		push @conf, join(' ', 'kernel', $file2grub->($entry->{xen}), $entry->{xen_append}) if $entry->{xen};

		my $vga = $entry->{vga} || $bootloader->{vga};
		push @conf, join(' ', $entry->{xen} ? 'module' : 'kernel', 
		       $file2grub->($entry->{kernel_or_dev}),
		       $entry->{xen} ? '' : 'BOOT_IMAGE=' . simplify_label($entry->{label}),
		       if_($entry->{root}, $entry->{root} =~ /loop7/ ? "root=707" : "root=$entry->{root}"), #- special to workaround bug in kernel (see #ifdef CONFIG_BLK_DEV_LOOP)
		       $entry->{append},
		       if_($entry->{'read-write'}, 'rw'),
		       if_($vga && $vga ne "normal", "vga=$vga"));
		push @conf, "module " . $_ foreach @{$entry->{modules} || []};
		push @conf, join(' ', $entry->{xen} ? 'module' : 'initrd', $file2grub->($entry->{initrd})) if $entry->{initrd};
	    } else {
		my $dev = eval { device_string2grub($entry->{kernel_or_dev}, \@legacy_floppies, \@sorted_hds) };
		if (!$dev) {
		    log::l("dropping bad entry $entry->{label} for unknown device $entry->{kernel_or_dev}");
		    next;
		}
		push @conf, $title;
		push @conf, join(' ', $entry->{grub_noverify} ? 'rootnoverify' : 'root', $dev);

		if ($entry->{table}) {
		    if (my $hd = fs::get::device2part($entry->{table}, \@sorted_hds)) {
			if (my $bios = find_index { $hd eq $_ } @sorted_hds) {
			    #- boot off the nth drive, so reverse the BIOS maps
			    my $nb = sprintf("0x%x", 0x80 + $bios);
			    $entry->{mapdrive} ||= { '0x80' => $nb, $nb => '0x80' }; 
			}
		    }
		}
		if ($entry->{mapdrive}) {
		    push @conf, map_each { "map ($::b) ($::a)" } %{$entry->{mapdrive}};
		}
		push @conf, "makeactive" if $entry->{makeactive};
		push @conf, "chainloader +1";
	    }
	}
	my $f = "$::prefix/boot/grub/menu.lst";
	log::l("writing grub config to $f");
	renamef($f, "$f.old");
	output($f, map { "$_\n" } @conf);
    }
    {
	my $f = "$::prefix/boot/grub/install.sh";
	my $boot_dev = device_string2grub($bootloader->{boot}, \@legacy_floppies, \@sorted_hds);
	my $files_dev = device2grub(fs::get::root_($fstab, 'boot'), \@sorted_hds);
	renamef($f, "$f.old");
	output_with_perm($f, 0755,
"grub --device-map=/boot/grub/device.map --batch <<EOF
root $files_dev
setup --stage2=/boot/grub/stage2 $boot_dev
quit
EOF
");
    }

    check_enough_space();
}

sub configure_kdm_BootManager {
    my ($name) = @_;
    eval { common::update_gnomekderc_no_create("$::prefix/etc/kde/kdm/kdmrc", 'Shutdown' => (
	BootManager => $name
    )) };
}

sub install_grub {
    my ($bootloader, $all_hds) = @_;

    write_grub($bootloader, $all_hds);

    if (!$::testing) {
	my @files = grep { /(stage1|stage2|_stage1_5)$/ } glob("$::prefix/lib/grub/*/*");
	cp_af(@files, "$::prefix/boot/grub");
	install_raw_grub(); 
    }

    configure_kdm_BootManager('Grub');
}
sub install_raw_grub() {
    log::l("Installing boot loader...");
    my $error;
    run_program::rooted($::prefix, "sh", '/boot/grub/install.sh', "2>", \$error) or die "grub failed: $error";
}

sub when_config_changed_grub {
    my ($_bootloader) = @_;
    #- do not do anything

    update_copy_in_boot($_) foreach glob($::prefix . boot_copies_dir() . '/*.link');
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
	die N("You can not install the bootloader on a %s partition\n", $part->{fs_type})
	  if $part->{fs_type} eq 'xfs';
    }
    $bootloader->{keytable} = keytable($bootloader->{keytable});
    action($bootloader, 'install', $all_hds);
}

sub ensure_pkg_is_installed {
    my ($do_pkgs, $bootloader) = @_;

    my $main_method = bootloader::main_method($bootloader->{method});
    if ($main_method eq 'grub' || $main_method eq 'lilo') {
	$do_pkgs->ensure_binary_is_installed($main_method, $main_method, 1) or return 0;
	if ($bootloader->{method} eq 'grub-graphic') {
	    $do_pkgs->ensure_is_installed('mandriva-gfxboot-theme', '/usr/share/gfxboot/themes/Mandriva/boot/message', 1) or return 0;
	}
    }
    1;
}

sub update_for_renumbered_partitions {
    my ($in, $renumbering, $all_hds) = @_;

    my @configs = grep { $_->{content} } config_files();
    $_->{new} = $_->{orig} = $_->{content} foreach @configs;

    my @sorted_hds; {
 	my $grub2dev = read_grub_device_map();
	map_each {
	    $sorted_hds[$1] = fs::get::device2part($::b, $all_hds->{hds}) if $::a =~ /hd(\d+)/;
	} %$grub2dev;
    }

    #- NB: we make the changes with an added string inside so that hda5 is only renamed once to hda6

    foreach (@$renumbering) {
	my ($old, $new) = @$_;
	log::l("renaming $old -> $new");
	(my $lnew = $new) =~ s/(\d+)$/__DRAKX_DONE__$1/;
	$_->{new} =~ s/\b$old/$lnew/g foreach @configs;

	any { $_->{name} eq 'grub' } @configs or next;

	my ($old_grub, $new_grub) = map { device_string2grub($_, [], \@sorted_hds) } $old, $new;
	log::l("renaming $old_grub -> $new_grub");
	(my $lnew_grub = $new_grub) =~ s/\)$/__DRAKX_DONE__)/;
	$_->{new} =~ s/\Q$old_grub/$lnew_grub/g foreach @configs;
    }

    $_->{new} =~ s/__DRAKX_DONE__//g foreach @configs;

    my @changed_configs = grep { $_->{orig} ne $_->{new} } @configs or return 1; # no need to update

    $in->ask_okcancel('', N("Your bootloader configuration must be updated because partition has been renumbered")) or return;

    foreach (@changed_configs) {
	renamef("$::prefix/$_->{file}", "$::prefix/$_->{file}.old");
	output("$::prefix/$_->{file}", $_->{new});
    }

    my $main_method = detect_main_method($all_hds);
    my @needed = map { 
	$_ eq 'grub' ? 'grub_install' : $_;
    } $main_method ? $main_method : ('lilo', 'grub');

    if (intersection(\@needed, [ map { $_->{name} } @changed_configs ])) {
	$in->ask_warn('', N("The bootloader can not be installed correctly. You have to boot rescue and choose \"%s\"", 
			    N("Re-install Boot Loader")));
    }
    1;
}

1;
