package fs::partitioning; # $Id$

use diagnostics;
use strict;

use common;
use fs::format;
use fs::type;

sub guess_partitions_to_format {
    my ($fstab) = @_;
    foreach (@$fstab) {
	$_->{mntpoint} = "swap" if isSwap($_);
	$_->{mntpoint} or next;

	add2hash_($_, { toFormat => $_->{notFormatted} }) if $_->{fs_type}; #- eg: do not set toFormat for isRawRAID (0xfd)
        $_->{toFormatUnsure} ||= member($_->{mntpoint}, '/', '/usr');

	if (!$_->{toFormat}) {
	    my $fs_type = fs::type::fs_type_from_magic($_);
	    if (!$fs_type || $fs_type ne $_->{fs_type}) {
		log::l("setting toFormatUnsure for $_->{device} because <$_->{fs_type}> ne <$fs_type>");
		$_->{toFormatUnsure} = 1;
	    }
	}
    }
}

sub choose_partitions_to_format {
    my ($in, $fstab) = @_;

    guess_partitions_to_format($fstab);

    my @l = grep { !$_->{isMounted} && $_->{mntpoint} && !isSwap($_) &&
		   (!isFat_or_NTFS($_) || $_->{notFormatted}) &&
		   (!isOtherAvailableFS($_) || $_->{toFormat});
	       } @$fstab;
    $_->{toFormat} = 1 foreach grep { isSwap($_) } @$fstab;

    return if @l == 0 || every { $_->{toFormat} } @l;

    #- keep it temporary until the guy has accepted
    $_->{toFormatTmp} = $_->{toFormat} || $_->{toFormatUnsure} foreach @l;

    $in->ask_from_(
        { messages => N("Choose the partitions you want to format"),
	  interactive_help_id => 'formatPartitions',
          advanced_messages => N("Check bad blocks?"),
        },
        [ map { 
	    my $e = $_;
	    ({
	      text => partition_table::description($e), type => 'bool',
	      val => \$e->{toFormatTmp}
	     }, if_(!isLoopback($_) && !member($_->{fs_type}, 'reiserfs', 'xfs', 'jfs'), {
	      text => partition_table::description($e), type => 'bool', advanced => 1, 
	      disabled => sub { !$e->{toFormatTmp} },
	      val => \$e->{toFormatCheck}
        })) } @l ]
    ) or die 'already displayed';
    #- ok now we can really set toFormat
    foreach (@l) {
	$_->{toFormat} = delete $_->{toFormatTmp};
	set_isFormatted($_, 0);
    }
}

sub format_mount_partitions {
    my ($in, $all_hds, $fstab) = @_;
    my ($w, $wait_message) = $in->wait_message_with_progress_bar;
    catch_cdie {
        fs::format::formatMount_all($all_hds, $fstab, $wait_message);
    } sub { 
	$@ =~ /fsck failed on (\S+)/ or return;
	$in->ask_yesorno('', N("Failed to check filesystem %s. Do you want to repair the errors? (beware, you can lose data)", $1), 1);
    };
    undef $w; #- help perl (otherwise wait_message stays forever in curses)
    die N("Not enough swap space to fulfill installation, please add some") if availableMemory() < 40 * 1024;
}

1;
