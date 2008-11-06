package fs::remote::davfs; # $Id: smb.pm 231184 2007-10-24 14:36:29Z pixel $

use strict;
use diagnostics;

use common;
use fs::mount_options;

sub secrets_file { "$::prefix/etc/davfs2/secrets" }

sub fstab_entry_to_credentials {
    my ($part) = @_;    

    my ($options, $unknown) = fs::mount_options::unpack($part);
    $options->{'username='} && $options->{'password='} or return;
    my %h = map { $_ => delete $options->{"$_="} } qw(username password);
    $h{mntpoint} = $part->{mntpoint} or return;
    fs::mount_options::pack_($part, $options, $unknown), \%h;
}

sub save_credentials {
    my ($credentials) = @_;
    @$credentials or return;

    output_with_perm(secrets_file(), 0600, 
		     map { to_double_quoted($_->{mntpoint}, $_->{username}, $_->{password}) . "\n" } @$credentials);
}


sub read_credentials_raw {
    my ($file) = @_;
    map { 
	my %h;
	@h{'mntpoint', 'username', 'password'} = from_double_quoted($_);
	\%h;
    } cat_(secrets_file());
}

sub read_credentials {
    my ($mntpoint) = @_;
    find { $mntpoint eq $_->{mntpoint} } read_credentials_raw();
}

sub from_double_quoted {
    my ($s) = @_;
    my @l;
    while (1) {
	(my $e1, my $e2, $s) = 
	  $s =~ /^( "((?:\\.|[^"])*)" | (?:\\.|[^"\s])+ ) (.*)$/x or die "bad entry $_[0]\n";
	my $entry = defined $e2 ? $e2 : $e1;
	$entry =~ s/\\(.)/$1/g;
	push @l, $entry;
	last if $s eq '';
	$s =~ s/^\s+// or die "bad entry $_[0]\n";
	last if $s eq '';
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
