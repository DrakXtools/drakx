#-########################################################################
#- This file implement many common shell commands:
#- true, false, cat, which, dirname, basename, rmdir, lsmod, grep, tr,
#- mount, umount, mkdir, mknod, ln, rm, chmod, chown, mkswap, swapon,
#- swapoff, ls, cp, ps, dd, head, tail, strings, hexdump, more, insmod,
#- modprobe, route, df, kill, lspci, dmesg, sort, du, 
#-########################################################################
package commands;

use diagnostics;
use strict;
use vars qw($printable_chars);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :file :system :constant);

#-#####################################################################################
#- Globals
#-#####################################################################################
my $BUFFER_SIZE = 1024;

#-######################################################################################
#- Functions
#-######################################################################################
sub getopts {
    my $o = shift;
    my @r = map { '' } (@_ = split //, $_[0]);
    while (1) {
	local $_ = $o->[0];
	$_ && /^-/ or return @r;
	for (my $i = 0; $i < @_; $i++) { /$_[$i]/ and $r[$i] = $_[$i]; }
	shift @$o;
    }
    @r;
}

sub true { exit 0 }
sub false { exit 1 }
sub cat { @ARGV = @_; print while <> }
sub which { ARG: foreach (@_) { foreach my $c (split /:/, $ENV{PATH}) { -x "$c/$_" and print("$c/$_\n"), next ARG; }}}
sub dirname_ { print dirname(@_), "\n" }
sub basename_ { print basename(@_), "\n" }
sub rmdir_ { foreach (@_) { rmdir $_ or die "rmdir: can't remove $_\n" } }
sub lsmod { print "Module                  Size  Used by\n"; cat("/proc/modules"); }

sub grep_ {
    my ($h, $v, $i) = getopts(\@_, qw(hvi));
    @_ == 0 || $h and die "usage: grep <regexp> [files...]\n";
    my $r = shift;
    $r = qr/$r/i if $i;
    @ARGV = @_; (/$r/ ? $v || print : $v && print) while <>
}

sub tr_ {
    my ($s, $c, $d) = getopts(\@_, qw(s c d));
    @_ >= 1 + (!$d || $s) or die "usage: tr [-c] [-s [-d]] <set1> <set2> [files...]\n    or tr [-c] -d <set1> [files...]\n";
    my $set1 = shift;
    my $set2; !$d || $s and $set2 = shift;
    @ARGV = @_;
    eval "(tr/$set1/$set2/$s$d$c, print) while <>";
}

sub mount {
    @_ or return cat("/proc/mounts");
    my ($t, $r) = getopts(\@_, qw(tr));
    my $fs = $t && shift;

    @_ == 2 or die "usage: mount [-r] [-t <fs>] <device> <dir>\n",
    "       (use -r for readonly)\n",
    "       (if /dev/ is left off the device name, a temporary node will be created)\n";

    my ($dev, $where) = @_;
    $fs ||= $where =~ /:/ ? "nfs" :
            $dev =~ /fd/ ? "vfat" : "ext2";

    require fs;
    require modules;
    modules::load_deps("/modules/modules.dep");
    fs::mount($dev, $where, $fs, $r);
}

sub umount {
    @_ == 1 or die "umount expects a single argument\n";

    require 'fs.pm';
    fs::umount($_[0]);
}

sub mkdir_ {
    my ($rec) = getopts(\@_, qw(p));

    my $mkdir; $mkdir = sub {
	my $root = dirname $_[0];
	if (-e $root) {
	    -d $root or die "mkdir: error creating directory $_[0]: $root is a file and i won't delete it\n";
	} else {
	    $rec or die "mkdir: $root does not exist (try option -p)\n";
	    &$mkdir($root);
	}
	$rec and -d $_[0] and return;
	mkdir $_[0], 0755 or die "mkdir: error creating directory $_: $!\n";
    };
    &$mkdir($_) foreach @_;
}


sub mknod {
    if (@_ == 1) {
	require 'devices.pm';
	eval { devices::make($_[0]) }; $@ and die "mknod: failed to create $_[0]\n";
    } elsif (@_ == 4) {
	require 'c.pm';
	my $mode = $ {{"b" => c::S_IFBLK(), "c" => c::S_IFCHR()}}{$_[1]} or die "unknown node type $_[1]\n";
	syscall_('mknod', my $a = $_[0], $mode | 0600, makedev($_[2], $_[3])) or die "mknod failed: $!\n";
    } else { die "usage: mknod <path> [b|c] <major> <minor> or mknod <path>\n"; }
}

sub ln {
    my ($force, $soft) = getopts(\@_, qw(fs));
    @_ >= 1 or die "usage: ln [-s] [-f] <source> [<dest>]\n";

    my ($source, $dest) = @_;
    $dest ||= basename($source);

    $force and unlink $dest;

    ($soft ? symlink($source, $dest) : link($source, $dest)) or die "ln failed: $!\n";
}

sub rm {
    my ($rec, undef) = getopts(\@_, qw(rf));

    my $rm; $rm = sub {
	foreach (@_) {
	    if (!-l $_ && -d $_) {
		$rec or die "$_ is a directory\n";
		&$rm(glob_($_));
		rmdir $_ or die "can't remove directory $_: $!\n";
	    } else { unlink $_ or die "rm of $_ failed: $!\n" }
	}
    };
    &$rm(@_);
}

sub chmod_ {
    @_ >= 2 or die "usage: chmod <mode> <files>\n";

    my $mode = shift;
    $mode =~ /^[0-7]+$/ or die "illegal mode $mode\n";

    foreach (@_) { chmod oct($mode), $_ or die "chmod failed $_: $!\n" }
}

sub chown_ {
    my ($rec, undef) = getopts(\@_, qw(r));
    local $_ = shift or die "usage: chown [-r] name[.group] <files>\n";

    my ($name, $group) = (split('\.'), $_);

    my ($uid, $gid) = (getpwnam($name) || $name, getgrnam($group) || $group);

    my $chown; $chown = sub {
	foreach (@_) {
	    chown $uid, $gid, $_ or die "chown of file $_ failed: $!\n";
	    -d $_ && $rec and &$chown(glob_($_));
	}
    };
    &$chown(@_);
}

sub mkswap {
    @_ == 1 or die "mkswap <device>\n";
    require swap;
    swap::enable($_[0], 0);
}

sub swapon {
    @_ == 1 or die "swapon <file>\n";
    require swap;
    swap::swapon($_[0]);
}
sub swapoff {
    @_ == 1 or die "swapoff <file>\n";
    require swap;
    swap::swapoff($_[0]);
}

sub uncpio {
    @_ and die "uncpio reads from stdin\n";

#    cpioInstallArchive(gzdopen(0, "r"), NULL, 0, NULL, NULL, &fail);
}


sub rights {
    my $r = '-' x 9;
    my @rights = (qw(x w r x w r x w r), ['t', 0], ['s', 3], ['s', 6]);
    for (my $i = 0; $i < @rights; $i++) {
	if (vec(pack("S", $_[0]), $i, 1)) {
	    my ($val, $place) = $i >= 9 ? @{$rights[$i]} : ($rights[$i], $i);
	    my $old = \substr($r, 8 - $place, 1);
	    $$old = ($$old eq '-' && $i >= 9) ? uc $val : $val;
	}
    }
    my @types = split //, "_pc_d_b_-_l_s";
    $types[$_[0] >> 12 & 0xf] . $r;
}

sub displaySize {
    my $m = $_[0] >> 12;
    $m == 4 || $m == 8 || $m == 10;
}

sub ls {
    my ($l , $h) = getopts(\@_, qw(lh));
    $h and die "usage: ls [-l] <files...>\n";

    @_ or @_ = '.';
    @_ == 1 && -d $_[0] and @_ = glob_($_[0]);
    foreach (sort @_) {
	if ($l) {
	    my @s = lstat or warn("can't stat file $_\n"), next;
	    formline(
"@<<<<<<<<< @<<<<<<< @<<<<<<< @>>>>>>>> @>>>>>>>>>>>>>>> @*\n",
		     rights($s[2]), getpwuid $s[4] || $s[4], getgrgid $s[5] || $s[5],
		     displaySize($s[2]) ? $s[7] : join(", ", unmakedev($s[6])),
		     scalar localtime $s[9], -l $_ ? "$_ -> " . readlink $_ : $_);
	    print $^A; $^A = '';
	} else { print "$_\n"; }
    }
}
sub cp {
    my ($force) = getopts(\@_, qw(f));
    @_ >= 2 or die "usage: cp [-f] <sources> <dest>\n(this cp does -Rl by default)\n";

    my $cp; $cp = sub {
	my $dest = pop @_;

	@_ or return;
	@_ == 1 || -d $dest or die "cp: copying multiple files, but last argument ($dest) is not a directory\n";

	foreach my $src (@_) {
	    my $dest = $dest;
	    -d $dest and $dest .= "/" . basename($src);

	    if (-e $dest) {
		$force ? unlink $dest : die "file $dest already exist\n";
	    }

	    if (-d $src) {
		-d $dest or mkdir $dest, mode($src) or die "mkdir: can't create directory $dest: $!\n";
		&$cp(glob_($src), $dest);
	    } elsif (-l $src) {
		unless (symlink((readlink($src) || die "readlink failed: $!"), $dest)) {
		    my $msg = "symlink: can't create symlink $dest: $!\n";
		    $force ? warn $msg : die $msg;		    
		}
	    } else {
		local (*F, *G);
		open F, $src or die "can't open $src for reading: $!\n";
		open G, "> $dest" or $force or die "can't create $dest : $!\n";
		foreach (<F>) { print G $_ }
		chmod mode($src), $dest;
	    }
	}
    };
    &$cp(@_);
}

sub ps {
    @_ and die "usage: ps\n";
    my ($pid, $rss, $cpu, $cmd);
    my ($uptime) = split ' ', first(cat_("/proc/uptime"));
    my $hertz = 100;

    require c;
    my $page = c::getpagesize() / 1024;

    open PS, ">&STDOUT";
    format PS_TOP =
  PID   RSS %CPU CMD
.
    format PS =
@>>>> @>>>> @>>> @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$pid, $rss, $cpu, $cmd
.
    foreach $pid (sort {$a <=> $b} grep { /\d+/ } all('/proc')) {
	 my @l = split(' ', cat_("/proc/$pid/stat"));
	 $cpu = sprintf "%2.1f", max(0, min(99, ($l[13] + $l[14]) * 100 / $hertz / ($uptime - $l[21] / $hertz)));
	 $rss = (split ' ', cat_("/proc/$pid/stat"))[23] * $page;
	 (($cmd) = cat_("/proc/$pid/cmdline")) =~ s/\0/ /g;
	 $cmd ||= (split ' ', (cat_("/proc/$pid/stat"))[0])[1];
	 write PS;
    }
}


sub dd {
    my $u = "usage: dd [-h] [-p] [if=<file>] [of=<file>] [bs=<number>] [count=<number>]\n";
    my ($help, $percent) = getopts(\@_, qw(hp));
    die $u if $help;
    my %h = (if => *STDIN, of => *STDOUT, bs => 512, count => undef);
    foreach (@_) {
	/(.*?)=(.*)/ && exists $h{$1} or die $u;
	$h{$1} = $2;
    }
    local (*IF, *OF); my ($tmp, $nb, $read);
    ref $h{if} eq 'GLOB' ? *IF = $h{if} : sysopen(IF, $h{if}, 0   ) || die "error: can't open file $h{if}\n";
    ref $h{of} eq 'GLOB' ? *OF = $h{of} : sysopen(OF, $h{of}, 0x41) || die "error: can't open file $h{of}\n";

    $h{bs} = removeXiBSuffix($h{bs});

    for ($nb = 0; !$h{count} || $nb < $h{count}; $nb++) {
	printf "\r%02.1d%%", 100 * $nb / $h{count} if $h{count} && $percent;
	$read = sysread(IF, $tmp, $h{bs}) or $h{count} ? die "error: can't read block $nb\n" : last;
	syswrite(OF, $tmp) or die "error: can't write block $nb\n";
	$read < $h{bs} and $read = 1, last;
    }
    print STDERR "\r$nb+$read records in\n";
    print STDERR   "$nb+$read records out\n";
}

sub head_tail {
    my ($h, $n) = getopts(\@_, qw(hn));
    $h || @_ > 1 + bool($n) and die "usage: $0 [-h] [-n lines] [<file>]\n";
    $n = $n ? shift : 10;
    local *F; @_ ? open(F, $_[0]) || die "error: can't open file $_[0]\n" : (*F = *STDIN);

    if ($0 eq 'head') {
	foreach (<F>) { $n-- or return; print }
    } else {
	@_ = (); foreach (<F>) { push @_, $_; @_ > $n and shift; }
	print @_;
    }
}
sub head { $0 = 'head'; &head_tail }
sub tail { $0 = 'tail'; &head_tail }

sub strings {
    my ($h, $o, $n) = getopts(\@_, qw(hon));
    $h and die "usage: strings [-o] [-n min-length] [<files>]\n";
    $n = $n ? shift : 4;
    $/ = "\0"; @ARGV = @_; my $l = 0; while (<>) {
	while (/[$printable_chars]{$n,}/og) {
	    printf "%07d ", ($l + length $') if $o;
	    print "$&\n" ;
	}
	$l += length;
    } continue { $l = 0 if eof }
}

sub hexdump {
    my $i = 0; $/ = \16; @ARGV = @_; while (<>) {
	printf "%08lX  ", $i; $i += 16;
	print join(" ", (map { sprintf "%02X", $_ } unpack("C*", $_)),
		   ($_ =~ s/[^$printable_chars]/./og, $_)[1]), "\n";
    }
}

sub more {
    @ARGV = @_;
    require 'devices.pm';
    my $tty = devices::make('tty');
    local *IN; open IN, "<$tty" or die "can't open $tty\n";
    my $n = 0; while (<>) {
	++$n == 25 and $n = <IN>, $n = 0;
	print
    }
}

sub pack_ {
    my $t;
    foreach (@_) {
	if (-d $_) {
	    pack_(glob_($_));
	} else {
	    print -s $_, "\n";
	    print $_, "\n";

	    local *F;
	    open F, $_ or die "can't read file $_: $!\n";
	    while (read F, $t, $BUFFER_SIZE) { print $t; }
	}
    }
}

sub unpack_ {
    my $t;
    @_ == 1 or die "give me one and only one file to unpack\n";
    local *F;
    open F, $_[0] or die "can't open file $_: $!\n";
    while (1) {
	my ($size) = chop_(scalar <F>);
	defined $size or last;
	$size =~ /^\d+$/ or die "bad format (can't find file size)\n";
	my ($filename) = chop_(scalar <F>) or die "expecting filename\n";

	print "$filename\n";
	my $dir = dirname($filename);
	-d $dir or mkdir_('-p', $dir);

	local *G;
	open G, "> $filename" or die "can't write file $filename: $!\n";
	while ($size) {
	    $size -= read(F, $t, min($size, $BUFFER_SIZE)) || die "data for file $filename is missing\n";
	    print G $t or die "error writing to file $filename: $!\n";
	}
    }
}

sub insmod {
    my ($h) = getopts(\@_, qw(h));
    $h || @_ == 0 and die "usage: insmod <module> [options]\n";
    my $f = local $_ = shift;

    require 'run_program.pm';

    #- try to install the module if it exist else extract it from archive.
    #- needed for cardmgr.
    unless (-r $f) {
	$_ = $1 if m@.*/([^/]*)\.o@;
	unless (-r ($f = "/lib/modules/$_.o")) {
	    $f = "/tmp/$_.o";
	    my $cz = "/lib/modules" . (arch() eq 'sparc64' && "64") . ".cz"; -e $cz or $cz .= "2";
	    if (-e $cz) {
		run_program::run("extract_archive $cz /tmp $_.o");
	    } elsif (-e "/lib/modules.cpio.bz2") {
		run_program::run("cd /tmp ; bzip2 -cd /lib/modules.cpio.bz2 | cpio -i $_.o");
	    } else {
		die "unable to find an archive for modules";
	    }
	}
    }
    -r $f or die "can't find module $_";
    run_program::run(["insmod_", "insmod"], "-f", $f, @_) or die("insmod $_ failed");
    unlink $f;
}

sub modprobe {
    my ($h) = getopts(\@_, qw(h));
    $h || @_ == 0 and die "usage: modprobe <module> [options]\n";
    my $name = shift;
    require 'modules.pm';
    modules::load_deps("/modules/modules.dep");
    modules::load($name, '', @_);
}

sub route {
    @_ == 0 or die "usage: route\nsorry, no modification handled\n";
    my ($titles, @l) = cat_("/proc/net/route");
    my @titles = split ' ', $titles;
    my %l;
    open ROUTE, ">&STDOUT";
    format ROUTE_TOP =
Destination    Gateway        Mask           Iface
.
    format ROUTE =
@<<<<<<<<<<<<  @<<<<<<<<<<<<  @<<<<<<<<<<<<  @<<<<<<<
$l{Destination}, $l{Gateway}, $l{Mask}, $l{Iface}
.
    foreach (@l) {
	/^\s*$/ and next;
	@l{@titles} = split;
	$_ = join ".", reverse map { hex } unpack "a2a2a2a2", $_ foreach @l{qw(Destination Gateway Mask)};
	$l{Destination} = 'default' if $l{Destination} eq "0.0.0.0";
	$l{Gateway}     = '*'       if $l{Gateway}     eq "0.0.0.0";
	write ROUTE;
    }
}

sub df {
    my ($h) = getopts(\@_, qw(h));
    my ($dev, $blocksize, $size, $free, $used, $use, $mntpoint);
    open DF, ">&STDOUT";
    format DF_TOP =
Filesystem          Size      Used    Avail     Use  Mounted on
.
    format DF =
@<<<<<<<<<<<<<<<< @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>% @<<<<<<<<<<<<<<<<<<<<<<<<<
$dev, $size, $used, $free, $use, $mntpoint
.
    my %h;
    foreach (cat_("/proc/mounts"), cat_("/etc/mtab")) {
	($dev, $mntpoint) = split;
	$h{$dev} = $mntpoint;
    }
    foreach $dev (sort keys %h) {
	$mntpoint = $h{$dev};
	my $buf = ' ' x 20000;
	syscall_('statfs', $mntpoint, $buf) or next;
	(undef, $blocksize, $size, undef, $free, undef) = unpack "L2L4", $buf;
	$_ *= $blocksize / 1024 foreach $size, $free;

	$size or next;

	$use = int (100 * ($size - $free) / $size);
	$used = $size - $free;
	if ($h) {
	    $used = int ($used / 1024) . "M";
	    $size = int ($size / 1024) . "M";
	    $free = int ($free / 1024) . "M";
	}
	write DF if $size;
    }
}

sub kill {
    my $signal = 15;
    @_ or die "usage: kill [-<signal>] pids\n";
    $signal = (shift, $1)[1] if $_[0] =~ /^-(.*)/;
    kill $signal, @_ or die "kill failed: $!\n";
}

sub lspci {
    require 'pci_probing/main.pm';
    print join "\n", pci_probing::main::list (), '';
}
sub dmesg { print cat_("/tmp/syslog"); }

sub sort {
    my ($n, $h) = getopts(\@_, qw(nh));
    $h and die "usage: sort [-n] [<file>]\n";
    local *F; @_ ? open(F, $_[0]) || die "error: can't open file $_[0]\n" : (*F = *STDIN);
    if ($n) {
	print sort { $a <=> $b } <F>;
    } else {
	print sort <F>;
    }
}

sub du {
    my ($s, $h) = getopts(\@_, qw(sh));
    $h || !$s and die "usage: du -s [<directories>]\n";

    my $f; $f = sub {
	my ($e) = @_;
	my $s = (lstat($e))[12];
	$s += sum map { &$f($_) } glob_("$e/*") if !-l $e && -d $e;
	$s;
    };
    print &$f($_) >> 1, "\t$_\n" foreach @_ ? @_ : glob_("*");
}

sub  install_cpio($$;@) {
    my ($dir, $name, @more) = @_; 

    return "$dir/$name" if -e "$dir/$name";

    my $cpio = "$dir.cpio.bz2";
    -e $cpio or return;

    eval { rm("-r", $dir) };
    mkdir $dir, 0755;
    require 'run_program.pm';
    
    my $more = join " ", map { $_ && "$_ $_/*" } @more;
    run_program::run("cd $dir ; bzip2 -cd $cpio | cpio -id $name $name/* $more");

    "$dir/$name";
}


#-######################################################################################
#- Wonderful perl :(
#-######################################################################################
1; #

