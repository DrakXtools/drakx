package ctxhelp;

use diagnostics;
use strict;

use lib qw(/usr/lib/libDrakX);
use common;
use lang;

# 'id' => ['Globalhtmlfile', 'relativelink']
my %helppage = (
		'diskdrake' => [undef, 'diskdrake.html'],
		'diskdrake-fileshare' => [undef, 'diskdrake-fileshare.html'],
		'diskdrake-nfs' => [undef, 'diskdrake.html'],
		'diskdrake-removable' => [undef, 'diskdrake-removable.html'],
		'diskdrake-smb' => [undef, 'diskdrake-smb.html'],
		'drakautoinst' => [undef, 'drakautoinst.html'],
		'drakbackup' => [undef, 'drakbackup.html'],
		'drakboot' => [undef, 'drakboot.html'],
		'drakconf-intro' => [undef, 'drakconf-intro.html'],
		'drakconsole' => [undef, 'drakconsole.html'],
		'drakfloppy' => [undef, 'drakfloppy.html'],
		'drakfont' => [undef, 'drakfont.html'],
		'drakgw' => [undef, 'drakgw.html'],
		'draksec' => [undef, 'draksec.html'],
		'draktime' => [undef, 'draktime.html'],
		'drakxservices' => [undef, 'drakxservices.html'],
		'harddrake' => [undef, 'harddrake.html'],
		'internet-connection' => [undef, 'internet-connection.html'],
		'keyboarddrake' => [undef, 'keyboarddrake.html'],
		'logdrake' => [undef, 'logdrake.html'],
		'mcc-boot' => [undef, 'mcc-boot.html'],
		'mcc-hardware' => [undef, 'mcc-hardware.html'],
		'mcc-mountpoints' => [undef, 'mcc-mountpoints.html'],
		'mcc-network' => [undef, 'mcc-network.html'],
		'mcc-security' => [undef, 'mcc-security.html'],
		'mcc-system' => [undef, 'mcc-system.html'],
		'menudrake' => [undef, 'menudrake.html'],
		'mousedrake' => [undef, 'mousedrake.html'],
		'printerdrake' => [undef, 'printerdrake.html'],
		'software-management' => [undef, 'software-management.html'],
		'software-management-install' => [undef, 'software-management-install.html'],
		'software-management-remove' => [undef, 'software-management-remove.html'],
		'software-management-sources' => [undef, 'software-management-sources.html'],
		'software-management-update' => [undef, 'software-management-update.html'],
		'tinyfirewall' => [undef, 'tinyfirewall.html'],
		'userdrake' => [undef, 'userdrake.html'],
		'wiz-client' => [undef, 'wiz-client.html'],
		'wiz-dhcp' => [undef, 'wiz-dhcp.html'],
		'wiz-dns' => [undef, 'wiz-dns.html'],
		'wizdrake' => [undef, 'wizdrake.html'],
		'wiz-ftp' => [undef, 'wiz-ftp.html'],
		'wiz-mail' => [undef, 'wiz-mail.html'],
		'wiz-news' => [undef, 'wiz-news.html'],
		'wiz-proxy' => [undef, 'wiz-proxy.html'],
		'wiz-samba' => [undef, 'wiz-samba.html'],
		'wiz-server' => [undef, 'wiz-server.html'],
		'wiz-time' => [undef, 'wiz-time.html'],
		'wiz-web' => [undef, 'wiz-web.html'],
		'xfdrake' => [undef, 'xfdrake.html']
	       );

sub id2file { exists $helppage{$_[0]} && defined $helppage{$_[0]}[0] ? $helppage{$_[0]}[0] : $helppage{$_[0]}[1] }

sub id2anchorage { exists $helppage{$_[0]} && $helppage{$_[0]}[1] } 

sub path2help {
    my ($id) = @_;
    my ($l, $instpath, $ancpath, $path);
    my $locale = lang::read('', $>);
    $l = $locale->{lang}; 
    # For Debug Purpose
    printf("lang is %s\n", $l);
    $l = 'en' unless member($l, qw(en es fr));
    $path = '/usr/share/doc/mandrake/' . $l . '/Drakxtools-Guide.html/';
    $instpath = $path . id2file($id); $ancpath = $path . id2anchorage($id);
    print("\n** Install path = $instpath **\n** Anchorage Path = $ancpath **\n ");
    ($l, $instpath, $ancpath);
}

1;
