package loopback;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file);
use partition_table qw(:types);
use commands;
use fs;
use log;


sub file {
    my ($part) = @_;
    ($part->{device}{mntpoint} || die "loopback::file but loopback file has no associated mntpoint") . 
      $part->{loopback_file};
}

sub ffile { "$_[0]{device}{mntpoint}$_[0]{loopback_file}" }

sub loopbacks {
    map { map { @{$_->{loopback} || []} } partition_table::get_normal_parts($_) } @_;
}

sub format_part {
    my ($part) = @_;
    my $prefix = $::isStandalone ? '' : $::o->{prefix};
    fs::mount_part($part->{device}, $prefix);
    my $f = create($part);
    local $part->{device} = $f;
    fs::real_format_part($part);
}

sub create {
    my ($part) = @_;
    my $f = "$part->{device}{mntpoint}$part->{loopback_file}";
    return $f if -e $f;

    eval { commands::mkdir_("-p", dirname($f)) };
    
    local *F;
    open F, ">$f" or die "failed to create loopback file";
    for (my $nb = $part->{size}; $nb >= 0; $nb -= 8) { #- 8 * 512 = 4096 :)
	print F "\0" x 4096;
    }
    $f;
}

sub getFree {
    my ($part, $prefix) = @_;

    unless ($part->{freespace}) {
	$part->{isFormatted} || !$part->{notFormatted} or return;
	isMountableRW($part) or return;

	my $dir = "/tmp/loopback_tmp";
	if ($part->{isMounted}) {
	    $dir = ($prefix || '') . $part->{mntpoint};
	} else {
	    mkdir $dir, 0700;
	    fs::mount($part->{device}, $dir, type2fs($part->{type}), 'rdonly');
	}
	my $buf = ' ' x 20000;
	syscall_('statfs', $dir, $buf) or return;
	my (undef, $blocksize, $size, undef, $free, undef) = unpack "L2L4", $buf;
	$_ *= $blocksize / 512 foreach $size, $free;

	
	unless ($part->{isMounted}) {
	    fs::umount($dir);
	    unlink $dir;
	}

	$part->{freespace} = $free;
    }
    $part->{freespace} - sum map { $_->{size} } @{$part->{loopback} || []};
}

1;

