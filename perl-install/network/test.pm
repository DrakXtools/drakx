package network::test; # $Id

use strict;
use MDK::Common;
use run_program;
use Socket;

sub new {
  my ($class, $o_hostname) = @_;
  bless {
	 hostname => $o_hostname || "mandrakesoft.com"
	}, $class;
}

#- launch synchronous test, will hang until the test finishes
sub test_synchronous {
  my ($o) = @_;
  ($o->{address}, $o->{ping}) = resolve_and_ping($o->{hostname});
  $o->{done} = 1;
}

#- launch asynchronous test, won't hang
sub start {
  my ($o) = @_;
  $o->{done} = 0;
  $o->{kid} = bg_command->new(sub {
				my ($address, $ping) = resolve_and_ping($o->{hostname});
				print "$address|$ping\n";
			      });
}

#- abort asynchronous test
sub abort {
  my ($o) = @_;
  if ($o->{kid}) {
    kill -9, $o->{kid}{pid};
    undef $o->{kid};
  }
}

#- returns a true value if the test is finished, usefull for asynchronous tests
sub is_done {
  my ($o) = @_;
  $o->update_status;
  to_bool($o->{done});
}

#- return a true value if the connection works (hostname resolution and ping)
sub is_connected {
  my ($o) = @_;
  to_bool(defined($o->{hostname}) && defined($o->{ping}));
}

#- get hostname used in test for resolution and ping
sub get_hostname {
  my ($o) = @_;
  $o->{hostname};
}

#- get resolved address (if any) of given hostname
sub get_address {
  my ($o) = @_;
  $o->{address};
}

#- get ping (if any) to given hostname
sub get_ping {
  my ($o) = @_;
  $o->{ping};
}

sub resolve_and_ping {
  my ($hostname) = @_;
  require Net::Ping;
  require Time::HiRes;
  my $p;
  if ($>) {
      $p = Net::Ping->new('tcp');
      # Try connecting to the www port instead of the echo port
      $p->{port_num} = getservbyname('http', 'tcp');
  } else {
      $p = Net::Ping->new('icmp');
  }
  $p->Net::Ping::hires; #- get ping as float
  #- default timeout is 5 seconds
  my ($ret, $ping, $address) = $p->Net::Ping::ping($hostname, 5);
  if ($ret) {
      return $address, $ping;
  } elsif (defined($ret)) {
      return $address;
  }
}

sub update_status {
  my ($o) = @_;
  if ($o->{kid}) {
    my $fd = $o->{kid}{fd};
    fcntl($fd, c::F_SETFL(), c::O_NONBLOCK()) or die "can't fcntl F_SETFL: $!";
    local $| = 1;
    if (defined(my $output = <$fd>)) {
      ($o->{address}, $o->{ping}) = $output =~ /^([\d\.]+)\|([\d\.]+)*$/;
      $o->{done} = 1;
      undef $o->{kid};
    }
  }
}

1;

=head1 network::test

=head2 Test synchronously

#- resolve and get ping to hostname from command line if given, else to Mandrakesoft
use lib qw(/usr/lib/libDrakX);
use network::test;

my $net_test = network::test->new($ARGV[0]);
$net_test->test_synchronous;

my $is_connected = $net_test->is_connected;
my $hostname = $net_test->get_hostname;
my $address = $net_test->get_address;
my $ping = $net_test->get_ping;

print "connected: $is_connected
host: $hostname
resolved host: $address
ping to host: $ping
";

=head2 Test asynchronously

#- resolve and get ping to hostname from command line if given, else to Mandrakesoft
#- prints a "." every 10 miliseconds during connection test
use lib qw(/usr/lib/libDrakX);
use network::test;

my $net_test = network::test->new($ARGV[0]);
$net_test->start;

do {
  print ".\n";
  select(undef, undef, undef, 0.01);
} while !$net_test->is_done;

my $is_connected = $net_test->is_connected;
my $hostname = $net_test->get_hostname;
my $address = $net_test->get_address;
my $ping = $net_test->get_ping;

print "connected: $is_connected
host: $hostname
resolved host: $address
ping to host: $ping
";

=cut
