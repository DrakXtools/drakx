package network::tools; # $Id$

use strict;
use common;
use run_program;
use c;
use vars qw(@ISA @EXPORT @EXPORT_OK);
use MDK::Common::System qw(getVarsFromSh);

@ISA = qw(Exporter);
@EXPORT = qw(connect_backend connected connected_bg disconnect_backend is_dynamic_ip passwd_by_login read_secret_backend set_cnx_script test_connected write_cnx_script write_initscript write_secret_backend);

our $connect_prog   = "/etc/sysconfig/network-scripts/net_cnx_pg";
our $connect_file    = "/etc/sysconfig/network-scripts/net_cnx_up";
our $disconnect_file = "/etc/sysconfig/network-scripts/net_cnx_down";

sub set_cnx_script {
    my ($netc, $type, $up, $down, $type2) = @_;
    $netc->{internet_cnx}{$type}{$_->[0]} = $_->[1] foreach [$connect_file, $up], [$disconnect_file, $down];
    $netc->{internet_cnx}{$type}{type} = $type2;
}
sub write_cnx_script {
    my ($netc) = @_;
    foreach ($connect_file, $disconnect_file) {
        output_with_perm("$::prefix$_", 0755,
                         '#!/bin/bash
' . if_(!$netc->{at_boot}, 'if [ "x$1" == "x--boot_time" ]; then exit; fi
') . $netc->{internet_cnx}{$netc->{internet_cnx_choice}}{$_});
    }
}

sub write_secret_backend {
    my ($a, $b) = @_;
    foreach my $i ("$::prefix/etc/ppp/pap-secrets", "$::prefix/etc/ppp/chap-secrets") {
	substInFile { s/^'$a'.*\n//; $_ .= "\n'$a' * '$b' * \n" if eof  } $i;
	#- restore access right to secrets file, just in case.
	chmod 0600, $i;
    }
}

sub unquotify {
    my ($word) = @_;
    $$word =~ s/^(['"]?)(.*)\1$/$2/;
}

sub read_secret_backend() {
    my $conf = [];
    foreach my $i ("pap-secrets", "chap-secrets") {
	foreach (cat_("$::prefix/etc/ppp/$i")) {
	    my ($login, $server, $passwd) = split(' ');
	    if ($login && $passwd) {
		unquotify \$passwd;
		unquotify \$login;
		unquotify \$server;
		push @$conf, {login => $login,
			      passwd => $passwd,
			      server => $server };
	    }
	}
    }
    $conf;
}

sub passwd_by_login {
    my ($login) = @_;
    
    unquotify \$login;
    my $secret = read_secret_backend();
    foreach (@$secret) {
	return $_->{passwd} if $_->{login} eq $login;
    }
}

sub connect_backend() { run_program::rooted($::prefix, "$connect_file &") }

sub disconnect_backend() { run_program::rooted($::prefix, "$disconnect_file &") }

sub connected() { gethostbyname("mandrakesoft.com") ? 1 : 0 }

# request a ref on a bg_connect and a ref on a scalar
sub connected_bg__raw {
    my ($kid_pipe, $status) = @_;
    local $| = 1;
    if (ref($kid_pipe) && ref($$kid_pipe)) {
	my $fd = $$kid_pipe->{fd};
	fcntl($fd, c::F_SETFL(), c::O_NONBLOCK()) or die "can't fcntl F_SETFL: $!";
	my $a  = <$fd>;
     $$status = $a if defined $a;
    } else { $$kid_pipe = check_link_beat() }
}

my $kid_pipe;
sub connected_bg {
    my ($status) = @_;
    connected_bg__raw(\$kid_pipe, $status);
}

# test if connected;
# cmd = 0 : ask current status
#     return : 0 : not connected; 1 : connected; -1 : no test ever done; -2 : test in progress
# cmd = 1 : start new connection test
#     return : -2
# cmd = 2 : cancel current test
#    return : nothing
# cmd = 3 : return current status even if a test is in progress
my $kid_pipe_connect;
my $current_connection_status;

sub test_connected {
    local $| = 1;
    my ($cmd) = @_;
    
    $current_connection_status = -1 if !defined $current_connection_status;
    
    if ($cmd == 0) {
        connected_bg__raw(\$kid_pipe_connect, \$current_connection_status);
    } elsif ($cmd == 1) {
        if ($current_connection_status != -2) {
             $current_connection_status = -2;
             $kid_pipe_connect = check_link_beat();
        }
    } elsif ($cmd == 2) {
        if (defined($kid_pipe_connect)) {
	    kill -9, $kid_pipe_connect->{pid};
	    undef $kid_pipe_connect;
        }
    }
    return $current_connection_status;
}

sub check_link_beat() {
    bg_command->new(sub {
                        require Net::Ping;
                        print Net::Ping->new("icmp")->ping("mandrakesoft.com") ? 1 : 0;
                    });
}

sub write_initscript() {
    $::testing and return;
    output_with_perm("$::prefix/etc/rc.d/init.d/internet", 0755,
		     sprintf(<<'EOF', $connect_file, $connect_file, $disconnect_file, $disconnect_file));
#!/bin/bash
#
# internet       Bring up/down internet connection
#
# chkconfig: 2345 11 89
# description: Activates/Deactivates the internet interfaces
#
# dam's (damien@mandrakesoft.com)

# Source function library.
. /etc/rc.d/init.d/functions

	case "$1" in
		start)
                if [ -e %s ]; then
			action "Checking internet connections to start at boot" "%s --boot_time"
		else
			action "No connection to start" "true"
		fi
		touch /var/lock/subsys/internet
		;;
	stop)
                if [ -e %s ]; then
			action "Stopping internet connection if needed: " "%s --boot_time"
		else
			action "No connection to stop" "true"
		fi
		rm -f /var/lock/subsys/internet
		;;
	restart)
		$0 stop
		echo "Waiting 10 sec before restarting the internet connection."
		sleep 10
		$0 start
		;;
	status)
		;;
	*)
	echo "Usage: internet {start|stop|status|restart}"
	exit 1
esac
exit 0
EOF
    $::isStandalone ? system("/sbin/chkconfig --add internet") : do {
	symlinkf("../init.d/internet", "$::prefix/etc/rc.d/rc$_") foreach
	  '0.d/K11internet', '1.d/K11internet', '2.d/K11internet', '3.d/S89internet', '5.d/S89internet', '6.d/K11internet';
    };
}

sub use_windows {
    my ($file) = @_;
    my $all_hds = fsedit::get_hds({}, undef); 
    fs::get_info_from_fstab($all_hds, '');
    my $part = find { $_->{device_windobe} eq 'C' } fsedit::get_fstab(@{$all_hds->{hds}});
    $part or my $failed = N("No partition available");
    my $source = find { -d $_ && -e "$_/$file"  } map { "$part->{mntpoint}/$_" } qw(windows/system winnt/system windows/system32/drivers winnt/system32/drivers);
    log::explanations($failed || "Seek in $source to find firmware");

    return $source, $failed;
}

sub use_floppy {
    my ($in, $file) = @_;
    my $floppy = detect_devices::floppy();
    $in->ask_okcancel(N("Insert floppy"),
		      N("Insert a FAT formatted floppy in drive %s with %s in root directory and press %s", $floppy, $file, N("Next"))) or return;
    eval { fs::mount(devices::make($floppy), '/mnt', 'vfat', 'readonly'); 1 } or my $failed = N("Floppy access error, unable to mount device %s", $floppy);
    log::explanations($failed || "Mounting floppy device $floppy in /mnt");

    return '/mnt', $failed;
}


sub is_dynamic_ip {
  my ($intf) = @_;
  any { $_->{BOOTPROTO} !~ /^(none|static|)$/ } values %$intf;
}

sub is_dynamic_host {
  my ($intf) = @_;
  any { defined $_->{DHCP_HOSTNAME} } values %$intf;
}

sub reread_net_conf {
    my ($netcnx, $netc, $intf) = @_;
    network::netconnect::read_net_conf('', $netcnx, $netc);
    modules::load_category('net');
    network::netconnect::load_conf($netcnx, $netc, $intf);
    network::network::probe_netcnx_type('', $netc, $intf, $netcnx);
}

1;
