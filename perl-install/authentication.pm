package authentication; # $Id$

use common;
use any;


sub kinds() { 
    ('local', 'LDAP', 'NIS', 'winbind');
}
sub kind2description {
    my ($kind) = @_;
    ${{ local => N("Local files"), LDAP => N("LDAP"), NIS => N("NIS"), winbind => N("Windows Domain") }}{$kind};
}
sub to_kind {
    my ($authentication) = @_;
    (find { exists $authentication->{$_} } kinds()) || 'local';
}

sub ask_parameters {
    my ($in, $netc, $authentication, $kind) = @_;

    #- keep only this authentication kind
    foreach (kinds()) {
	delete $authentication->{$_} if $_ ne $kind;
    }

    my $val = $authentication->{$kind} ||= '';

    if ($kind eq 'LDAP') {
	$val ||= 'ldap.' . $netc->{DOMAINNAME};
	$netc->{LDAPDOMAIN} ||= join(',', map { "dc=$_" } split /\./, $netc->{DOMAINNAME});
	$in->ask_from('',
		     N("Authentication LDAP"),
		     [ { label => N("LDAP Base dn"), val => \$netc->{LDAPDOMAIN} },
		       { label => N("LDAP Server"), val => \$val },
		     ]) or return;
    } elsif ($kind eq 'NIS') { 
	$val ||= 'broadcast';
	$in->ask_from('',
		     N("Authentication NIS"),
		     [ { label => N("NIS Domain"), val => \ ($netc->{NISDOMAIN} ||= $netc->{DOMAINNAME}) },
		       { label => N("NIS Server"), val => \$val, list => ["broadcast"], not_edit => 0 },
		     ]) or return;
    } elsif ($kind eq 'winbind') {
	#- maybe we should browse the network like diskdrake --smb and get the 'doze server names in a list 
	#- but networking isn't setup yet necessarily
	$in->ask_warn('', N("For this to work for a W2K PDC, you will probably need to have the admin run: C:\\>net localgroup \"Pre-Windows 2000 Compatible Access\" everyone /add and reboot the server.\nYou will also need the username/password of a Domain Admin to join the machine to the Windows(TM) domain.\nIf networking is not yet enabled, Drakx will attempt to join the domain after the network setup step.\nShould this setup fail for some reason and domain authentication is not working, run 'smbpasswd -j DOMAIN -U USER%%PASSWORD' using your Windows(tm) Domain, and Admin Username/Password, after system boot.\nThe command 'wbinfo -t' will test whether your authentication secrets are good."));
	$in->ask_from('',
			N("Authentication Windows Domain"),
			[ { label => N("Windows Domain"), val => \ ($netc->{WINDOMAIN} ||= $netc->{DOMAINNAME}) },
			  { label => N("Domain Admin User Name"), val => \$val },
			  { label => N("Domain Admin Password"), val => \$authentication->{winpass}, hidden => 1 },
			]) or return;
    }
    $authentication->{$kind} = $val;
    1;
}

sub set {
    my ($in, $netc, $authentication, $when_network_is_up) = @_;

    any::enableShadow() if $authentication->{shadow};    

    my $kind = authentication::to_kind($authentication);
    my $val = $authentication->{$kind};

    log::l("authentication::set $kind with $val");

    if ($kind eq 'LDAP') {
	$in->do_pkgs->install(qw(openldap-clients nss_ldap pam_ldap autofs));

	my $domain = $netc->{LDAPDOMAIN} || do {
	    my $s = run_program::rooted_get_stdout($::prefix, 'ldapsearch', '-x', '-h', $val, '-b', '', '-s', 'base', '+');
	    first($s =~ /namingContexts: (.+)/);
	} or log::l("no ldap domain found on server $val"), return;

	set_nsswitch_priority('ldap');
	set_pam_authentication('ldap');
	set_ldap_conf($domain, $val, 1);
    } elsif ($kind eq 'NIS') {
	$in->do_pkgs->install(qw(ypbind autofs));
	my $domain = $netc->{NISDOMAIN};
	$domain || $val ne "broadcast" or die N("Can't use broadcast with no NIS domain");
	my $t = $domain ? "domain $domain" . ($val ne "broadcast" && " server") : "ypserver";
	substInFile {
	    $_ = "#~$_" unless /^#/;
	    $_ .= "$t $val\n" if eof;
	} "$::prefix/etc/yp.conf";

	set_nsswitch_priority('nis');
	#- no need to modify system-auth for nis

	$when_network_is_up->(sub {
	    run_program::rooted($::prefix, 'nisdomainname', $domain);
	    run_program::rooted($::prefix, 'service', 'ypbind', 'restart');
	}) if !$::isInstall; #- TODO: also do it during install since nis can be useful to resolve domain names. Not done because 9.2-RC
    } elsif ($kind eq 'winbind') {
	my $domain = $netc->{WINDOMAIN};
	$domain =~ tr/a-z/A-Z/;

	$in->do_pkgs->install(qw(samba-winbind samba-common));
	set_pam_authentication('winbind');

	require network::smb;
	network::smb::write_smb_conf($domain);
	run_program::rooted($::prefix, "chkconfig", "--level", "35", "winbind", "on");
	mkdir_p("$::prefix/home/$domain");
	
	#- defer running smbpassword until the network is up
	$when_network_is_up->(sub {
	    run_program::rooted($::prefix, 'smbpasswd', '-j', $domain, '-U', $val . '%' . $authentication->{winpass});
	});
    }
}


sub pam_modules() {
    'pam_ldap', 'pam_winbind', 'pam_mkhomedir';
}
sub pam_module_from_path { 
    $_[0] && $_[0] =~ m|(/lib/security/)?(pam_.*)\.so| && $2;
}
sub pam_module_to_path { 
    "$_[0].so";
}
sub pam_format_line {
    my ($type, $control, $module, @para) = @_;
    sprintf("%-11s %-13s %s\n", $type, $control, join(' ', pam_module_to_path($module), @para));
}

sub get_raw_pam_authentication() {
    my %before_deny;
    foreach (cat_("$::prefix/etc/pam.d/system-auth")) {
	my ($type, $control, $module, @para) = split;
	if ($module = pam_module_from_path($module)) {
	    $before_deny{$type}{$module} = \@para if $control eq 'sufficient' && member($module, pam_modules());
	}
    }
    \%before_deny;
}

sub set_raw_pam_authentication {
    my ($before_deny, $before_first) = @_;
    substInFile {
	my ($type, $control, $module, @para) = split;
	my $added_pre_line = '';
	if ($module = pam_module_from_path($module)) {
	    if ($module eq 'pam_unix' && member($type, 'auth', 'account')) {
		#- remove likeauth, nullok and use_first_pass
		$_ = pam_format_line($type, 'sufficient', $module, grep { !member($_, qw(likeauth nullok use_first_pass)) } @para);
		if ($control eq 'required') {
		    #- ensure a pam_deny line is there
		    ($control, $module, @para) = ('required', 'pam_deny');
		    ($added_pre_line, $_) = ($_, pam_format_line($type, $control, $module));
		}
	    }
	    if (member($module, pam_modules())) {
		#- first removing previous config
		warn "dropping line $_";
		$_ = '';
	    } else {
		if ($before_first->{$type}) {
		    foreach my $module (keys %{$before_first->{$type}}) {
			$_ = pam_format_line($type, 'required', $module, @{$before_first->{$type}{$module}}) . $_;
		    }
		    delete $before_first->{$type};
		}		
		if ($control eq 'required' && $module eq 'pam_deny') {
		    if ($before_deny->{$type}) {
			foreach my $module (keys %{$before_deny->{$type}}) {
			    $_ = pam_format_line($type, 'sufficient', $module, @{$before_deny->{$type}{$module}}) . $_;
			}
		    }
		}
	    }
	    $_ = $added_pre_line . $_;
	}
    } "$::prefix/etc/pam.d/system-auth";
}

sub get_pam_authentication_kinds() {
    my $before_deny = get_raw_pam_authentication();
    map { s/pam_//; $_ } keys %{$before_deny->{auth}};
}

sub set_pam_authentication {
    my (@authentication_kinds) = @_;
    my $before_deny = {};
    my $before_first = {};
    foreach (@authentication_kinds) {
	my $module = 'pam_' . $_;
	$before_deny->{auth}{$module} = [ 'likeauth', 'nullok', 'use_first_pass' ];
	$before_deny->{account}{$module} = [ 'use_first_pass' ];
	$before_deny->{password}{$module} = [] if $_ eq 'ldap';
	$before_first->{session}{pam_mkhomedir} = [ 'skel=/etc/skel/', 'umask=0022' ] if $_ eq 'winbind';
    }
    set_raw_pam_authentication($before_deny, $before_first);
}

sub set_nsswitch_priority {
    my (@kinds) = @_;
    # allowed: files nis ldap dns
    substInFile {
	if (my ($database, $l) = /^(\s*(?:passwd|shadow|group|automount):\s*)(.*)/) {
	    $_ = $database . join(' ', uniq('files', @kinds, split(' ', $l))) . "\n";
	}	
    } "$::prefix/etc/nsswitch.conf";
}

sub read_ldap_conf() {
    my %conf = map { s/^\s*#.*//; if_(/(\S+)\s+(.*)/, $1 => $2) } cat_("$::prefix/etc/ldap.conf");
    \%conf;
}

sub set_ldap_conf {    
    my ($domain, $servers, $b_ssl) = @_;

    my %wanted_conf = (
	host => $servers,
	base => $domain,
	port => $b_ssl ? 636 : 389,
	ssl => $b_ssl ? 'on' : 'off',
	nss_base_shadow => "ou=People,$domain",
	nss_base_passwd => "ou=People,$domain",
	nss_base_group => "ou=Group,$domain",
    );

    substInFile {
	my ($cmd) = /^#?\s*(\w+)\s/;
	if ($cmd && exists $wanted_conf{$cmd}) {
	    my $val = $wanted_conf{$cmd};
	    $wanted_conf{$cmd} = '';
	    $_ = $val ? "$cmd $val\n" : '';
        }
    } "$::prefix/etc/ldap.conf";
}

1;

