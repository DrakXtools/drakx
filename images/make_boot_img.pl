#!/usr/bin/perl

use MDK::Common;
use lib "/usr/lib/libDrakX";
use keyboard;

use Config;
use FileHandle;
use MDK::Common;
use POSIX;
use Carp;


Config->import;
my ($arch) = $Config{archname} =~ /(.*?)-/;

my $default_append = '';
my $default_acpi = '';
my $default_vga = "vga=791 splash quiet";
my $timeout = 150;
my $isolinux_bin = '/usr/lib/syslinux/isolinux.bin';
my $lib = $arch eq 'x86_64' ? 'lib64' : 'lib';
my $wordsize = $arch eq 'x86_64' ? '64' : '32';

my $tmp_mnt = "$ENV{'PWD'}/tmp_mnt";
my $tmp_initrd = "$ENV{'PWD'}/tmp_initrd";
my $compress_filter;

if ("@ARGV") {
    if ($ARGV[0] eq "--compress") {
	shift @ARGV;
	$compress_filter = $ARGV[0];
	shift @ARGV;
    }
} else {
    #usage();
    #exit(1);
}

my $target = basename($ARGV[0]);

my $sudo;
if ($>) {
    $sudo = "sudo";
    $ENV{PATH} = "/sbin:/usr/sbin:$ENV{PATH}";
}

sub __ { print @_, "\n"; system(@_) }
sub _ { __ @_; $? and croak "'" . join(' ', @_) . "failed ($?)\n" }
sub mke2fs { 
    my ($f) = @_;
    _ "/sbin/mke2fs -q -m 0 -F -s 1 $f";
    _ "/sbin/tune2fs -c 0 -U clear -T 1970010101 $f";
}

_ "mkdir -p $tmp_mnt";
mkdir "images";

my @kernels = chomp_(cat_('all.kernels/.list'));

my @all_images = (
		  if_($arch =~ /i.86/, 'isolinux', 'boot.iso', 'hd_grub.img'),
		  if_($arch =~ /x86_64/, 'isolinux', 'boot.iso', 'hd_grub.img'),
		  if_($arch =~ /ia64/, 'all.img'),
		  if_($arch =~ /ppc/, 'all.img'),
		 );

my @images = @ARGV ? @ARGV : map { "images/$_" } @all_images;

if ($target eq "hd_grub.img") {
	hd_grub($ARGV[0]);
} elsif ($target eq 'all.rdz') {
	initrd('all', '', $ARGV[0]);
} elsif ($target eq 'modules.rdz') {
	grub("grub", \@kernels);
} elsif ($target eq 'grub') {
	grub($ARGV[0], \@kernels);
} elsif ($target eq "boot.iso") {
	boot_iso($ARGV[0], \@kernels);
}

sub usage () {
    print "Usage: make_boot_img [--compress <filter>]\n";

    exit(1);
}

sub syslinux_color {
    "0" . {
	default => '7',
	blue    => '9',
	green   => 'a',
	red     => 'c',
	yellow  => 'e',
	white   => 'f',
    }->{$_[0]} || die "unknown color $_[0]\n";
}

sub syslinux_msg { 
    my ($msg_xml_file, @more_text) = @_;

    require XML::Parser;

    sub xml_tree2syslinux {
	my ($current_color, $tree) = @_;
	my (undef, @l) = @$tree;
	join('', map {
	    my ($type, $val) = @$_;
	    if ($type eq '0') {
		$val;
	    } else {
		syslinux_color($type) . xml_tree2syslinux($type, $val) . syslinux_color($current_color);
	    }
	} group_by2(@l));
    }

    print "parsing $msg_xml_file\n";
    my $tree = XML::Parser->new(Style => 'Tree')->parsefile($msg_xml_file);
    $tree->[0] eq 'document' or die "bad file $msg_xml_file\n";
    my $text = xml_tree2syslinux('default', $tree->[1]);

    pack("C*", 0x0E, 0x80, 0x03, 0x00) . ""
      . $text . join('', @more_text)
      . "\n" . syslinux_color('red') . "[F1-Help] [F2-Advanced Help]" . syslinux_color('default') . "\n";
}

sub syslinux_cfg_init {
    my $default = 'load';

    my $header = <<EOF;
default load
timeout $timeout
display help.msg
implicit 0

SERIAL 0

label load
	com32 ifcpu.c32
	append 64 -- 64 -- 32

label 32 
	CONFIG 32.cfg

label 64
	CONFIG 64.cfg

EOF
}

sub syslinux_cfg {
    my ($entries, $b_gfxboot, $type) = @_;
    my $default = 'linux';

    my $header = "default $default\n";
    if ($type ne 'cdrom') {
	$header .= <<EOF;
prompt 1
timeout $timeout
display help.msg
implicit 1
EOF
    }

    $header .= <<EOF;
label harddisk
  localboot 0x80
EOF

    my $header_gfxboot = <<EOF;
UI gfxboot.c32 bootlogo
EOF

    my $header_non_gfxboot = <<EOF;
F1 help.msg
F2 advanced.msg
F3 boot.msg
EOF

    my @l = map {
	$_->{append} =~ s/\s+/ /g;
	"label $_->{label}\n" .
	"  kernel $_->{kernel}\n" .
	($_->{initrd} ? "  append initrd=$_->{initrd} $_->{append}\n" : '');
    } @$entries;

    $header . ($b_gfxboot ? $header_gfxboot : $header_non_gfxboot) . join('', @l);
}

sub grub_cfg {
    my ($entries, $b_gfxboot, $type) = @_;
    my $default = 'linux';

    my $header = "default $default\n";
    if ($type ne 'cdrom') {
	$header .= <<EOF;
prompt 1
timeout $timeout
display help.msg
implicit 1
EOF
    }

    $header .= <<EOF;
label harddisk
  localboot 0x80
EOF

    my $header_gfxboot = <<EOF;
UI gfxboot.c32 bootlogo
EOF

    my $header_non_gfxboot = <<EOF;
F1 help.msg
F2 advanced.msg
F3 boot.msg
EOF

    my @l = map {
	$_->{append} =~ s/\s+/ /g;
	"label $_->{label}\n" .
	"  kernel $_->{kernel}\n" .
	($_->{initrd} ? "  append initrd=$_->{initrd} $_->{append}\n" : '');
    } @$entries;

    $header . ($b_gfxboot ? $header_gfxboot : $header_non_gfxboot) . join('', @l);
}

sub grub {
    my ($dir, $kernels) = @_;

    _ "install -m644 grub_data/grub.cfg -D $dir/boot/grub/grub.cfg";
    _ "install -m644 grub_data/themes/Moondrake/theme.txt -D $dir/boot/grub/themes/Moondrake/theme.txt";
    _ "install -m644 grub_data/themes/Moondrake/star_w.png -D $dir/boot/grub/themes/Moondrake/star_w.png";
    _ "install -m644 /usr/share/gfxboot/themes/Moondrake/install/back.jpg -D $dir/boot/grub/themes/Moondrake/background.jpg";
    mkdir_p("$dir/boot/grub/fonts/");
    _ "grub2-mkfont -o $dir/boot/grub/fonts/dejavu.pf2 /usr/share/fonts/TTF/dejavu/DejaVuSans-Bold.ttf";

    @$kernels or die "grub: no kernel\n";

    each_index {
	mkdir "$dir/boot/alt$::i/$wordsize", 0755;
	_ "install -m644 all.kernels/$_/vmlinuz -D $dir/boot/alt$::i/$wordsize/vmlinuz";
	modules('all', "$_", "images/modules.rdz-$_");
	rename("images/modules.rdz-$_", "$dir/boot/alt$::i/$wordsize/modules.rdz");
    } @$kernels;

    _ "install -m 644 -D /boot/memtest* $dir/boot/memtest";
}

sub initrd {
    my ($type, $I, $img) = @_;
    my $stage1_root = $ENV{USE_LOCAL_STAGE1} ? "../mdk-stage1" : "/usr/$lib/drakx-installer/binaries";

    _ "rm -rf $tmp_initrd";
    mkdir_p("$tmp_initrd$_") foreach qw(/etc /firmware /lib /mnt /sbin /tmp /var/run);
    symlink "../modules", "$tmp_initrd/lib/modules";
    symlink "../firmware", "$tmp_initrd/lib/firmware";

    symlink "/proc/mounts", "$tmp_initrd/etc/mtab";
    symlink "../tmp", "$tmp_initrd/var/run";
    _ "install -D /usr/share/terminfo/l/linux $tmp_initrd/usr/share/terminfo/l/linux";
    _ "install -d $tmp_initrd/usr/share/ldetect-lst";
    foreach ('pcitable', 'usbtable') {
        _ "zcat /usr/share/ldetect-lst/$_.gz > $tmp_initrd/usr/share/ldetect-lst/$_";
    }
    _ "install -D /usr/share/pci.ids $tmp_initrd/usr/share/pci.ids";
    foreach ("dkms-modules.alias", "fallback-modules.alias", "/lib/module-init-tools/ldetect-lst-modules.alias") {
        my $file = m!^/! ? $_ : "/usr/share/ldetect-lst/$_";
        _ "install -D $file $tmp_initrd$file";
    }
    foreach my $firm (glob_("all.kernels$I/$img/firmware/*")) {
        my $dest=$firm;
        $dest =~ s|all.kernels$I/$img/||;
        _ "cp -a $firm $tmp_initrd/$dest";
    };

    my $issue = `linux_logo -l`;

    $issue .= <<EOF;

		[1;37;40mRescue Disk[0m

$ENV{DISTRIB_DESCR}

Use [1;33;40mloadkeys[0m to change your keyboard layout (eg: loadkeys fr)
Use [1;33;40mmodprobe[0m to load modules (eg: modprobe snd-card-fm801)
Use [1;33;40mdrvinst[0m to install drivers according to detected devices
Use [1;33;40mblkid[0m to list your partitions with types
Use [1;33;40mstartssh[0m to start an ssh daemon
Use [1;33;40mrescue-gui[0m to go back to the rescue menu

EOF

     output("$tmp_initrd/etc/issue", $issue);

     _ "../tools/install-xml-file-list list.xml $tmp_initrd";

    _ "cp -r tree/* $tmp_initrd";

    if (0) {
	_ "install -m644 tree/etc/mdev.conf		-D $tmp_initrd/etc/mdev.conf";
	_ "install -m755 tree/lib/mdev/dvbdev		-D $tmp_initrd/lib/mdev/dvbdev";
	_ "install -m755 tree/lib/mdev/ide_links	-D $tmp_initrd/lib/mdev/ide_links";
	_ "install -m755 tree/lib/mdev/usbdev		-D $tmp_initrd/lib/mdev/usbdev";
	_ "install -m755 tree/lib/mdev/usbdisk_link	-D $tmp_initrd/lib/mdev/usbdisk_link";
    }

    my @busybox_links = split("\n", `$tmp_initrd/usr/bin/busybox --list-full`);
    foreach my $bin (@busybox_links) {
	    if (not -e "$tmp_initrd/$bin") {
		    _ "mkdir -p `dirname $tmp_initrd/$bin`; ln $tmp_initrd/usr/bin/busybox $tmp_initrd/$bin";
	    }
    }

    _ "install -m755 $stage1_root/stage1 -D $tmp_initrd/sbin/stage1";
    foreach (cat_("aliases")) {
	    chomp; my ($f, $dest) = split;
	    _ "ln $tmp_initrd$f $tmp_initrd$dest";
    }

    my $LANGUAGE = "C";
    substInFile {
	    $_ = "export LANGUAGE=$LANGUAGE\n" . "export LC_ALL=$LANGUAGE\n" if /^#LANGUAGE/;	
    } "$tmp_initrd/etc/init.d/rc.stage2";

    # XXX: prevent this from being added to begin with
    _ "rm -rf $tmp_initrd/usr/share/locale/";

    _ "
    for f in `find $tmp_initrd`; do
	    if [ -n \"`file \$f|grep 'not stripped'`\" ]; then
		    strip \$f
	    fi
    done
    ";

    # ka deploy need some files in all.rdz 
    {
	mkdir_p("$tmp_initrd/$_") foreach qw(dev etc/sysconfig/network-scripts media/cdrom media/floppy proc run sys var/log var/tmp tmp/newroot tmp/stage2);
	#cp_af("/usr/bin/ka-d-client", "$tmp_initrd/ka/ka-d-client");

	if ($ENV{DEBUG_INSTALL}) {
		foreach my $f (split("\n", `rpm -ql valgrind`)) {
			_ "test -d $f || install $f -D ${tmp_initrd}$f";
		}
		foreach my $f (("libc.so.6", "libpthread.so.0", "ld-linux-" . ($wordsize eq "64" ? "x86-64" : "") . ".so.2")) {
			_ "install -m755 /$lib/$f -D $tmp_initrd/$lib/$f";
		}
	}
    }
    my $comp = $compress_filter ? $compress_filter : "xz --x86 --lzma2 -v9e --check=crc32";

    mkdir_p(dirname("$ENV{PWD}/$img"));
    _ "(cd $tmp_initrd; find . | cpio -o -H newc --quiet) | $comp > $ENV{PWD}/$img";
    _ "rm -rf $tmp";
    }

sub modules {
    my ($type, $I, $img) = @_;

    _ "rm -rf $tmp_initrd";
    mkdir_p("$tmp_initrd/modules");

    {
	my $modz = "all.kernels/$I";
	mkdir_p("$tmp_initrd/lib/modules/$I");
	__ "tar xC $tmp_initrd/lib/modules/$I -f $modz/${type}_modules.tar";
        _ "cp -f $modz/modules.$_ $tmp_initrd/lib/modules/$I" foreach qw(order builtin);
        substInFile { s,.*/,, } "$tmp_initrd/lib/modules/$I/modules.order";
	_ "/sbin/depmod -b $tmp_initrd $I";
	# depmod keeps only available modules in modules.alias, but we want them all
	_ "cp -f $modz/modules.alias $tmp_initrd/lib/modules/$I";
    }
    my $comp = $compress_filter ? $compress_filter : "xz -v9e --check=crc32";

    mkdir_p(dirname("$ENV{PWD}/$img"));
    _ "(cd $tmp_initrd; find . | cpio -o -H newc --quiet) | $comp > $ENV{PWD}/$img";
    _ "rm -rf $tmp_initrd";
}

sub entries_append {
    my ($type) = @_;

    my $automatic = $type =~ /cdrom/ ? 'automatic=method:cdrom ' : '';
    $automatic .= 'changedisk ' if $type =~ /changedisk/;

    my @simple_entries = (
	linux => $default_vga,
	vgalo => "vga=785",
#	vgame => "vga=788",
	vgahi => "vga=791",
	text => "text",
#	patch => "patch $default_vga",
	rescue => "rescue",
    );
    my @entries = (
        (map { $_->[0] => "$automatic$default_acpi $_->[1]" } group_by2(@simple_entries)),
	noacpi => "$automatic$default_vga acpi=off",
#	restore => "$automatic$default_vga restore",
    );

    map { { label => $_->[0], append => join(' ', grep { $_ } $default_append, $_->[1]) } }
      group_by2(@entries);
}

sub syslinux_cfg_all {
    my ($type, $b_gfxboot) = @_;

    syslinux_cfg([
	(map {
	    { kernel => "alt0/$wordsize/vmlinuz", initrd => "alt0/$wordsize/modules.rdz,all.rdz", %$_ };
	} entries_append($type)),
	(map_index {
	    { label => "alt$::i", kernel => "alt$::i/$wordsize/vmlinuz", initrd => "alt$::i/$wordsize/modules.rdz,all.rdz", 
	      append => join(' ', grep { $_ } $default_append, $default_acpi, $default_vga) };
	} @kernels),
	{ label => 'memtest', kernel => 'memtest' },
	{ label => 'hdt', kernel => 'hdt.c32', append => 'modules=modules.pci' }
    ], $b_gfxboot, $type);
}
sub remove_ending_zero {
    my ($img) = @_;
    _(q(perl -0777 -pi -e 's/\0+$//' ) . $img);
}

sub boot_img_i386 {
    my ($type, $I, $img, $kernel) = @_;

    _ "rm -rf $tmp_mnt"; mkdir $tmp_mnt;
    _ "cat $kernel > $tmp_mnt/vmlinuz";

    output("$tmp_mnt/help.msg", syslinux_msg('help.msg.xml'));
    output("$tmp_mnt/advanced.msg", syslinux_msg('advanced.msg.xml'));

    (my $rdz = $img) =~ s/\.img/.rdz/;
    (my $initrd_type = $type) =~ s/-changedisk//;
    initrd($initrd_type, $I, $rdz);
    my $short_type = substr($type, 0, 8);

    output("$tmp_mnt/syslinux.cfg", 
	   syslinux_cfg([ map {
			    { kernel => 'vmlinuz', initrd => "$short_type.rdz", %$_ };
			} entries_append($type) ]));

    _ "cp -f $rdz $tmp_mnt/$short_type.rdz";
    unlink $rdz;

    # mtools wants the image to be a power of 32
    my $size = max((ceil(chomp_(`du -s -k $tmp_mnt`) / 32) * 32) + 128, 1440);
    _ "dd if=/dev/zero of=$img bs=1k count=$size";

    _ "/sbin/mkdosfs $img";
    _ "mcopy -i $img $tmp_mnt/* ::";
    _ "syslinux $img";
    _ "rm -rf $tmp_mnt";
}

# alias to x86 variant, slightly bigger with images though
sub boot_img_x86_64 { &boot_img_i386 }

sub boot_img_alpha {
    my ($type, $I, $img) = @_;

    __ "$sudo umount $tmp_mnt 2>/dev/null";
    _ "dd if=/dev/zero of=$img bs=1k count=1440";
    mke2fs($img);
    _ "/sbin/e2writeboot $img /boot/bootlx";
    _ "$sudo mount -t ext2 $img $tmp_mnt -o loop";
    _ "cp -f vmlinux.gz $tmp_mnt";
    -f "$type.rdz" ? _ "cp -f $type.rdz $tmp_mnt" : initrd($type, $I, "$tmp_mnt/$type.rdz");

    mkdir "$tmp_mnt/etc", 0777;
    output("$tmp_mnt/etc/aboot.conf", 
"0:vmlinux.gz initrd=$type.rdz rw $default_append $type
1:vmlinux.gz initrd=$type.rdz rw $default_append text $type
");
    _ "sync";
    _ "df $tmp_mnt";
}

sub boot_img_ia64 {
    my ($type, $_I, $img, $kernel) = @_;
	my $rdz = $img; $rdz =~ s/\.img/.rdz/;

    __ "$sudo umount $tmp_mnt 2>/dev/null";
    _ "dd if=/dev/zero of=$img bs=1k count=16384";
    _ "mkdosfs $img";
    _ "$sudo mount -t vfat $img $tmp_mnt -o loop,umask=000";
    _ "$sudo cp -f $kernel $tmp_mnt/vmlinux";
    _ "cp -f $rdz $tmp_mnt/$type.rdz";
    _ "$sudo cp -f tools/ia64/elilo.efi $tmp_mnt";
	output("$tmp_mnt/elilo.conf", qq(
prompt
timeout=50

image=vmlinux
        label=linux
        initrd=$type.rdz
        append=" ramdisk_size=120000"
        read-only

image=vmlinux
        label=rescue
        initrd=$type.rdz
        append=" rescue ramdisk_size=120000"
"));
    _ "sync";
    _ "df $tmp_mnt";

}

sub boot_img_sparc {
    my ($type, $I, $_img) = @_;
    if ($type =~ /^live(.*)/) {
	#- hack to produce directly into /export the needed file for cdrom boot.
	my $dir = "/export";
	my $boot = "boot"; #- non-absolute pathname only!

	_ "mkdir -p $dir/$boot";
	_ "cp -f /boot/cd.b /boot/second.b $dir/$boot";
	_ "cp -f vmlinux$1 $dir/$boot/vmlinux$1";
	-f "live$1.rdz" ? _ "cp -f live$1.rdz $dir/$boot" : initrd($type, $I, "$dir/$boot/live$1.rdz");

	output("$dir/$boot/silo.conf", qq(
partition=1
default=linux
timeout=100
read-write
message=/$boot/boot.msg
image="cat /$boot/boot.msg"
  label=1
  single-key
image="cat /$boot/general.msg"
  label=2
  single-key
image="cat /$boot/expert.msg"
  label=3
  single-key
image="cat /$boot/rescue.msg"
  label=4
  single-key
image="cat /$boot/kickit.msg"
  label=5
  single-key
image="cat /$boot/param.msg"
  label=6
  single-key
image[sun4c,sun4d,sun4m]=/$boot/vmlinux
  label=linux
  alias=install
  initrd=/$boot/live.rdz
  append="ramdisk_size=128000"
image[sun4c,sun4d,sun4m]=/$boot/vmlinux
  label=text
  initrd=/$boot/live.rdz
  append="ramdisk_size=128000 text"
image[sun4c,sun4d,sun4m]=/$boot/vmlinux
  label=expert
  initrd=/$boot/live.rdz
  append="ramdisk_size=128000 expert"
image[sun4c,sun4d,sun4m]=/$boot/vmlinux
  label=ks
  initrd=/$boot/live.rdz
  append="ramdisk_size=128000 ks"
image[sun4c,sun4d,sun4m]=/$boot/vmlinux
  label=rescue
  initrd=/$boot/live.rdz
  append="ramdisk_size=128000 rescue"
image[sun4u]=/$boot/vmlinux64
  label=linux
  alias=install
  initrd=/$boot/live64.rdz
  append="ramdisk_size=128000"
image[sun4u]=/$boot/vmlinux64
  label=text
  initrd=/$boot/live64.rdz
  append="ramdisk_size=128000 text"
image[sun4u]=/$boot/vmlinux64
  label=expert
  initrd=/$boot/live64.rdz
  append="ramdisk_size=128000 expert"
image[sun4u]=/$boot/vmlinux64
  label=ks
  initrd=/$boot/live64.rdz
  append="ramdisk_size=128000 ks"
image[sun4u]=/$boot/vmlinux64
  label=rescue
  initrd=/$boot/live64.rdz
  append="ramdisk_size=128000 rescue"
"));

	output("$dir/$boot/README", "
To Build a Bootable CD-ROM, try:
  genisoimage -R -o t.iso -s /$boot/silo.conf /export
");
    } elsif ($type =~ /^tftprd(.*)/) {
	my $dir = "/export";
	my $boot = "images";
	my $setarch = $1 ? "sparc64" : "sparc32";

	_ "mkdir -p $dir/$boot";
	-f "$type.rdz" or initrd($type, $I, "$type.rdz");
	_ "cp -f vmlinux$1.aout $dir/$boot/$type.img";
	_ "$setarch kernel$1/src/arch/sparc$1/boot/piggyback $dir/$boot/$type.img kernel$1/boot/System.map $type.rdz";
    } elsif ($type =~ /^tftp(.*)/) {
	my $dir = "/export";
	my $boot = "images";

	_ "mkdir -p $dir/$boot";
	_ "cp -f vmlinux$1.aout $dir/$boot/$type.img";
    } else {
	my $dir = "floppy";
	__ "$sudo umount $tmp_mnt 2>/dev/null";
	_ "rm -rf $dir";
	_ "mkdir -p $dir";
	_ "cp -f /boot/fd.b /boot/second.b $dir";
	_ "cp -f vmlinuz$I $dir/vmlinux$I.gz";
	-f "$type.rdz" ? _ "cp -f $type.rdz $dir" : initrd($type, $I, "$dir/$type.rdz");

	output("$dir/boot.msg", "
Welcome to Moondrake GNU/Linux

Press <Enter> to install or upgrade a system 7mMoondrake GNU/Linux7m
");

	output("$dir/silo.conf", qq(
partition=1
default=linux
timeout=100
read-write
message=/boot.msg
image=/vmlinux$I.gz
  label=linux
  initrd=/$type.rdz
  append="ramdisk_size=128000 $type"
"));
	_ "genromfs -d $dir -f /dev/ram -A 2048,/.. -a 512 -V 'DrakX boot disk'";
	_ "$sudo mount -t romfs /dev/ram $tmp_mnt";
	_ "silo -r $tmp_mnt -F -i /fd.b -b /second.b -C /silo.conf";
	_ "$sudo umount $tmp_mnt";
	_ "dd if=/dev/ram of=$type.img bs=1440k count=1";
	_ "sync";
	_ "$sudo mount -t romfs /dev/ram $tmp_mnt";
	_ "df $tmp_mnt";
    }
}

sub boot_img_ppc {
	my ($_type, $I, $_img, $_kernel) = @_;
	foreach (glob("all.kernels/*")) {
		my $ext = basename($_);
		if ($ext =~ /legacy/) {
			initrd("all", $I, "images/all.rdz-$ext");
			_ "mv images/all.rdz-$ext images/all.rdz-legacy";
			_ "cp $_/vmlinuz images/vmlinux-legacy";
		}
		elsif ($ext =~ /2.6/) {
			initrd("all", $I, "images/all.rdz-$ext");
			_ "mv images/all.rdz-$ext images/all.rdz";
			_ "cp $_/vmlinuz images/vmlinux";
		}
    }
    _ "cp -f /usr/lib/yaboot/yaboot images/yaboot";
	
	output("images/ofboot.b", '<CHRP-BOOT>
<COMPATIBLE>
MacRISC
</COMPATIBLE>
<DESCRIPTION>
Moondrake GNU/Linux PPC bootloader
</DESCRIPTION>
<BOOT-SCRIPT>
" screen" output
load-base release-load-area
dev screen
" "(0000000000aa00aa0000aaaaaa0000aa00aaaa5500aaaaaa)" drop 0 8 set-colors
" "(5555555555ff55ff5555ffffff5555ff55ffffff55ffffff)" drop 8 8 set-colors
device-end
3 to foreground-color
0 to background-color
" "(0C)" fb8-write drop
" Booting Moondrake GNU/Linux PPC..." fb8-write drop 100 ms
boot cd:,\boot\yaboot
</BOOT-SCRIPT>
<OS-BADGE-ICONS>
1010
000000000000F8FEACF6000000000000
0000000000F5FFFFFEFEF50000000000
00000000002BFAFEFAFCF70000000000
0000000000F65D5857812B0000000000
0000000000F5350B2F88560000000000
0000000000F6335708F8FE0000000000
00000000005600F600F5FD8100000000
00000000F9F8000000F5FAFFF8000000
000000008100F5F50000F6FEFE000000
000000F8F700F500F50000FCFFF70000
00000088F70000F50000F5FCFF2B0000
0000002F582A00F5000008ADE02C0000
00090B0A35A62B0000002D3B350A0000
000A0A0B0B3BF60000505E0B0A0B0A00
002E350B0B2F87FAFCF45F0B2E090000
00000007335FF82BF72B575907000000
000000000000ACFFFF81000000000000
000000000081FFFFFFFF810000000000
0000000000FBFFFFFFFFAC0000000000
000000000081DFDFDFFFFB0000000000
000000000081DD5F83FFFD0000000000
000000000081DDDF5EACFF0000000000
0000000000FDF981F981FFFF00000000
00000000FFACF9F9F981FFFFAC000000
00000000FFF98181F9F981FFFF000000
000000ACACF981F981F9F9FFFFAC0000
000000FFACF9F981F9F981FFFFFB0000
00000083DFFBF981F9F95EFFFFFC0000
005F5F5FDDFFFBF9F9F983DDDD5F0000
005F5F5F5FDD81F9F9E7DF5F5F5F5F00
0083DD5F5F83FFFFFFFFDF5F835F0000
000000FBDDDFACFBACFBDFDFFB000000
000000000000FFFFFFFF000000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFFFF00000000
00000000FFFFFFFFFFFFFFFFFF000000
00000000FFFFFFFFFFFFFFFFFF000000
000000FFFFFFFFFFFFFFFFFFFFFF0000
000000FFFFFFFFFFFFFFFFFFFFFF0000
000000FFFFFFFFFFFFFFFFFFFFFF0000
00FFFFFFFFFFFFFFFFFFFFFFFFFF0000
00FFFFFFFFFFFFFFFFFFFFFFFFFFFF00
00FFFFFFFFFFFFFFFFFFFFFFFFFF0000
000000FFFFFFFFFFFFFFFFFFFF000000
</OS-BADGE-ICONS>
</CHRP-BOOT>
');

	output("images/yaboot.conf", '
init-message = "\nWelcome to Moondrake GNU/Linux PPC!\nHit <TAB> for boot options.\n\n"
timeout = 150
device=cd:
default = install-gui
message=/boot/yaboot.msg

image = /boot/vmlinux
    label = install-gui
    initrd = /boot/all.gz
    initrd-size = 34000
    append = " ramdisk_size=128000"

image = /boot/vmlinux-power4
    label = install-gui-power4
    initrd = /boot/all-power4.gz
    initrd-size = 34000
    append = " ramdisk_size=128000"

image = /boot/vmlinux
    label = install-text
    initrd = /boot/all.gz
    initrd-size = 34000
    append = " text ramdisk_size=128000"

image = /boot/vmlinux-power4
    label = install-text-power4
    initrd = /boot/all-power4.gz
    initrd-size = 34000
    append = " text ramdisk_size=128000"

image = /boot/vmlinux
    label = install-gui-old
    initrd = /boot/all.gz
    initrd-size = 34000
    append = " gui-old ramdisk_size=128000"

image = /boot/vmlinux-power4
    label = install-gui-old-power4
    initrd = /boot/all-power4.gz
    initrd-size = 34000
    append = " gui-old ramdisk_size=128000"

image = enet:0,vmlinux
    label = install-net
    initrd = enet:0,all.gz
    initrd-size = 34000
    append = " ramdisk_size=128000"

image = enet:0,vmlinux-power4
    label = install-net-power4
    initrd = enet:0,all-power4.gz
    initrd-size = 34000
    append = " ramdisk_size=128000"

image = enet:0,vmlinux
    label = install-net-text
    initrd = enet:0,all.gz
    initrd-size = 34000
    append = " text ramdisk_size=128000"

image = enet:0,vmlinux-power4
    label = install-net-text-power4
    initrd = enet:0,all-power4.gz
    initrd-size = 34000
    append = " text ramdisk_size=128000"

image = /boot/vmlinux
    label = rescue
    initrd = /boot/all.gz
    initrd-size = 34000
    append = " rescue ramdisk_size=128000"

image = /boot/vmlinux-power4
    label = rescue-power4
    initrd = /boot/all-power4.gz
    initrd-size = 34000
    append = " rescue ramdisk_size=128000"

image = enet:0,vmlinux
    label = rescue-net
    initrd = enet:0,all.gz
    initrd-size = 34000
    append = " rescue ramdisk_size=128000" 

image = enet:0,vmlinux-power4
    label = rescue-net-power4
    initrd = enet:0,all-power4.gz
    initrd-size = 34000
    append = " rescue ramdisk_size=128000" 
');

	output("images/yaboot.msg", '
Thanks for choosing Moondrake GNU/Linux PPC.  The following is a short
explanation of the various options for booting the install CD.

All options ending with "-power4" use the BOOT kernel for ppc 9xx and POWER4.
The default syntax with no suffix uses the BOOT kernel for ppc 6xx 7xx and 7xxx.
The default if you just hit enter is "install-gui".

install-gui:        	uses Xorg fbdev mode
install-text:       	text based install
install-net:            allows you to use a minimal boot CD,
                        pulling the rest of the install from
                        a network server
install-net-text:       text mode network install
rescue:                 boots the rescue image
rescue-net:             boots the rescue image from a network server

');

}

sub VERSION {
    my ($kernels) = @_;

    map { "$_\n" }
      $ENV{DISTRIB_DESCR},
      scalar gmtime(),
      '', @$kernels;
}

sub syslinux_all_files {
    my ($dir, $kernels) = @_;

    eval { rm_rf($dir) }; mkdir_p($dir);

    @$kernels or die "syslinux_all_files: no kernel\n";

    $default_vga =~ /791/ or die 'we rely on vga=791 for bootsplash';
    my $theme = $ENV{THEME} || 'Moondrake';

    each_index {
	mkdir "$dir/alt$::i/$wordsize", 0777;
	_ "install -m644 all.kernels/$_/vmlinuz -D $dir/alt$::i/$wordsize/vmlinuz";
	modules('all', "$_", "images/modules.rdz-$_");
	rename("images/modules.rdz-$_", "$dir/alt$::i/$wordsize/modules.rdz");
    } @$kernels;

    _ "install -m 644 -D /boot/memtest* $dir/memtest";

    output("$dir/help.msg", syslinux_msg('help.msg.xml'));
    output("$dir/advanced.msg", syslinux_msg('advanced.msg.xml', 
					     "\nYou can choose the following kernels :\n",
					     map_index { " o  " . syslinux_color('white') . "alt$::i" . syslinux_color('default') . " is kernel $_\n" } @$kernels));
}

sub isolinux {
    my ($dir, $kernels) = @_;

    syslinux_all_files($dir, $kernels);

    _ "cp $isolinux_bin $dir/isolinux.bin";
    _ "cp /usr/lib/syslinux/ifcpu.c32 $dir/ifcpu.c32";
    _ "cp /usr/lib/syslinux/gfxboot.c32 $dir/gfxboot.c32";
    output("$dir/isolinux.cfg", syslinux_cfg_init());
    output("$dir/$wordsize.cfg", syslinux_cfg_all('cdrom', 1));

    xbox_stage1("$dir/xbox") if arch() =~ /i.86/;
}

sub xbox_stage1() {
    my ($dir) = @_;

    my $xbox_kernel = find { /xbox/ } all('all.kernels') or return;

    eval { rm_rf($dir) }; mkdir_p($dir);

    _ "cp all.kernels/$xbox_kernel/vmlinuz $dir";
    rename("images/all.rdz-$xbox_kernel", "$dir/initrd");

    _ "cp /usr/share/cromwell/xromwell-installer.xbe $dir/default.xbe";
    output("$dir/linuxboot.cfg", <<EOF);
kernel $dir/vmlinuz
initrd $dir/initrd
append root=/dev/ram3 ramdisk_size=36000 automatic=method:cdrom
EOF
}

sub boot_iso {
    my ($iso, $kernels) = @_;

    output('grub/VERSION', VERSION($kernels));	   
   
    _ "grub2-mkrescue -o $iso grub";
}

sub boot_iso_old {
    my ($iso, $kernels) = @_;

    _ "
for f in `find isolinux -type f | grep -v -e isolinux.cfg -e $wordsize.cfg`; do
	mkdir -p .boot_iso/\$(dirname \$f)
	ln -f \$f .boot_iso/\$f
done";

    output('.boot_iso/VERSION', VERSION($kernels));	   
   
    # for the boot iso, use standard isolinux
    _ "cp /usr/lib/syslinux/isolinux.bin .boot_iso/isolinux/isolinux.bin";

    my $with_gfxboot = 0;
    _ "cp /usr/share/gfxboot/themes/Moondrake/install/* .boot_iso/isolinux" if $with_gfxboot;
# _ "cp /home/pixel/cooker/soft/theme/mandriva-gfxboot-theme/inst/* .boot_iso/isolinux" if $with_gfxboot;
    #_ "cp /home/teuf/mdv/src/mandriva-gfxboot-theme/inst/* .boot_iso/isolinux" if $with_gfxboot;
    _ "cp /usr/lib/syslinux/gfxboot.c32 .boot_iso/isolinux/gfxboot.c32" if $with_gfxboot;

    output('.boot_iso/isolinux/isolinux.cfg', syslinux_cfg_all('', $with_gfxboot));

    _ "genisoimage -r -f -J -cache-inodes -V 'Mdv Boot ISO' -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -input-charset utf-8 -o $iso .boot_iso";
    _ "isohybrid -o 1 $iso";
    rm_rf('.boot_iso');
}

sub hd_grub {
    my ($img) = @_;
    my $mapfile = '/tmp/device.map.tmp';

    my ($grub_dir) = glob("/lib/grub/*-*");
    my @grub_files = map { "$grub_dir/$_" } qw(stage1 stage2);

    # mtools wants the image to be a power of 32
    my $size = ceil((40_000 + sum(map { -s $_ } @grub_files)) / 32 / 1024) * 32;

    _ "dd if=/dev/zero of=$img bs=1k count=$size";

    _ "rm -rf $tmp_mnt"; mkdir $tmp_mnt;
    _ "cp @grub_files $tmp_mnt";

    output("$tmp_mnt/menu.lst", <<EOF);
timeout 10
default 0
fallback 1

title Moondrake GNU/Linux Install

root (hd0,0)
kernel /cooker/isolinux/alt0/$wordsize/vmlinuz $default_append $default_acpi $default_vga automatic=method:disk
initrd /cooker/isolinux/alt0/$wordsize/all.rdz

title Help

pause To display the help, press <space> until you reach "HELP END"
pause .
pause Please see http://qa.mandriva.com/hd_grub.cgi for a friendlier solution
pause .
pause To specify the location where Moondrake GNU/Linux is copied,
pause choose "Moondrake GNU/Linux Install", and press "e".
pause Then change "root (hd0,0)". FYI:
pause - (hd0,0) is the first partition on first bios hard drive (usually hda1)
pause - (hd0,4) is the first extended partition (usually hda5)
pause - (hd1,0) is the first partition on second bios hard drive
pause Replace /cooker to suits the directory containing Moondrake GNU/Linux
pause .
pause HELP END
EOF

    _ "/sbin/mkdosfs $img";
    _ "mcopy -i $img $tmp_mnt/* ::";
    _ "rm -rf $tmp_mnt";

    output($mapfile, "(fd0) $img\n");

    open(my $G, "| grub --device-map=$mapfile --batch");
    print $G <<EOF;
root (fd0)
install /stage1 d (fd0) /stage2 p /menu.lst
quit
EOF
    close $G;
    unlink $mapfile;
}
