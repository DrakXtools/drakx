package fs::remote::davfs;

use strict;
use diagnostics;

use common;
use fs::mount_options;

sub secrets_file() { "$::prefix/etc/davfs2/secrets" }

sub fstab_entry_to_credentials {
    my ($part) = @_;    

    my ($options, $unknown) = fs::mount_options::unpack($part);
    my %h = map { $_ => delete $options->{"$_="} } qw(username password);
    foreach (qw(username password)) {
        $h{$_} ||= 'nobody';
    }
    $h{mntpoint} = $part->{mntpoint} or return;
    fs::mount_options::pack_($part, $options, $unknown), \%h;
}

sub save_credentials {
    my ($credentials) = @_;
    @$credentials or return;

    output_with_perm(secrets_file(), 0600, 
		     map { to_double_quoted($_->{mntpoint}, $_->{username}, $_->{password}) . "\n" } @$credentials);
}

sub mountpoint_credentials_save {
    my ($mntpoint, $mount_opt) = @_;
    my @entries = read_credentials_raw();
    my $entry = find { $mntpoint eq $_->{mntpoint} } @entries;
    die "mountpoint not found" if !$entry;
    my %h;
    foreach (@$mount_opt) {
        my @var = split(/=/);
        $h{$var[0]} = $var[1];
    }
    foreach my $key (qw(username password)) {
        $entry->{$key} = $h{$key};
    }
    save_credentials(\@entries);
}


sub read_credentials_raw() {
    from_double_quoted(cat_(secrets_file()));
}

sub read_credentials {
    my ($mntpoint) = @_;
    find { $mntpoint eq $_->{mntpoint} } read_credentials_raw();
}

# Comments are indicated by a '#' character and the rest of the line
# is ignored. Empty lines are ignored too.
#
# Each line consists of two or three items separated by spaces or tabs.
# If an item contains one of the characters space, tab, #, \ or ", this
# character must be escaped by a preceding \. Alternatively, the item
# may be enclosed in double quotes.

sub from_double_quoted {
    my ($file) = @_;
    my @l;
    my @lines = split("\n",$file);
    foreach (@lines) {
	my ($mnt, $user, $pass, $comment); 
	if (/^\s*(#.*)?$/) {
	    $comment = $1;
	} else {
            if (/^(?:"((?:\\.|[^"])*)"|((?:\\.|[^"\s#])+))\s+(?:"((?:\\.|[^"])*)"|((?:\\.|[^"\s#])+))(?:\s+(?:"((?:\\.|[^"])*)"|((?:\\.|[^"\s#])+)))?(?:\s*|\s*(#.*))?$/) {
	            $mnt = "$1$2";
		    $mnt =~ s/\\(.)/$1/g;
		    $user = "$3$4";
	            $user =~ s/\\(.)/$1/g;
		    $pass = "$5$6";
	            $pass =~ s/\\(.)/$1/g;
		    $comment=$7;
	    } else {
		    die "bad entry $_";
	    }
        }
        push @l, { 'mntpoint' => $mnt, 'username' => $user, 'password' => $pass, 'comment' => $comment };
    }
    @l;
}

sub to_double_quoted {
    my (@l) = @_;
    join(' ', map {
	s/(["\\])/\\$1/g;
	/\s/ ? qq("$_") : $_;
    } @l);
}

1;
