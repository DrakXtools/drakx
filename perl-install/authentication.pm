package authentication; # $Id$

use common;
my $ccreds = 1;
my $conf_file = "/etc/sysconfig/drakauth";

$::real_windowwidth  = 700;
$::real_windowheight = 600;

my ($authentication) = @_;

sub kinds { 
    my $no_para = @_ == 0;
    my ($do_pkgs, $_meta_class) = @_;
    my $allow_SmartCard = $no_para || $do_pkgs->is_available('castella-pam');
    my $allow_AD = 1;
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

my %kind2packages = (
    local     => [],
    SmartCard => [ 'castella-pam' ],
    LDAP      => [ 'openldap-clients', 'nss_ldap', 'pam_ldap', 'autofs', 'pam_ccreds', 'nss_updatedb' ],
    KRB5       => [ 'nss_ldap', 'pam_krb5', 'libsasl2-plug-gssapi', 'pam_ccreds', 'nss_updatedb' ],
    NIS       => [ 'ypbind', 'autofs' ],
    winbind   => [ 'samba-winbind', 'nss_ldap', 'pam_krb5', 'libsasl2-plug-gssapi', 'samba-server' ],
);


sub kind2description {
    my (@kinds) = @_;
    my %kind2description = (
	local     => [ N("Local file:"), N("Use local for all authentication and information user tell in local file"), ],
	LDAP      => [ N("LDAP:"), N("Tells your computer to use LDAP for some or all authentication. LDAP consolidates certain types of information within your organization."), ],
	NIS       => [ N("NIS:"), N("Allows you to run a group of computers in the same Network Information Service domain with a common password and group file."), ],
	winbind   => [ N("Windows Domain:"), N("Winbind allows the system to retrieve information and authenticate users in a Windows domain."), ],
	KRB5        => [ N("Kerberos 5 :"), N("With Kerberos and Ldap for authentication in Active Directory Server "), ],
    );
    join('', map { $_ ? qq($_->[0]\n$_->[1]\n\n) : '' } map { $kind2description{$_} } @kinds);
}
sub to_kind {
    my ($authentication) = @_;
    (find { exists $authentication->{$_} } kinds()) || 'LDAP';
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

    if ($kind eq 'LDAP') {
	$authentication->{LDAPDOMAIN} ||= domain_to_ldap_domain($net->{resolv}{DOMAINNAME});
	#$authentication->{anonymous} = "0";
	#$authentication->{cafile} = "0";
	#$authentication->{nssgrp} = "0";

	$in->ask_from('', N(" "),
		     [ { label => N("Welcome to the Authentication Wizard"), title => 1 },
                     {},
                     { label => N("You have selected LDAP authentication. Please review the configuration options below "), },
                     {},
		     { label => N("LDAP Server"), val => \$authentication->{LDAP_server} },
		     { label => N("Base dn"), val => \$authentication->{LDAPDOMAIN} },
                     { val => N("Fecth base Dn "), type  => button , clicked_may_quit => sub { $authentication->{LDAPDOMAIN} = fetch_dn($authentication->{LDAP_server}); 0 } },
		     {},
		     { text => N("Use encrypt connection with TLS "), val => \$authentication->{cafile}, type => 'bool' },
                     { val => N("Download CA Certificate "), type  => button , disabled => sub { !$authentication->{cafile} }, clicked_may_quit => sub { $authentication->{file} = add_cafile(); 0 }  },
		     
		     { text => N("Use Disconnect mode "), val => \$ccreds, type => 'bool' },
		     { text => N("Use anonymous BIND "), val => \$authentication->{anonymous}, type => 'bool' , advanced => 1 },
		     { text => N("  "), advanced => 1 },
                     { label => N("Bind DN "), val => \$authentication->{LDAP_binddn}, disabled => sub { !$authentication->{anonymous} }, advanced => 1  },
                     { label => N("Bind Password "), val => \$authentication->{LDAP_bindpwd}, disabled => sub { !$authentication->{anonymous} }, advanced => 1 },
		     { text => N("  "), advanced => 1 },
		     { text => N("Advanced path for group "), val => \$authentication->{nssgrp}, type => 'bool' , advanced => 1 },
		     { text => N("  "), advanced => 1 },
                     { label => N("Password base"), val => \$authentication->{nss_pwd},  disabled => sub { !$authentication->{nssgrp} }, advanced => 1 },
                     { label => N("Group base"), val => \$authentication->{nss_grp},  disabled => sub { !$authentication->{nssgrp} }, advanced => 1 },
                     { label => N("Sahdow base"), val => \$authentication->{nss_shadow},  disabled => sub { !$authentication->{nssgrp} }, advanced => 1 },
		     { text => N("  "), advanced => 1 },
		     ]) or return;
    } elsif ($kind eq 'KRB5') {
	
	$authentication->{AD_domain} ||= $net->{resolv}{DOMAINNAME};
	$in->do_pkgs->ensure_are_installed([ 'perl-Net-DNS' ], 1) or return;
	my @srvs = query_srv_names($authentication->{AD_domain});
	$authentication->{AD_server} ||= $srvs[0] if @srvs;
	my $AD_user = $authentication->{AD_user} =~ /(.*)\@\Q$authentication->{AD_domain}\E$/ ? $1 : $authentication->{AD_user};
	#my $authentication->{ccreds} ;

	$in->ask_from('', N(" "),
                        [ { label => N("Welcome to the Authentication Wizard"), title => 1 },
                        {},
                        { label => N("You have selected Kerberos 5 authentication. Please review the configuration options below "), },
                        {},
		       { label => N("Realm "),  val => \$authentication->{AD_domain} },
                       {},
		       { label => N("KDCs Servers"),  title => 1, val => \$authentication->{AD_server} , list => \@srvs , not_edit => 0,  title => 1 },
                       {},
		       { text => N("Use DNS to resolve hosts for realms "), val => \$authentication->{KRB_host_lookup}, type => 'bool' },
		       { text => N("Use DNS to resolve KDCs for realms "), val => \$authentication->{KRB_dns_lookup}, type => 'bool' },
		       { text => N("Use Disconnect mode "), val => \$ccreds, type => 'bool' },
		     ]) or return;

my %level = (
             1 => N("Use local file for users informations"),
             2 => N("Use Ldap for users informations"),
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
                     	{ val => N("Fecth base Dn "), type  => button , clicked_may_quit => sub { $authentication->{LDAPDOMAIN} = fetch_dn($authentication->{LDAP_server}); 0 }, disabled => sub { $authentication->{nsskrb} eq "1"  } },
			{},
                     	{ text => N("Use encrypt connection with TLS "), val => \$authentication->{cafile}, type => 'bool',, disabled => sub { $authentication->{nsskrb} eq "1"  } },
                     	{ val => N("Download CA Certificate "), type  => button , disabled => sub { !$authentication->{cafile} }, clicked_may_quit => sub { $authentication->{file} = add_cafile(); 0 }  },
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
		"Windows NT4 Domain",
		"Windows Active Directory Domain",
);


	$authentication->{AD_domain} ||= $net->{resolv}{DOMAINNAME};
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
		        {},
		        {},
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
	 icon => 'banner-pw',
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
    my $system_auth = cat_("/etc/pam.d/system-auth");
    my $authentication = { 
	md5 => $system_auth =~ /md5/, shadow => $system_auth =~ /shadow/, 
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
    my ($do_pkgs, $kind) = @_;
    if (my $pkgs = $kind2packages{$kind}) {
	#- automatic during install
	$do_pkgs->ensure_are_installed($pkgs, $::isInstall) or return;
    } else {
	log::l("ERROR: $kind not listed in kind2packages");
    }
    1;
}

sub set {
    my ($in, $net, $authentication, $o_when_network_is_up) = @_;

    install_needed_packages($in->do_pkgs, to_kind($authentication)) or return;
    set_raw($net, $authentication, $o_when_network_is_up);
}

sub set_raw {
    my ($net, $authentication, $o_when_network_is_up) = @_;

    my $when_network_is_up = $o_when_network_is_up || sub { my ($f) = @_; $f->() };

    enable_shadow() if $authentication->{shadow};    

    my $kind = to_kind($authentication);

    log::l("authentication::set $kind");

    my $pam_modules = $kind2pam_kind{$kind} or log::l("kind2pam_kind does not know $kind");
    $pam_modules ||= [];
    sshd_config_UsePAM(@$pam_modules > 0);
    set_pam_authentication($pam_modules, $ccreds);

    my $nsswitch = $kind2nsswitch{$kind} or log::l("kind2nsswitch does not know $kind");
    $nsswitch ||= [];
    set_nsswitch_priority($nsswitch,$ccreds);

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
auth=Ldap Directory
server=$authentication->{LDAP_server}
realm=$authentication->{LDAPDOMAIN}
EOF

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
	$domain || $NIS_server ne "broadcast" or die N("Can not use broadcast with no NIS domain");
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

#    } elsif ($kind eq 'winbind' || $kind eq 'AD' && $authentication->{subkind} eq 'winbind') {

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
	run_program::rooted($::prefix, 'service', 'winbind', 'restart');
	
	$when_network_is_up->(sub {
	    run_program::raw({ root => $::prefix, sensitive_arguments => 1 }, 
			     'net', 'ads', 'join', '-U', $authentication->{winuser} . '%' . $authentication->{winpass});
	});


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
	#my ($type, $control, $module, @para) = split;
	my ($type, $control, $other) = /(\S+)\s+(\[.*?\]|\S+)\s+(.*)/;
	my ($module, @para) = split(' ', $other);
	if ($module = pam_module_from_path($module)) {
	    #$before_deny{$type}{$module} = \@para if $control eq 'sufficient' && member($module, pam_modules());
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

    $ccreds && member($module, 'pam_unix' , 'pam_winbind') ?
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
    #my (@authentication_kinds) = @_;
    my ($authentication_kinds, $ccreds) = @_;
    
    my %special = (
	    #auth => [ difference2(\@authentication_kinds,, [ 'mount' ]) ],
	    #account => [ difference2(\@authentication_kinds, [ 'castella', 'mount' ]) ],
	    #password => [ intersection(\@authentication_kinds, [ 'ldap', 'krb5' ]) ],
	auth => [ difference2($authentication_kinds,, [ 'mount' ]) ],
	account => [ difference2($authentication_kinds, [ 'castella', 'mount', 'ccreds' ]) ],
	password => [ intersection($authentication_kinds, [ 'ldap', 'krb5', 'ccreds' ]) ],
    );
    my %before_first = (
	    #auth => member('mount', @authentication_kinds) ? pam_format_line('auth', 'required', 'pam_mount') : '',
	auth => member('mount', @$authentication_kinds) ? pam_format_line('auth', 'required', 'pam_mount') : '',
	session => 
	  #intersection(\@authentication_kinds, [ 'winbind', 'krb5', 'ldap' ]) 
	  intersection($authentication_kinds, [ 'winbind', 'krb5', 'ldap' ])
	    ? pam_format_line('session', 'optional', 'pam_mkhomedir', 'skel=/etc/skel/', 'umask=0022') :
	    #member('castella', @authentication_kinds)
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
	    #my ($type, $control, $module, @para) = split;
	my ($type, $control, $other) = /(\S+)\s+(\[.*?\]|\S+)\s+(.*)/;
	my ($module, @para) = split(' ', $other);
	if ($module = pam_module_from_path($module)) {
	    if (member($module, pam_modules())) {
		#- first removing previous config
		$_ = '';
	    }
	    if ($module eq 'pam_unix' && $special{$type}) {
		my @para_for_last = 
		    member($type, 'auth', 'account') ? qw(use_first_pass) : @{[]};
		@para = difference2(\@para, \@para_for_last);

		my ($before_noask, $ask) = partition { $_ eq 'castella' } @{$special{$type}};

		if (!@$ask) {
		    @para_for_last = grep { $_ ne 'use_first_pass' } @para_for_last;
		}

		my @l = ((map { [ "pam_$_" ] } @$before_noask),
			 [ 'pam_unix', @para ],
			 (map { [ "pam_$_" ] } @$ask),
			 );
		push @{$l[-1]}, @para_for_last;
		#$_ = join('', map { pam_format_line($type, 'sufficient', @$_) } @l);
		### $_ = join('', map { pam_format_line($type, sufficient($ccreds, $_->[0], $type), @$_) } @l);
		$_ = join('', map { pam_sufficient_line($ccreds, $type, @$_) } @l);

		if ($control eq 'required') {
		    #- ensure a pam_deny line is there. it will be added below
		    ($module, @para) = ('pam_deny');
		}

		if ($type eq 'auth' && $ccreds) {
			$_ .= pam_format_line('auth', '[default=done]', 'pam_ccreds', 'action=validate use_first_pass');
			$_ .= pam_format_line('auth', '[default=done]', 'pam_ccreds', 'action=store');
			$_ .= pam_format_line('auth', '[default=bad]',  'pam_ccreds', 'action=update');
		}
	    }


	    if (member($module, 'pam_deny', 'pam_permit')) {
		$_ .= pam_format_line($type, $control, 
				      $type eq 'account' && $ccreds ? 'pam_permit' : 'pam_deny');
	    }
	    if (my $s = delete $before_first{$type}) {
		$_ = $s . $_;
	    }
	    if ($control eq 'required' && member($module, 'pam_deny', 'pam_permit', 'pam_unix')) {
		if (my $s = delete $after_deny{$type}) {
		    $_ .= $s;
		}
	    }
	}
    } "$::prefix/etc/pam.d/system-auth";
}

sub set_nsswitch_priority {
	#my (@kinds) = @_;
    my ($kinds, $connected) = @_;
    my @known = qw(nis ldap winbind);
    substInFile {
	if (my ($database, $l) = /^(\s*(?:passwd|shadow|group|automount):\s*)(.*)/) {
	    my @l = difference2([ split(' ', $l) ], \@known);
	    #    $_ = $database . join(' ', uniq('files', @kinds, @l)) . "\n";
	    #}
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
    } cat_("$::prefix/etc/ldap.conf");
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
    } "$::prefix/etc/ldap.conf";
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

sub sshd_config_UsePAM {
    my ($UsePAM) = @_;
    my $sshd = "$::prefix/etc/ssh/sshd_config";
    -e $sshd or return;

    my $val = "UsePAM " . bool2yesno($UsePAM);
    substInFile {
	$val = '' if s/^#?UsePAM.*/$val/;
	$_ .= "$val\n" if eof && $val;
    } $sshd;
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
    open(my $F, devices::make("random")) or die "missing random";
    my $s; read $F, $s, $nb;
    $s = pack("b8" x $nb, unpack "b6" x $nb, $s);
    $s =~ tr|\0-\x3f|0-9a-zA-Z./|;
    $s;
}

sub user_crypted_passwd {
    my ($u, $isMD5) = @_;
    if ($u->{password}) {
	crypt($u->{password}, $isMD5 ? '$1$' . salt(8) : salt(2));
    } else {
	$u->{pw} || '';
    }
}

sub set_root_passwd {
    my ($superuser, $authentication) = @_;
    $superuser->{name} = 'root';
    write_passwd_user($superuser, $authentication->{md5});    
    delete $superuser->{name};
}

sub write_passwd_user {
    my ($u, $isMD5) = @_;

    $u->{pw} = user_crypted_passwd($u, $isMD5);      
    $u->{shell} ||= '/bin/bash';

    substInFile {
	my $l = unpack_passwd($_);
	if ($l->{name} eq $u->{name}) {
	    add2hash_($u, $l);
	    $_ = pack_passwd($u);
	    $u = {};
	}
	if (eof && $u->{name}) {
	    $_ .= pack_passwd($u);
	}
    } "$::prefix/etc/passwd";
}

my @etc_pass_fields = qw(name pw uid gid realname home shell);
sub unpack_passwd {
    my ($l) = @_;
    my %l; @l{@etc_pass_fields} = split ':', chomp_($l);
    \%l;
}
sub pack_passwd {
    my ($l) = @_;
    join(':', @$l{@etc_pass_fields}) . "\n";
}

sub add_cafile() {
	my $file;
	my $in = interactive->vnew;
	$file = $in->ask_filename({ title => N("Select file") }) or return;
}

sub auth() {
	my $in = interactive->vnew;
        $file = $in->ask_from('', N(" "), [
		{ label => N("Domain Windows for authentication : " , $authentication->{WINDOMAIN}) },
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
    my %domains;
    foreach my $server ($smb->find_servers) {
        return $server->{name} if $server->{group} == @_[0];
    }
}

sub fetch_dn {
	my ($srv) = @_;
	#print "$srv";
	my $s = run_program::rooted_get_stdout($::prefix, 'ldapsearch', '-x', '-h', $srv, '-b', '', '-s', 'base', '+');
	$authentication->{LDAPDOMAIN} = first($s =~ /namingContexts: (.+)/);
	return $authentication->{LDAPDOMAIN};
}
	
sub configure_nss_ldap {
	my ($authentication) = @_;
	#my $authentication->{domain} = $authentication->{LDAPDOMAIN} || do {
        #    my $s = run_program::rooted_get_stdout($::prefix, 'ldapsearch', '-x', '-h', $authentication->{LDAP_server}, '-b', '', '-s', 'base', '+');
        #    first($s =~ /namingContexts: (.+)/);
        #} or log::l("no ldap domain found on server $authentication->{LDAP_server}"), return;
	update_ldap_conf(
                         host => $authentication->{LDAP_server},
                         base => $authentication->{LDAPDOMAIN},
                        );

        if ($authentication->{nssgrp} eq '1') {

        update_ldap_conf(
                         nss_base_shadow => $authentication->{nss_shadow} . "?sub",
                         nss_base_passwd => $authentication->{nss_pwd} . "?sub",
                         nss_base_group => $authentication->{nss_grp} . "?sub",
                        );
        } else {

        update_ldap_conf(
                         nss_base_shadow => $authentication->{LDAPDOMAIN} . "?sub",
                         nss_base_passwd => $authentication->{LDAPDOMAIN} . "?sub",
                         nss_base_group => $authentication->{LDAPDOMAIN}  . "?sub",
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
                 tls_checkpeer => "yes",
                 tls_cacertfile => $authentication->{file},
                );
        }
 }
1;
