package authentication;

use common;

my $authentication;

sub kinds { 
    my $no_para = @_ == 0;
    my ($do_pkgs, $_meta_class) = @_;
    my $allow_SmartCard = $no_para || $do_pkgs->is_available('castella-pam');
    (
	'LDAP',
	'KRB5',
	'winbind', 
	'NIS', 
	if_($allow_SmartCard, 'SmartCard'), 
	'local',
    );
}

sub kind2name {
    my ($kind) = @_;
    # Keep the following strings in sync with kind2description ones!!!
    ${{ local => N("Local file"), 
    LDAP => N("LDAP"), 
    NIS => N("NIS"),
    SmartCard => N("Smart Card"),
    winbind => N("Windows Domain"), 
    KRB5 => N("Kerberos 5") }}{$kind};
}

my %kind2pam_kind = (
    local     => [],
    SmartCard => ['castella'],
    LDAP      => ['ldap'], 
    NIS       => [],
    KRB5        => ['krb5'],
    winbind   => ['winbind'], 
);

my %kind2nsswitch = (
    local     => [],
    SmartCard => [],
    LDAP      => ['ldap'], 
    NIS       => ['nis'],
    KRB5        => ['ldap'],
    winbind   => ['winbind'], 
);

my $lib = get_libdir();

my %kind2packages = (
    local     => [],
    SmartCard => [ 'castella-pam' ],
    LDAP      => [ 'openldap-clients', 'nss-pam-ldapd', 'autofs', 'nss_updatedb' ],
    KRB5       => [ 'nss-pam-ldapd', 'pam_krb5', "${lib}sasl2-plug-gssapi", 'nss_updatedb' ],
    NIS       => [ 'ypbind', 'autofs' ],
    winbind   => [ 'samba-winbind', 'nss-pam-ldapd', 'pam_krb5', "${lib}sasl2-plug-gssapi" ],
);


sub kind2description_raw {
    my (@kinds) = @_;
    my %kind2description = (
	local     => [ N("Local file:"), N("Use local for all authentication and information user tell in local file"), ],
	LDAP      => [ N("LDAP:"), N("Tells your computer to use LDAP for some or all authentication. LDAP consolidates certain types of information within your organization."), ],
	NIS       => [ N("NIS:"), N("Allows you to run a group of computers in the same Network Information Service domain with a common password and group file."), ],
	winbind   => [ N("Windows Domain:"), N("Winbind allows the system to retrieve information and authenticate users in a Windows domain."), ],
	KRB5        => [ N("Kerberos 5 :"), N("With Kerberos and LDAP for authentication in Active Directory Server "), ],
    );
    join('', map { $_ ? qq($_->[0]\n$_->[1]) : '' } map { $kind2description{$_} } @kinds);
}

sub kind2description {
    my (@kinds) = @_;
    join('', map { $_ ? qq($_\n\n) : '' } map { kind2description_raw($_) } @kinds);
}

sub to_kind {
    my ($authentication) = @_;
    (find { exists $authentication->{$_} } kinds()) || 'local';
}

sub domain_to_ldap_domain {
    my ($domain) = @_;
    join(',', map { "dc=$_" } split /\./, $domain);
}

sub ask_parameters {
    my ($in, $net, $authentication, $kind) = @_;

    #- keep only this authentication kind
    foreach (kinds()) {
	delete $authentication->{$_} if $_ ne $kind;
    }
    # do not enable ccreds unless required
    undef $authentication->{ccreds};

    if ($kind eq 'LDAP') {
	$authentication->{LDAPDOMAIN} ||= domain_to_ldap_domain($net->{resolv}{DOMAINNAME});
	$authentication->{ccreds} = 1;

    # this package must be installed for 'Fetch DN' button to actually work
    $in->do_pkgs->ensure_are_installed([ 'openldap-clients' ], 1) or return;
    
	$in->ask_from('', N(" "),
		     [ { label => N("Welcome to the Authentication Wizard"), title => 1 },
                     {},
                     { label => N("You have selected LDAP authentication. Please review the configuration options below "), },
                     {},
		     { label => N("LDAP Server"), val => \$authentication->{LDAP_server} },
		     { label => N("Base dn"), val => \$authentication->{LDAPDOMAIN} },
                     { val => N("Fetch base Dn "), type  => 'button' , clicked_may_quit => sub { $authentication->{LDAPDOMAIN} = fetch_dn($authentication->{LDAP_server}); 0 } },
		     {},
		     { text => N("Use encrypt connection with TLS "), val => \$authentication->{cafile}, type => 'bool' },
                     { val => N("Download CA Certificate "), type  => 'button' , disabled => sub { !$authentication->{cafile} }, clicked_may_quit => sub { $authentication->{file} = add_cafile(); 0 }  },
		     
		     { text => N("Use Disconnect mode "), val => \$authentication->{ccreds}, type => 'bool' },
		     { text => N("Use anonymous BIND "), val => \$authentication->{anonymous}, type => 'bool' , advanced => 1 },
		     { text => N("  "), advanced => 1 },
                     { label => N("Bind DN "), val => \$authentication->{LDAP_binddn}, disabled => sub { !$authentication->{anonymous} }, advanced => 1  },
                     { label => N("Bind Password "), val => \$authentication->{LDAP_bindpwd}, disabled => sub { !$authentication->{anonymous} }, advanced => 1 },
		     { text => N("  "), advanced => 1 },
		     { text => N("Advanced path for group "), val => \$authentication->{nssgrp}, type => 'bool' , advanced => 1 },
		     { text => N("  "), advanced => 1 },
                     { label => N("Password base"), val => \$authentication->{nss_pwd},  disabled => sub { !$authentication->{nssgrp} }, advanced => 1 },
                     { label => N("Group base"), val => \$authentication->{nss_grp},  disabled => sub { !$authentication->{nssgrp} }, advanced => 1 },
                     { label => N("Shadow base"), val => \$authentication->{nss_shadow},  disabled => sub { !$authentication->{nssgrp} }, advanced => 1 },
		     { text => N("  "), advanced => 1 },
		     ]) or return;
    } elsif ($kind eq 'KRB5') {
	
	$authentication->{AD_domain} ||= $net->{resolv}{DOMAINNAME};
	$in->do_pkgs->ensure_are_installed([ 'perl-Net-DNS' ], 1) or return;
	my @srvs = query_srv_names($authentication->{AD_domain}); #FIXME: update this list if the REALM has changed
	$authentication->{AD_server} ||= $srvs[0] if @srvs;
	my $AD_user = $authentication->{AD_user} =~ /(.*)\@\Q$authentication->{AD_domain}\E$/ ? $1 : $authentication->{AD_user};
	$authentication->{ccreds} = 1;

	$in->ask_from('', N(" "),
                        [ { label => N("Welcome to the Authentication Wizard"), title => 1 },
                        {},
                        { label => N("You have selected Kerberos 5 authentication. Please review the configuration options below "), },
                        {},
		       { label => N("Realm "),  val => \$authentication->{AD_domain} },
                       {},
		       { label => N("KDCs Servers"), title => 1, val => \$authentication->{AD_server} , list => \@srvs , not_edit => 0,  title => 1 },
                       {},
		       { text => N("Use DNS to locate KDC for the realm"), val => \$authentication->{KRB_host_lookup}, type => 'bool' },
		       { text => N("Use DNS to locate realms"), val => \$authentication->{KRB_dns_lookup}, type => 'bool' },
		       { text => N("Use Disconnect mode "), val => \$authentication->{ccreds}, type => 'bool' },
		     ]) or return;

my %level = (
             1 => N("Use local file for users information"),
             2 => N("Use LDAP for users information"),
            );

 $in->ask_from('', N(" "),
                        [ { label => N(" "), title => 1 },
                        {},
                        { label => N("You have selected Kerberos 5 for authentication, now you must choose the type of users information "), },
                        {},
			{ label => "" , val => \$authentication->{nsskrb}, type => 'list', list => [ keys %level ], format => sub { $level{$_[0]} } },
			{},	
			{ label => N("LDAP Server"), val => \$authentication->{LDAP_server}, disabled => sub { $authentication->{nsskrb} eq "1"  } },
                     	{ label => N("Base dn"), val => \$authentication->{LDAPDOMAIN} , disabled => sub { $authentication->{nsskrb} eq "1"  } },
                     	{ val => N("Fecth base Dn "), type  => 'button' , clicked_may_quit => sub { $authentication->{LDAPDOMAIN} = fetch_dn($authentication->{LDAP_server}); 0 }, disabled => sub { $authentication->{nsskrb} eq "1"  } },
			{},
                     	{ text => N("Use encrypt connection with TLS "), val => \$authentication->{cafile}, type => 'bool',, disabled => sub { $authentication->{nsskrb} eq "1"  } },
                     	{ val => N("Download CA Certificate "), type  => 'button' , disabled => sub { !$authentication->{cafile} }, clicked_may_quit => sub { $authentication->{file} = add_cafile(); 0 }  },
                     	{ text => N("Use anonymous BIND "), val => \$authentication->{anonymous}, type => 'bool', disabled => sub { $authentication->{nsskrb} eq "1"  } },
                     	{ label => N("Bind DN "), val => \$authentication->{LDAP_binddn}, disabled => sub { !$authentication->{anonymous} } },
                     	{ label => N("Bind Password "), val => \$authentication->{LDAP_bindpwd}, disabled => sub { !$authentication->{anonymous} } },
                     	{},
			]) or return;
	
	$authentication->{AD_user} = !$AD_user || $authentication->{sub_kind} eq 'anonymous' ? '' : 
	                             $AD_user =~ /@/ ? $AD_user : "$AD_user\@$authentication->{AD_domain}";
	$authentication->{AD_password} = '' if !$authentication->{AD_user};


    } elsif ($kind eq 'NIS') {
	$authentication->{NIS_server} ||= 'broadcast';
	$net->{network}{NISDOMAIN} ||= $net->{resolv}{DOMAINNAME};
	$in->ask_from('', N(" "),
		[ { label => N("Welcome to the Authentication Wizard"), title => 1 },
		{},
		{ label => N("You have selected NIS authentication. Please review the configuration options below "), },
		{},
		{ label => N("NIS Domain"), val => \$net->{network}{NISDOMAIN} },
		{ label => N("NIS Server"), val => \$authentication->{NIS_server}, list => ["broadcast"], not_edit => 0 },
		{},
		     ]) or return;
    } elsif ($kind eq 'winbind') {
	#- maybe we should browse the network like diskdrake --smb and get the 'doze server names in a list 
	#- but networking is not setup yet necessarily
	#
	my @sec_domain = (
		"Windows Active Directory Domain",
		"Windows NT4 Domain",
);


	$authentication->{DNS_domain} ||= $net->{resolv}{DOMAINNAME};
	$authentication->{WINDOMAIN} ||= $net->{resolv}{DOMAINNAME};
	$in->do_pkgs->ensure_are_installed([ 'samba-client' ], 1) or return;
	my @domains=list_domains();

	$in->ask_from('', N(" "),
			[ { label => N("Welcome to the Authentication Wizard"), title => 1 },
			{},
			{ label => N("You have selected Windows Domain authentication. Please review the configuration options below "), },
		        {},
			{ label => N("Windows Domain"), val => \$authentication->{WINDOMAIN}, list => \@domains, not_edit => 1 },
		        {},
		        { label => N("Domain Model "), val => \$authentication->{model}, list => \@sec_domain , not_edit => 1 },
		        {},
			{ label => N("Active Directory Realm "), val => \$authentication->{AD_domain} , disabled => sub { $authentication->{model} eq "Windows NT4 Domain"  } },
			{ label => N("DNS Domain"), val => \$authentication->{DNS_domain} , disabled => sub { $authentication->{model} eq "Windows NT4 Domain"  } },
			{ label => N("DC Server"), val => \$authentication->{AD_server} , disabled => sub { $authentication->{model} eq "Windows NT4 Domain"  } },
		        {},
			]) or return;
    }
    $authentication->{$kind} ||= 1;
    1;
}
sub ask_root_password_and_authentication {
    my ($in, $net, $superuser, $authentication, $meta_class, $security) = @_;

    my $kind = to_kind($authentication);
    my @kinds = kinds($in->do_pkgs, $meta_class);

    $in->ask_from_({
	 title => N("Authentication"), 
	 messages => N("Set administrator (root) password"),
	 advanced_label => N("Authentication method"),
	 advanced_messages => kind2description(@kinds),
	 interactive_help_id => "setRootPassword",
	 cancel => ($security <= 2 ? 
		    #-PO: keep this short or else the buttons will not fit in the window
		    N("No password") : ''),
	 focus_first => 1,
	 callbacks => { 
	     complete => sub {
		 check_given_password($in, $superuser, 2 * $security) or return 1,0;
		 return 0;
        } } }, [
{ label => N("Password"), val => \$superuser->{password},  hidden => 1 },
{ label => N("Password (again)"), val => \$superuser->{password2}, hidden => 1 },
{ label => N("Authentication"), val => \$kind, type => 'list', list => \@kinds, format => \&kind2name, advanced => 1 },
        ]) or delete $superuser->{password};

    ask_parameters($in, $net, $authentication, $kind) or goto &ask_root_password_and_authentication;
}

sub check_given_password {
    my ($in, $u, $min_length) = @_;
    if ($u->{password} ne $u->{password2}) {
	$in->ask_warn('', [ N("The passwords do not match"), N("Please try again") ]);
	0;
    } elsif (length $u->{password} < $min_length) {
	$in->ask_warn('', N("This password is too short (it must be at least %d characters long)", $min_length));
	0;
    } else {
	1;
    }
}

sub get() {
    my $system_auth = cat_("$::prefix/etc/pam.d/system-auth");
    my $authentication = {
	blowfish => to_bool($system_auth =~ /\$2a\$/),
	md5      => to_bool($system_auth =~ /md5/), 
	sha256   => to_bool($system_auth =~ /sha256/),
	sha512	 => to_bool($system_auth =~ /sha512/),
	shadow   => to_bool($system_auth =~ /shadow/),
    };

    my @pam_kinds = get_pam_authentication_kinds();
    if (my $kind = find { intersection(\@pam_kinds, $kind2pam_kind{$_}) } keys %kind2pam_kind) {
	$authentication->{$kind} = '';
    } else {
	#- we can't use pam to detect NIS
	if (my $yp_conf = read_yp_conf()) {
	    $authentication->{NIS} = 1;
	    map_each { $authentication->{"NIS_$::a"} = $::b } %$yp_conf;
	}
    }
    $authentication;
}

sub install_needed_packages {
    my ($do_pkgs, $kind, $ccreds) = @_;
    if (my $pkgs = $kind2packages{$kind}) {
	# install ccreds if required
	$ccreds and push(@$pkgs, 'pam_ccreds');
	#- automatic during install
	$do_pkgs->ensure_are_installed($pkgs, $::isInstall) or return;
    } else {
	log::l("ERROR: $kind not listed in kind2packages");
    }
    1;
}

sub set {
    my ($in, $net, $authentication, $o_when_network_is_up) = @_;

    install_needed_packages($in->do_pkgs, to_kind($authentication), $authentication->{ccreds}) or return;
    set_raw($net, $authentication, $o_when_network_is_up);

    require services;
    services::set_status('network-auth', to_kind($authentication) ne 'local', 'dont_apply');
}

sub set_raw {
    my ($net, $authentication, $o_when_network_is_up) = @_;

    my $conf_file = "$::prefix/etc/sysconfig/drakauth";
    my $when_network_is_up = $o_when_network_is_up || sub { my ($f) = @_; $f->() };

    enable_shadow() if $authentication->{shadow};    

    my $kind = to_kind($authentication);

    log::l("authentication::set $kind");

    my $pam_modules = $kind2pam_kind{$kind} or log::l("kind2pam_kind does not know $kind");
    $pam_modules ||= [];
    set_pam_authentication($pam_modules, $authentication->{ccreds});

    my $nsswitch = $kind2nsswitch{$kind} or log::l("kind2nsswitch does not know $kind");
    $nsswitch ||= [];
    set_nsswitch_priority($nsswitch, $authentication->{ccreds});

    if ($kind eq 'local') {

	output($conf_file, <<EOF);
auth=Local File 
server=none 
realm=none
EOF



    } elsif ($kind eq 'SmartCard') {
    } elsif ($kind eq 'LDAP') {

	configure_nss_ldap($authentication);

	output($conf_file, <<EOF);
auth=LDAP Directory
server=$authentication->{LDAP_server}
realm=$authentication->{LDAPDOMAIN}
EOF

    if ($authentication->{ccreds}) {
	run_program::rooted($::prefix, '/usr/sbin/nss_updatedb.cron');  # updates offline cache.
    }

    } elsif ($kind eq 'KRB5') {

	configure_krb5_for_AD($authentication);
	configure_nss_ldap($authentication);

	output($conf_file, <<EOF);
auth=Kerberos 5
server=$authentication->{AD_server}
realm=$authentication->{AD_domain}
EOF

    } elsif ($kind eq 'NIS') {
	my $domain = $net->{network}{NISDOMAIN};
	my $NIS_server = $authentication->{NIS_server};
	$domain || $NIS_server ne "broadcast" or die N("Cannot use broadcast with no NIS domain");
	my $t = $domain ? 
	  ($NIS_server eq 'broadcast' ? 
	     "domain $domain broadcast" : 
	     "domain $domain server $NIS_server") :
	     "server $NIS_server";

	substInFile {
	    if (/^#/) {
		$_ = '' if /^#\Q[PREVIOUS]/;
	    } else {
		$_ = "#[PREVIOUS] $_";
	    }
	    $_ .= "$t\n" if eof;
	} "$::prefix/etc/yp.conf";

	#- no need to modify system-auth for nis

	$when_network_is_up->(sub {
	    run_program::rooted($::prefix, 'nisdomainname', $domain);
	    run_program::rooted($::prefix, 'service', 'ypbind', 'restart');
	});

	output($conf_file, <<EOF);
auth=$kind
server=$NIS_server
realm=$domain
EOF

    } elsif ($kind eq 'winbind') {

	my $domain = uc $authentication->{WINDOMAIN};
	($authentication->{winuser}, $authentication->{winpass}) = auth();

	if ($authentication->{model} eq "Windows NT4 Domain") {

	require fs::remote::smb;
	fs::remote::smb::write_smb_conf($domain);
	run_program::rooted($::prefix, "chkconfig", "--level", "35", "winbind", "on");
	mkdir_p("$::prefix/home/$domain");
	run_program::rooted($::prefix, 'service', 'smb', 'restart');
	run_program::rooted($::prefix, 'service', 'winbind', 'restart');
	
	#- defer running smbpassword until the network is up

	$when_network_is_up->(sub {
	    run_program::raw({ root => $::prefix, sensitive_arguments => 1 },
			                 #'net', 'join', $domain, '-U', $authentication->{winuser} . '%' . $authentication->{winpass});
			     'echo', '"', 'net', 'join', $domain, '-U', $authentication->{winuser} . '%' . $authentication->{winpass}, '"');
	});

	output($conf_file, <<EOF);
auth=Windows NT4 Domain
server= none 
realm=$domain
EOF




	} else { 	
	# FIXME: the DC isn't named ads.domain... try to do reserve lookup?
	$authentication->{AD_server} ||= 'ads.' . $authentication->{AD_domain};
	my $domain = uc $authentication->{WINDOMAIN};
	my $realm = $authentication->{AD_domain};
	($authentication->{winuser}, $authentication->{winpass}) = auth();
	configure_krb5_for_AD($authentication);
		
	require fs::remote::smb;
	fs::remote::smb::write_smb_ads_conf($domain,$realm);
	run_program::rooted($::prefix, "chkconfig", "--level", "35", "winbind", "on");
	mkdir_p("$::prefix/home/$domain");
	run_program::rooted($::prefix, 'net', 'time', 'set', '-S', $authentication->{AD_server});
	run_program::rooted($::prefix, 'service', 'smb', 'restart');
	
	$when_network_is_up->(sub {
	    run_program::raw({ root => $::prefix, sensitive_arguments => 1 }, 
			     'net', 'ads', 'join', '-U', $authentication->{winuser} . '%' . $authentication->{winpass});
	    run_program::rooted($::prefix, 'service', 'winbind', 'restart');
	});

	#FIXME: perhaps save the defaults values ?
	output($conf_file, <<EOF);
auth=Windows Active Directory Domain
server= none
realm=$realm
EOF
    } }
    1;
}


sub pam_modules() {
    'pam_ldap', 'pam_castella', 'pam_winbind', 'pam_krb5', 'pam_mkhomedir', 'pam_ccreds', 'pam_deny' , 'pam_permit';
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
	my ($type, $_control, $other) = /(\S+)\s+(\[.*?\]|\S+)\s+(.*)/;
	my ($module, @para) = split(' ', $other);
	if ($module = pam_module_from_path($module)) {
	    $before_deny{$type}{$module} = \@para if member($module, pam_modules());
	}
    }
    \%before_deny;
}

sub get_pam_authentication_kinds() {
    my $before_deny = get_raw_pam_authentication();
    map { s/pam_//; $_ } keys %{$before_deny->{auth}};
}

sub sufficient {
    my ($ccreds, $module, $type) = @_;

    $ccreds && member($module, 'pam_tcb' , 'pam_winbind') ?
      'sufficient' :
    $ccreds && member($module, 'pam_ldap', 'pam_krb5') && $type eq 'account' ?
      '[authinfo_unavail=ignore default=done]' :
    $ccreds && member($module, 'pam_ldap', 'pam_krb5') && $type eq 'password' ?
      'sufficient' :
    $ccreds && member($module, 'pam_ldap', 'pam_krb5') ?
      '[authinfo_unavail=ignore user_unknown=ignore success=1 default=2]' :
      'sufficient';
}

sub pam_sufficient_line {
    my ($ccreds, $type, $module, @para) = @_;
    my $control = sufficient($ccreds, $module, $type);
    if ($module eq 'pam_winbind') {
	push @para, 'cached_login';
    }
    pam_format_line($type, $control, $module, @para);
}






sub set_pam_authentication {
    my ($authentication_kinds, $o_ccreds) = @_;
    
    my %special = (
	auth => [ difference2($authentication_kinds,, [ 'mount' ]) ],
	account => [ difference2($authentication_kinds, [ 'castella', 'mount', 'ccreds' ]) ],
	password => [ intersection($authentication_kinds, [ 'ldap', 'krb5', 'ccreds' ]) ],
    );
    my %before_first = (
	auth => member('mount', @$authentication_kinds) ? pam_format_line('auth', 'required', 'pam_mount') : '',
	session => 
	  intersection($authentication_kinds, [ 'winbind', 'krb5', 'ldap' ])
	    ? pam_format_line('session', 'optional', 'pam_mkhomedir', 'skel=/etc/skel/', 'umask=0022') :
	    member('castella', @$authentication_kinds)
	    ? pam_format_line('session', 'optional', 'pam_castella') : '',
    );
    my %after_deny = (
	session =>
          member('krb5', @$authentication_kinds)
            ? pam_format_line('session', 'optional', 'pam_krb5') :
          member('mount', @$authentication_kinds)
            ? pam_format_line('session', 'optional', 'pam_mount') : '',
    );

    substInFile {
	my ($type, $control, $other) = /(\S+)\s+(\[.*?\]|\S+)\s+(.*)/;
	my ($module, @para) = split(' ', $other);
	if ($module = pam_module_from_path($module)) {
	    if (member($module, pam_modules())) {
		#- first removing previous config
		$_ = '';
	    }
	    if ($module eq 'pam_tcb' && $special{$type}) {
		my @para_for_last = 
		    member($type, 'auth', 'account') ? qw(use_first_pass) : @{[]};
		@para = difference2(\@para, \@para_for_last);

		my ($before_noask, $ask) = partition { $_ eq 'castella' } @{$special{$type}};

		if (!@$ask) {
		    @para_for_last = grep { $_ ne 'use_first_pass' } @para_for_last;
		}

		my @l = ((map { [ "pam_$_" ] } @$before_noask),
			 [ 'pam_tcb', @para ],
			 (map { [ "pam_$_" ] } @$ask),
			 );
		push @{$l[-1]}, @para_for_last;

		$_ = join('', map { pam_sufficient_line($o_ccreds, $type, @$_) } @l);

		if ($control eq 'required') {
		    #- ensure a pam_deny line is there. it will be added below
		    ($module, @para) = ('pam_deny');
		}

		if ($type eq 'auth' && $o_ccreds) {
			$_ .= pam_format_line('auth', '[default=done]', 'pam_ccreds', 'action=validate use_first_pass');
			$_ .= pam_format_line('auth', '[default=done]', 'pam_ccreds', 'action=store');
			$_ .= pam_format_line('auth', '[default=bad]',  'pam_ccreds', 'action=update');
		}
	    }


	    if (member($module, 'pam_deny', 'pam_permit')) {
		$_ .= pam_format_line($type, $control, 
				      $type eq 'account' && $o_ccreds ? 'pam_permit' : 'pam_deny');
	    }
	    if (my $s = delete $before_first{$type}) {
		$_ = $s . $_;
	    }
	    if ($control eq 'required' && member($module, 'pam_deny', 'pam_permit', 'pam_tcb')) {
		if (my $s = delete $after_deny{$type}) {
		    $_ .= $s;
		}
	    }
	}
    } "$::prefix/etc/pam.d/system-auth";
}

sub set_nsswitch_priority {
    my ($kinds, $connected) = @_;
    my @known = qw(nis ldap winbind compat);
    substInFile {
	if (my ($database, $l) = /^(\s*(?:passwd|shadow|group|automount):\s*)(.*)/) {
	    my @l = difference2([ split(' ', $l) ], \@known);
		$_ = $database . join(' ', uniq('files', @$kinds, @l)) . "\n";
	}
	if (/^\s*(?:passwd|group):/) {
		my $option = '[NOTFOUND=return] db';
	if ($connected) {
		s/$/ $option/ if !/\Q$option/;
	} else {
		s/\s*\Q$option//;
	}
}	

    } "$::prefix/etc/nsswitch.conf";
}

sub read_yp_conf() {
    my $yp_conf = cat_("$::prefix/etc/yp.conf");
    
    if ($yp_conf =~ /^domain\s+(\S+)\s+(\S+)\s*(.*)/m) {
	{ domain => $1, server => $2 eq 'broadcast' ? 'broadcast' : $3 };
    } elsif ($yp_conf =~ /^server\s+(.*)/m) {
	{ server => $1 };
    } else {
	undef;
    }    
}

my $special_ldap_cmds = join('|', 'nss_map_attribute', 'nss_map_objectclass');
sub _after_read_ldap_line {
    my ($s) = @_;
    $s =~ s/\b($special_ldap_cmds)\s*/$1 . '_'/e;
    $s;
}
sub _pre_write_ldap_line {
    my ($s) = @_;
    $s =~ s/\b($special_ldap_cmds)_/$1 . ' '/e;
    $s;
}

sub read_ldap_conf() {
    my %conf = map { 
	s/^\s*#.*//; 
	if_(_after_read_ldap_line($_) =~ /(\S+)\s+(.*)/, $1 => $2);
    } cat_("$::prefix/etc/nslcd.conf");
    \%conf;
}

sub update_ldap_conf {    
    my (%conf) = @_;

    substInFile {
	my ($cmd) = _after_read_ldap_line($_) =~ /^\s*#?\s*(\w+)\s/;
	if ($cmd && exists $conf{$cmd}) {
	    my $val = $conf{$cmd};
	    $conf{$cmd} = '';
	    $_ = $val ? _pre_write_ldap_line("$cmd $val\n") : /^\s*#/ ? $_ : "#$_";
        }
	if (eof) {
	    foreach my $cmd (keys %conf) {
		my $val = $conf{$cmd} or next;
		$_ .= _pre_write_ldap_line("$cmd $val\n");
	    }
	}
    } "$::prefix/etc/nslcd.conf";
}

sub configure_krb5_for_AD {
    my ($authentication) = @_;

    my $uc_domain = uc $authentication->{AD_domain};
    my $krb5_conf_file = "$::prefix/etc/krb5.conf";

    krb5_conf_update($krb5_conf_file,
		     libdefaults => (
				     default_realm => $uc_domain,
				     dns_lookup_realm => $authentication->{KRB_dns_lookup} ? 'true' : 'false',
				     dns_lookup_kdc => $authentication->{KRB_host_lookup} ? 'true' : 'false',
				     default_tgs_enctypes => undef, 
				     default_tkt_enctypes => undef,
				     permitted_enctypes => undef,
				    ));

    my @sections = (
		    realms => <<EOF,
 $uc_domain = {
  kdc = $authentication->{AD_server}:88
  admin_server = $authentication->{AD_server}:749
  default_domain = $authentication->{AD_domain}
 }
EOF
		    domain_realm => <<EOF,
 .$authentication->{AD_domain} = $uc_domain
 $authentication->{AD_domain} = $uc_domain
EOF
		    kdc => <<'EOF',
 profile = /etc/kerberos/krb5kdc/kdc.conf
EOF
		    pam => <<'EOF',
 debug = false
 ticket_lifetime = 36000
 renew_lifetime = 36000
 forwardable = true
 krb4_convert = false
EOF
		    login => <<'EOF',
 krb4_convert = false
 krb4_get_tickets = false
EOF
		       );
    foreach (group_by2(@sections)) {
	my ($section, $txt) = @$_;
	krb5_conf_overwrite_category($krb5_conf_file, $section => $authentication->{AD_server} ? $txt : '');
    }
}

sub krb5_conf_overwrite_category {
    my ($file, $category, $new_val) = @_;

    my $done;
    substInFile {
	if (my $i = /^\s*\[\Q$category\E\]/i ... /^\[/) {
	    if ($new_val) {
		if ($i == 1) {
		    $_ .= $new_val;
		    $done = 1;
		} elsif ($i =~ /E/) {
		    $_ = "\n$_";
		} else {
		    $_ = '';
		}
	    } else {
		$_ = '' if $i !~ /E/;
	    }
	}
	#- if category has not been found above.
	if (eof && $new_val && !$done) {
	    $_ .= "\n[$category]\n$new_val";
	}
    } $file;
}

#- same as update_gnomekderc(), but allow spaces around "="
sub krb5_conf_update {
    my ($file, $category, %subst_) = @_;

    my %subst = map { lc($_) => [ $_, $subst_{$_} ] } keys %subst_;

    my $s;
    foreach (MDK::Common::File::cat_($file), "[NOCATEGORY]\n") {
	if (my $i = /^\s*\[\Q$category\E\]/i ... /^\[/) {
	    if ($i =~ /E/) { #- for last line of category
		chomp $s; $s .= "\n";
		$s .= " $_->[0] = $_->[1]\n" foreach grep { defined($_->[1]) } values %subst;
		%subst = ();
	    } elsif (/^\s*([^=]*?)\s*=/) {
		if (my $e = delete $subst{lc($1)}) {
		    $_ = defined($e->[1]) ? " $1 = $e->[1]\n" : '';
		}
	      }
	}
	$s .= $_ if !/^\Q[NOCATEGORY]/;
    }

    #- if category has not been found above.
    if (keys %subst) {
	chomp $s;
	$s .= "\n[$category]\n";
	$s .= " $_->[0] = $_->[1]\n" foreach grep { defined($_->[1]) } values %subst;
    }

    MDK::Common::File::output($file, $s);

}

sub query_srv_names {
    my ($domain) = @_;

    eval { require Net::DNS; 1 } or return;
    my $res = Net::DNS::Resolver->new;
    my $query = $res->query("_ldap._tcp.$domain", 'srv') or return;
    map { $_->target } $query->answer;
}

sub enable_shadow() {
    run_program::rooted($::prefix, "pwconv")  or log::l("pwconv failed");
    run_program::rooted($::prefix, "grpconv") or log::l("grpconv failed");
}

sub salt {
    my ($nb) = @_;
    require devices;
    open(my $F, "/dev/urandom") or die "missing urandom";
    my $s; read $F, $s, $nb;
    $s = pack("b8" x $nb, unpack "b6" x $nb, $s);
    $s =~ tr|\0-\x3f|0-9a-zA-Z./|;
    $s;
}

sub user_crypted_passwd {
    my ($u, $authentication) = @_;
    if ($u->{password}) {
	require utf8;
	utf8::encode($u->{password}); #- we don't want perl to do "smart" things in crypt()

	# Default to sha512
	$authentication = { sha512 => 1 } unless $authentication;

	my $salt;
	if ($authentication->{blowfish}) {
	    $salt = '$2a$08$' . salt(60);
	} elsif ($authentication->{md5}) {
	    $salt = '$1$' . salt(8);
	} elsif ($authentication->{sha256}) {
	    $salt = '$5$' . salt(44);
	} elsif ($authentication->{sha512}) {
	    $salt = '$6$' . salt(88);
	} else {
	    $salt = salt(2);
	}

	crypt($u->{password}, $salt);
    } else {
	$u->{pw} || '';
    }
}

sub set_root_passwd {
    my ($superuser, $authentication) = @_;
    $superuser->{name} = 'root';
    modify_user($superuser, $authentication);
    delete $superuser->{name};
}

sub modify_user {
    my ($u, $authentication) = @_;

    run_program::raw({ root => $::prefix, sensitive_arguments => 1 },
			    'usermod',
			    '-p', user_crypted_passwd($u, $authentication),
			    if_($uid, '-u', $uid), if_($gid, '-g', $gid),
			    if_($u->{realname}, '-c', $u->{realname}),
			    if_($u->{home}, '-d', $u->{home}),
			    if_($u->{shell}, '-s', $u->{shell}),
			    $u->{name}
		    );
}

sub add_cafile() {
	my $in = interactive->vnew;
	$in->ask_filename({ title => N("Select file") }) or return;
}

sub auth() {
	my $in = interactive->vnew;
        $in->ask_from('', N(" "), [
		{ label => N("Domain Windows for authentication : ") . $authentication->{WINDOMAIN} },
		{},
		{ label => N("Domain Admin User Name"), val => \$authentication->{winuser} },
	        { label => N("Domain Admin Password"), val => \$authentication->{winpass}, hidden => 1 },
	]);
	return $authentication->{winuser}, $authentication->{winpass};
}

require fs::remote::smb;
sub list_domains() {
    my $smb = fs::remote::smb->new;
    my %domains;
    foreach my $server ($smb->find_servers) {
        $domains{$server->{group}} = 1;
    }
    return sort keys %domains;
}
sub get_server_for_domain {
    my $smb = fs::remote::smb->new;
    foreach my $server ($smb->find_servers) {
        return $server->{name} if $server->{group} == $_[0];
    }
}

sub fetch_dn {
	my ($srv) = @_;
	my $s = run_program::rooted_get_stdout($::prefix, 'ldapsearch', '-x', '-h', $srv, '-b', '', '-s', 'base', '+');
	$authentication->{LDAPDOMAIN} = first($s =~ /namingContexts: (.+)/);
	return $authentication->{LDAPDOMAIN};
}
	
sub configure_nss_ldap {
	my ($authentication) = @_;
	update_ldap_conf(
			 uri => $authentication->{cafile} eq '1' ? "ldaps://" . $authentication->{LDAP_server} . "/" : "ldap://" . $authentication->{LDAP_server} . "/",
                         base => $authentication->{LDAPDOMAIN},
                        );

        if ($authentication->{nssgrp} eq '1') {

        update_ldap_conf(
                         'base shadow' => $authentication->{nss_shadow},
                         'base passwd' => $authentication->{nss_pwd},
                         'base group' => $authentication->{nss_grp},
			 scope => "sub",
                        );
        } else {

        update_ldap_conf(
                         'base shadow' => $authentication->{LDAPDOMAIN},
                         'base passwd' => $authentication->{LDAPDOMAIN},
                         'base group' => $authentication->{LDAPDOMAIN},
			 scope => "sub",
                        );
                }
        if ($authentication->{anonymous} eq '1') {
                 update_ldap_conf(
                         binddn => $authentication->{LDAP_binddn},
                         bindpw => $authentication->{LDAP_bindpwd},
                        );
        }

        if ($authentication->{cafile} eq '1') {
                 update_ldap_conf(
                 ssl => "on",
                 tls_reqcert => "allow",
                 tls_cacertfile => $authentication->{file},
                );
        }
 }

 sub compute_password_weakness {

   my ($password) = @_;
   my $score = 0;
   my $len = length($password);

   return 0 if $len == 0;

   $score = $len < 5 ? 3 :
   $len > 4 && $len < 8 ? 6 :
   $len > 7 && $len < 16 ? 12 : 18;

   $score += 1 if $password =~ /[a-z]/;
   $score += 5 if $password =~ /[A-Z]/;
   $score += 5 if $password =~ /\d+/;
   $score += 5 if $password =~ /(.*[0-9].*[0-9].*[0-9])/;
   $score += 5 if $password =~ /.[!@#$%^&*?_~,]/;
   $score += 5 if $password =~ /(.*[!@#$%^&*?_~,].*[!@#$%^&*?_~,])/;
   $score += 2 if $password =~ /([a-z].*[A-Z])|([A-Z].*[a-z])/;
   $score += 2 if $password =~ /([a-zA-Z])/ && $password =~ /([0-9])/;
   $score += 2 if $password =~ /([a-z].*[A-Z])|([A-Z].*[a-z])/;
   $score += 2 if $password =~ /([a-zA-Z0-9].*[!@#$%^&*?_~])|([!@#$%^&*?_~,].*[a-zA-Z0-9])/;

   my $level = $score < 11 ? 1 :
   $score > 10 && $score < 20 ? 2 :
   $score > 19 && $score < 30 ? 3 :
   $score > 29 && $score < 40 ? 4 : 5;

   return $level;
 }
1;
