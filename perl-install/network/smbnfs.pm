package network::smbnfs; # $Id$

use strict;
use diagnostics;

use fs;


sub new { 
    my ($class, $o_v) = @_;
    bless($o_v || {}, $class);
}

sub server_to_string {
    my ($_class, $server) = @_;
    $server->{name} || $server->{ip};
}
sub comment_to_string {
    my ($_class, $comment) = @_;
    $comment;
}
sub to_dev {
    my ($class, $e) = @_;
    $class->to_dev_raw($class->server_to_string($e->{server}), $e->{name} || $e->{ip});
}
sub to_string {
    my ($class, $e) = @_;
    my $comment = $class->comment_to_string($e->{comment});
    ($e->{name} || $e->{ip}) . ($comment ? " ($comment)" : '');
}

sub to_fullstring {
    my ($class, $e) = @_;
    my $comment = $class->comment_to_string($e->{comment});
    $class->to_dev($e) . ($comment ? " ($comment)" : '');
}
sub to_fstab_entry_raw {
    my ($class, $e, $type) = @_;
    my $fs_entry = { device => $class->to_dev($e), type => $type };
    fs::set_default_options($fs_entry);
    $fs_entry;
}

1;

