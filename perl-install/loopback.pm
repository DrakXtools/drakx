package loopback;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file :functional);
use partition_table qw(:types);
use commands;
use fs;
use log;


sub file {
    my ($part) = @_;
    ($part->{device}{mntpoint} || die "loopback::file but loopback file has no associated mntpoint") . 
      $part->{loopback_file};
}

sub loopbacks {
    map { map { @{$_->{loopback} || []} } partition_table::get_normal_parts($_) } @_;
}

sub carryRootLoopback {
    my ($part) = @_;
    $_->{mntpoint} eq '/' and return 1 foreach @{$part->{loopback} || []};
    0;
}

sub carryRootCreateSymlink {
    my ($part, $prefix) = @_;

    carryRootLoopback($part) or return;

    my $mntpoint = "$prefix$part->{mntpoint}";
    unless (-e $mntpoint) {
	eval { commands::mkdir_("-p", dirname($mntpoint)) };
	#- do non-relative link for install, should be changed to relative link before rebooting
	symlink "/initrd/loopfs", $mntpoint;

	mkdir "/initrd/loopfs/boot", 0755;
	symlink "/initrd/loopfs/boot", "$prefix/boot";
    }
    #- indicate kernel to keep initrd
    mkdir "$prefix/initrd", 0755;
}


sub format_part {
    my ($part, $prefix) = @_;
    fs::mount_part($part->{device}, $prefix);
    my $f = create($part, $prefix);
    local $part->{device} = $f;
    fs::real_format_part($part);
}

sub create {
    my ($part, $prefix) = @_;
    my $f = "$prefix$part->{device}{mntpoint}$part->{loopback_file}";
    return $f if -e $f;

    eval { commands::mkdir_("-p", dirname($f)) };

    log::l("creating loopback file $f");
    
    local *F;
    open F, ">$f" or die "failed to create loopback file";
    for (my $nb = $part->{size}; $nb >= 0; $nb -= 8) { #- 8 * 512 = 4096 :)
	print F "\0" x 4096;
    }
    $f;
}

sub inspect {
    my ($part, $prefix) = @_;

    isMountableRW($part) or return;

    my $dir = "/tmp/loopback_tmp";

    if ($part->{isMounted}) {
	$dir = ($prefix || '') . $part->{mntpoint};
    } elsif ($part->{notFormatted} && !$part->{isFormatted}) {
	$dir = '';
    } else {
	mkdir $dir, 0700;
	fs::mount($part->{device}, $dir, type2fs($part->{type}), 'rdonly');
    }
    my $h = before_leaving {
	if (!$part->{isMounted} && $dir) {
	    fs::umount($dir);
	    unlink($dir)
	}
    };
    $h->{dir} = $dir;
    $h;
}

sub getFree {
    my ($dir, $part) = @_;
    my ($freespace);

    if ($dir) {
	my $buf = ' ' x 20000;
	syscall_('statfs', $dir, $buf) or return;
	my (undef, $blocksize, $size, undef, $free, undef) = unpack "L2L4", $buf;
	$_ *= $blocksize / 512 foreach $free;
	
	$freespace = $free;
    } else {
	$freespace = $part->{size};
    }

    $freespace - sum map { $_->{size} } @{$part->{loopback} || []};
}

#- returns the size of the loopback file if it already exists
#- returns -1 is the loopback file can't be used
sub verifFile {
    my ($dir, $file, $part) = @_;
    -e "$dir$file" and return -s "$dir$file";

    $_->{loopback_file} eq $file and return -1 foreach @{$part->{loopback} || []};

    undef;
}

sub prepare_boot {
    my ($prefix) = @_;
    my $r = readlink "$prefix/boot"; 
    unlink "$prefix/boot"; 
    mkdir "$prefix/boot", 0755;
    [$r, $prefix];
}

sub save_boot {
    my ($loop_boot, $prefix) = @{$_[0]};
    
    $loop_boot or return;

    my @files = glob_("$prefix/boot/*");
    commands::cp("-f", @files, $loop_boot) if @files;
    commands::rm("-rf", "$prefix/boot");
    symlink $loop_boot, "$prefix/boot";
}


1;

