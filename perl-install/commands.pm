package commands; # $Id$

#-########################################################################
#- This file implement many common shell commands:
#- true, false, cat, which, dirname, basename, rmdir, lsmod, grep, tr,
#- mount, umount, mkdir, mknod, ln, rm, chmod, chown, swapon,
#- swapoff, ls, cp, ps, dd, head, tail, strings, hexdump, more, insmod,
#- modprobe, route, df, kill, lspci, lssbus, dmesg, sort, du, 
#-########################################################################

use diagnostics;
use strict;
use vars qw($printable_chars *ROUTE *DF *PS);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;

#-######################################################################################
#- Functions
#-######################################################################################
sub getopts {
    my $o = shift;
    my @r = map { '' } (@_ = split //, $_[0]);
    while (1) {
	local $_ = $o->[0];
	$_ && /^-/ or return @r;
	for (my $i = 0; $i < @_; $i++) { /$_[$i]/ and $r[$i] = $_[$i] }
	shift @$o;
    }
    @r;
}

sub true() { exit 0 }
sub false() { exit 1 }
sub cat { @ARGV = @_; print while <> }
sub dirname_ { print dirname(@_), "\n" }
sub basename_ { print basename(@_), "\n" }
sub rmdir_ { foreach (@_) { rmdir $_ or die "rmdir: can not remove $_\n" } }
sub lsmod() { print "Module                  Size  Used by\n"; cat("/proc/modules") }
sub which { 
  ARG: foreach (@_) { foreach my $c (split /:/, $ENV{PATH}) { -x "$c/$_" and print("$c/$_\n"), next ARG } }
}

sub grep_ {
    my ($h, $v, $i) = getopts(\@_, qw(hvi));
    @_ == 0 || $h and die "usage: grep <regexp> [files...]\n";
    my $r = shift;
    $r = qr/$r/i if $i;
    @ARGV = @_; (/$r/ xor $v) and print while <>;
}

sub tr_ {
    my ($s, $c, $d) = getopts(\@_, qw(s c d));
    @_ >= 1 + (!$d || $s) or die "usage: tr [-c] [-s [-d]] <set1> <set2> [files...]\n    or tr [-c] -d <set1> [files...]\n";
    my $set1 = shift;
    my $set2; !$d || $s and $set2 = shift;
    @ARGV = @_;
    eval "(tr/$set1/$set2/$s$d$c, print) while <>";
}

sub umount {
    @_ == 1 or die "umount expects a single argument\n";

    require fs::mount;
    fs::mount::umount($_[0]);
}

sub mkdir_ {
    my ($_rec) = getopts(\@_, qw(p));
    mkdir_p($_) foreach @_;
}


sub mknod {
    if (@_ == 1) {
	require devices;
	eval { devices::make($_[0]) }; $@ and die "mknod: failed to create $_[0]\n";
    } elsif (@_ == 4) {
	require c;
	my $mode = ${{ "b" => c::S_IFBLK(), "c" => c::S_IFCHR() }}{$_[1]} or die "unknown node type $_[1]\n";
	syscall_('mknod', my $_a = $_[0], $mode | 0600, makedev($_[2], $_[3])) or die "mknod failed: $!\n";
    } else { die "usage: mknod <path> [b|c] <major> <minor> or mknod <path>\n" }
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
		rmdir $_ or die "can not remove directory $_: $!\n";
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

sub swapon {
    @_ == 1 or die "swapon <file>\n";
    require fs::mount;
    fs::mount::swapon($_[0]);
}
sub swapoff {
    @_ == 1 or die "swapoff <file>\n";
    require fs::mount;
    fs::mount::swapoff($_[0]);
}

sub rights {
    my $r = '-' x 9;
    my @rights = (qw(x w r x w r x w r), ['t', 0], ['s', 3], ['s', 6]);
    for (my $i = 0; $i < @rights; $i++) {
	if (vec(pack("S", $_[0]), $i, 1)) {
	    my ($val, $place) = $i >= 9 ? @{$rights[$i]} : ($rights[$i], $i);
	    my $old = \substr($r, 8 - $place, 1);
	    $$old = $$old eq '-' && $i >= 9 ? uc $val : $val;
	}
    }
    my @types = split //, "_pc_d_b_-_l_s";
    $types[($_[0] >> 12) & 0xf] . $r;
}

sub displaySize {
    my $m = $_[0] >> 12;
    $m == 4 || $m == 8 || $m == 10;
}

sub ls {
    my ($l, $h) = getopts(\@_, qw(lh));
    $h and die "usage: ls [-l] <files...>\n";

    @_ or @_ = '.';
    @_ == 1 && -d $_[0] and @_ = glob_($_[0]);
    foreach (sort @_) {
	if ($l) {
	    my @s = lstat or warn("can not stat file $_\n"), next;
	    formline(
"@<<<<<<<<< @<<<<<<< @<<<<<<< @>>>>>>>> @>>>>>>>>>>>>>>> @*\n",
		     rights($s[2]), getpwuid $s[4] || $s[4], getgrgid $s[5] || $s[5],
		     displaySize($s[2]) ? $s[7] : join(", ", unmakedev($s[6])),
		     scalar localtime $s[9], -l $_ ? "$_ -> " . readlink $_ : $_);
	    print $^A; $^A = '';
	} else { print "$_\n" }
    }
}
sub cp {
    @_ >= 2 or die "usage: cp <sources> <dest>\n(this cp does -Rfl by default)\n";
    cp_af(@_);
}

sub ps {
    @_ and die "usage: ps\n";
    my ($pid, $rss, $cpu, $cmd);
    my ($uptime) = split ' ', first(cat_("/proc/uptime"));
    my $hertz = 100;

    require c;
    my $page = c::getpagesize() / 1024;

    open PS, ">&STDOUT"; #- PS must be not be localised otherwise the "format PS" fails
    format PS_TOP =
  PID   RSS %CPU CMD
.
    format PS =
@>>>> @>>>> @>>> @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$pid, $rss, $cpu, $cmd
.
    foreach (sort { $a <=> $b } grep { /\d+/ } all('/proc')) {
	$pid = $_;
	my @l = split(' ', cat_("/proc/$pid/stat"));
	$cpu = sprintf "%2.1f", max(0, min(99, ($l[13] + $l[14]) * 100 / $hertz / ($uptime - $l[21] / $hertz)));
	$rss = (split ' ', cat_("/proc/$pid/stat"))[23] * $page;
	($cmd = cat_("/proc/$pid/cmdline")) =~ s/\0/ /g;
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
    ref($h{if}) eq 'GLOB' ? (*IF = $h{if}) : sysopen(IF, $h{if}, 0)    || die "error: can not open file $h{if}\n";
    ref($h{of}) eq 'GLOB' ? (*OF = $h{of}) : sysopen(OF, $h{of}, c::O_CREAT()|c::O_WRONLY()) || die "error: can not open file $h{of}\n";

    $h{bs} = removeXiBSuffix($h{bs});

    for ($nb = 0; !$h{count} || $nb < $h{count}; $nb++) {
	printf "\r%02.1d%%", 100 * $nb / $h{count} if $h{count} && $percent;
	$read = sysread(IF, $tmp, $h{bs}) or ($h{count} ? die "error: can not read block $nb\n" : last);
	syswrite(OF, $tmp) or die "error: can not write block $nb\n";
	$read < $h{bs} and $read = 1, last;
    }
    print STDERR "\r$nb+$read records in\n";
    print STDERR   "$nb+$read records out\n";
}

sub head_tail {
    my ($h, $n) = getopts(\@_, qw(hn));
    $h || @_ < to_bool($n) and die "usage: $0 [-h] [-n lines] [<file>]\n";
    $n = $n ? shift : 10;
    my $fh; @_ ? open($fh, $_[0]) || die "error: can not open file $_[0]\n" : ($fh = *STDIN);

    if ($0 eq 'head') {
	local $_;
	while (<$fh>) { $n-- or return; print }
    } else {
	@_ = (); 
	local $_;
	while (<$fh>) { push @_, $_; @_ > $n and shift }
	print @_;
    }
}
sub head { $0 = 'head'; &head_tail }
sub tail { $0 = 'tail'; &head_tail }

sub strings {
    my ($h, $o, $n) = getopts(\@_, qw(hon));
    $h and die "usage: strings [-o] [-n min-length] [<files>]\n";
    $n = $n ? shift : 4;
    $/ = "\0"; @ARGV = @_; my $l = 0; 
    local $_;
    while (<>) {
	while (/[$printable_chars]{$n,}/og) {
	    printf "%07d ", ($l + length $') if $o;
	    print "$&\n";
	}
	$l += length;
    } continue { $l = 0 if eof }
}

sub hexdump {
    my $i = 0; $/ = \16; @ARGV = @_; 
    local $_;
    while (<>) {
	printf "%08lX  ", $i; $i += 16;
	print join(" ", (map { sprintf "%02X", $_ } unpack("C*", $_)),
		   (s/[^$printable_chars]/./og, $_)[1]), "\n";
    }
}

sub more {
    @ARGV = @_;
    require devices;
    my $tty = devices::make('tty');
    my $n = 0; 
    open(my $IN, $tty) or die "can not open $tty\n";
    local $_;
    while (<>) {
	if (++$n == 25) {
	    my $v = <$IN>;
	    $v =~ /^q/ and exit 0;
	    $n = 0;
	}
	print;
    }
}

sub insmod {
    my ($h) = getopts(\@_, qw(h));
    $h || @_ == 0 and die "usage: insmod <module> [options]\n";
    my $f = shift;

    require run_program;
    require modules;

    if (! -r $f) {
	my $name = basename($f);
	$name =~ s/\.k?o$//;
	($f) = modules::extract_modules('/tmp', $name);
    }
    if (! -r $f) {
	die "can not find module $f\n";
    }
    run_program::run(["insmod_", "insmod"], "-f", $f, @_) or die("insmod $f failed");
    unlink $f;
}

sub modprobe {
    my ($h) = getopts(\@_, qw(h));
    $h || @_ == 0 and die "usage: modprobe <module> [options]\n";
    my $name = shift;
    require modules;
    modules::load_dependencies("/modules/modules.dep");
    modules::load_with_options([ $name ], { $name => join(' ', @_) });
}

sub route {
    @_ == 0 or die "usage: route\nsorry, no modification handled\n";
    my ($titles, @l) = cat_("/proc/net/route");
    my @titles = split ' ', $titles;
    my %l;
    open ROUTE, ">&STDOUT"; #- ROUTE must be not be localised otherwise the "format ROUTE" fails
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
	$_ = join ".", reverse map { hex $_ } unpack "a2a2a2a2", $_ foreach @l{qw(Destination Gateway Mask)};
	$l{Destination} = 'default' if $l{Destination} eq "0.0.0.0";
	$l{Gateway}     = '*'       if $l{Gateway}     eq "0.0.0.0";
	write ROUTE;
    }
}

sub df {
    my ($h) = getopts(\@_, qw(h));
    my ($dev, $size, $free, $used, $use, $mntpoint);
    open DF, ">&STDOUT"; #- DF must be not be localised otherwise the "format DF" fails
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
    foreach (sort keys %h) {
	$dev = $_;
	($size, $free) = MDK::Common::System::df($mntpoint = $h{$dev});
	$size or next;

	$use = int(100 * ($size - $free) / $size);
	$used = $size - $free;
	if ($h) {
	    $used = int($used / 1024 . "M");
	    $size = int($size / 1024 . "M");
	    $free = int($free / 1024 . "M");
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

sub lspci() { lspcidrake() }
sub lspcidrake() {
    require detect_devices;
    print join "\n", detect_devices::stringlist(), '';
}
*lssbus = \&lspci;

sub dmesg() { print cat_("/tmp/syslog") }

sub sort {
    my ($n, $h) = getopts(\@_, qw(nh));
    $h and die "usage: sort [-n] [<file>]\n";
    my $fh; @_ ? open($fh, $_[0]) || die "error: can not open file $_[0]\n" : ($fh = *STDIN);
    if ($n) {
	print(sort { $a <=> $b } <$fh>);
    } else {
	print(sort <$fh>);
    }
}

sub du {
    my ($s, $h) = getopts(\@_, qw(sh));
    $h || !$s and die "usage: du -s [<directories>]\n";

    my $f; $f = sub {
	my ($e) = @_;
	my $s = (lstat($e))[12];
	$s += sum(map { &$f($_) } glob_("$e/*")) if !-l _ && -d _;
	$s;
    };
    print &$f($_) >> 1, "\t$_\n" foreach @_ ? @_ : glob_("*");
}

sub bug {
    my ($h) = getopts(\@_, "h");
    $h and die "usage: bug\nput file report.bug on fat formatted floppy\n";

    require detect_devices;
    require modules;
    require fs;
    modules::load_dependencies("/modules/modules.dep");
    fs::mount::mount(devices::make(detect_devices::floppy()), '/fd0', 'vfat');

    require install_any;
    output("/fd0/report.bug", install_any::report_bug());
    umount "/fd0";
    common::sync();
}

sub loadkeys {
    my ($h) = getopts(\@_, "h");
    $h || @_ != 1 and die "usage: loadkeys <keyboard>\n";

    require keyboard;
    keyboard::setup_install({ KEYBOARD => $_[0] });
}

sub sync() { common::sync() }

1;
