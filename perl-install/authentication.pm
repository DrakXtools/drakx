package authentication; # $Id$

use common;
use any;

sub kinds { 
    my ($meta_class) = @_;
    my $allow_AD = $meta_class =~ /corporate/;
    ('local', 'LDAP', 'NIS', 'winbind', if_($allow_AD, 'AD', 'SMBKRB'));
}

sub kind2name {
    my ($kind) = @_;
    # Keep the following strings in sync with kind2description ones!!!
    ${{ local => N("Local file"), 
    LDAP => N("LDAP"), 
    NIS => N("NIS"), 
    winbind => N("Windows Domain"), 
    AD => N("Active Directory with SFU"),
    SMBKRB => N("Active Directory with Winbind") }}{$kind};
}

sub kind2description() {
    join('', 
         map {
             qq($_->[0]\n$_->[1]\n\n)
         }
         (
          [ N("Local file:"), N("Use local for all authentication and information user tell in local file"), ],
          [ N("LDAP:"), N("Tells your computer to use LDAP for some or all authentication. LDAP consolidates certain types of information within your organization."), ],
          [ N("NIS:"), N("Allows you to run a group of computers in the same Network Information Service domain with a common password and group file."), ],
          [ N("Windows Domain:"), N("Winbind allows the system to retrieve information and authenticate users in a Windows domain."), ],
          [ N("Active Directory with SFU:"), N("Kerberos is a secure system for providing network authentication services."), ],
          [ N("Active Directory with Winbind:"), N("Kerberos is a secure system for providing network authentication services.")  ],
         )
        );
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
    my ($in, $netc, $authentication, $kind) = @_;

    #- keep only this authentication kind
    foreach (kinds()) {
	delete $authentication->{$_} if $_ ne $kind;
    }

    if ($kind eq 'LDAP') {
	$netc->{LDAPDOMAIN} ||= domain_to_ldap_domain($netc->{DOMAINNAME});
	$in->ask_from('',
		     N("Authentication LDAP"),
		     [ { label => N("LDAP Base dn"), val => \$netc->{LDAPDOMAIN} },
		       { label => N("LDAP Server"), val => \$authentication->{LDAP_server} },
		     ]) or return;
    } elsif ($kind eq 'AD') {
	
	$authentication->{AD_domain} ||= $netc->{DOMAINNAME};
	$authentication->{AD_users_db} ||= 'cn=users,' . domain_to_ldap_domain($authentication->{AD_domain});

	$in->do_pkgs->install(qw(perl-Net-DNS));

	my @srvs = query_srv_names($authentication->{AD_domain});
	$authentication->{AD_server} ||= $srvs[0] if @srvs;

	my %sub_kinds = my @sub_kinds = (
	    simple => N("simple"), 
	    tls => N("TLS"),
	    ssl => N("SSL"),
	    kerberos => N("security layout (SASL/Kerberos)"),
	);

	my $AD_user = $authentication->{AD_user} =~ /(.*)\@\Q$authentication->{AD_domain}\E$/ ? $1 : $authentication->{AD_user};
	my $anonymous = $AD_user;

	$in->ask_from('',
		     N("Authentication Active Directory"),
		     [ { label => N("Domain"), val => \$authentication->{AD_domain} },
		     #{ label => N("Server"), val => \$authentication->{AD_server} },
		       { label => N("Server"), type => 'combo', val => \$authentication->{AD_server}, list => \@srvs , not_edit => 0 },
		       { label => N("LDAP users database"), val => \$authentication->{AD_users_db} },
		       { label => N("Use Anonymous BIND "), val => \$anonymous, type => 'bool' },
		       { label => N("LDAP user allowed to browse the Active Directory"), val => \$AD_user, disabled => sub { $anonymous } },
		       { label => N("Password for user"), val => \$authentication->{AD_password}, disabled => sub { $anonymous } },
		       { label => N("Encryption"), val => \$authentication->{sub_kind}, list => [ map { $_->[0] } group_by2(@sub_kinds) ], format => sub { $sub_kinds{$_[0]} } },
		     ]) or return;
	$authentication->{AD_user} = !$AD_user || $authentication->{sub_kind} eq 'anonymous' ? '' : 
	                             $AD_user =~ /@/ ? $AD_user : "$AD_user\@$authentication->{AD_domain}";
	$authentication->{AD_password} = '' if !$authentication->{AD_user};


    } elsif ($kind eq 'NIS') { 
	$authentication->{NIS_server} ||= 'broadcast';
	$netc->{NISDOMAIN} ||= $netc->{DOMAINNAME};
	$in->ask_from('',
		     N("Authentication NIS"),
		     [ { label => N("NIS Domain"), val => \$netc->{NISDOMAIN} },
		       { label => N("NIS Server"), val => \$authentication->{NIS_server}, list => ["broadcast"], not_edit => 0 },
		     ]) or return;
    } elsif ($kind eq 'winbind' || $kind eq 'SMBKRB') {
	#- maybe we should browse the network like diskdrake --smb and get the 'doze server names in a list 
	#- but networking isn't setup yet necessarily
	$in->ask_warn('', N("For this to work for a W2K PDC, you will probably need to have the admin run: C:\\>net localgroup \"Pre-Windows 2000 Compatible Access\" everyone /add and reboot the server.
You will also need the username/password of a Domain Admin to join the machine to the Windows(TM) domain.
If networking is not yet enabled, Drakx will attempt to join the domain after the network setup step.
Should this setup fail for some reason and domain authentication is not working, run 'smbpasswd -j DOMAIN -U USER%%PASSWORD' using your Windows(tm) Domain, and Admin Username/Password, after system boot.
The command 'wbinfo -t' will test whether your authentication secrets are good."))
	  if $kind eq 'winbind';

	$authentication->{AD_domain} ||= $netc->{DOMAINNAME} if $kind eq 'SMBKRB';
	 $authentication->{AD_users_idmap} ||= 'ou=idmap,' . domain_to_ldap_domain($authentication->{AD_domain}) if $kind eq 'SMBKRB';
	$netc->{WINDOMAIN} ||= $netc->{DOMAINNAME};
	my $anonymous;
	$in->ask_from('',
		      $kind eq 'SMBKRB' ? N("Authentication Active Directory") : N("Authentication Windows Domain"),
		        [ if_($kind eq 'SMBKRB', 
			  { label => N("Domain"), val => \$authentication->{AD_domain} }
			     ),
			  { label => N("Windows Domain"), val => \$netc->{WINDOMAIN} },
			  { label => N("Domain Admin User Name"), val => \$authentication->{winuser} },
			  { label => N("Domain Admin Password"), val => \$authentication->{winpass}, hidden => 1 },
			  { label => N("Use Idmap for store UID/SID "), val => \$anonymous, type => 'bool' },
			  { label => N("Default Idmap "), val => \$authentication->{AD_users_idmap}, disabled => sub { $anonymous } },
			]) or return;
    }
    $authentication->{$kind} ||= 1;
    1;
}

sub set {
    my ($in, $netc, $authentication, $when_network_is_up) = @_;

    any::enableShadow() if $authentication->{shadow};    

    my $kind = authentication::to_kind($authentication);

    log::l("authentication::set $kind");

    if ($kind eq 'LDAP') {
	$in->do_pkgs->install(qw(openldap-clients nss_ldap pam_ldap autofs));

	my $domain = $netc->{LDAPDOMAIN} || do {
	    my $s = run_program::rooted_get_stdout($::prefix, 'ldapsearch', '-x', '-h', $authentication->{LDAP_server}, '-b', '', '-s', 'base', '+');
	    first($s =~ /namingContexts: (.+)/);
	} or log::l("no ldap domain found on server $authentication->{LDAP_server}"), return;

	set_nsswitch_priority('ldap');
	set_pam_authentication('ldap');

	update_ldap_conf(
			 host => $authentication->{LDAP_server},
			 base => $domain,
			 nss_base_shadow => $domain."?sub",
			 nss_base_passwd => $domain."?sub",
			 nss_base_group => $domain."?sub",
			);
    } elsif ($kind eq 'AD') {
	$in->do_pkgs->install(qw(nss_ldap pam_krb5 libsasl2-plug-gssapi));
	my $port = "389";
	
	set_nsswitch_priority('ldap');
	set_pam_authentication('krb5');

	my $ssl = { 
		   anonymous => 'off', 
		   simple => 'off', 
		   tls => 'start_tls',
		   ssl => 'on',
		   kerberos => 'off',
		  }->{$authentication->{sub_kind}};

	if ($ssl eq 'on') {
		$port = '636';
	};
	
	
	
	update_ldap_conf(
			 host => $authentication->{AD_server},
			 base => domain_to_ldap_domain($authentication->{AD_domain}),
			 nss_base_shadow => "$authentication->{AD_users_db}?sub",
			 nss_base_passwd => "$authentication->{AD_users_db}?sub",
			 nss_base_group => "$authentication->{AD_users_db}?sub",

			 ssl => $ssl,
			 sasl_mech => $authentication->{sub_kind} eq 'kerberos' ? 'GSSAPI' : '',
			 port => $port,

			 binddn => $authentication->{AD_user},
			 bindpw => $authentication->{AD_password},

			 (map_each { "nss_map_objectclass_$::a" => $::b }
			  posixAccount => 'User',
			  shadowAccount => 'User',
			  posixGroup => 'Group',
			 ),


			 scope => 'sub',
			 pam_login_attribute => 'sAMAccountName',
			 pam_filter => 'objectclass=User',
			 pam_password => 'ad',

			 
			 (map_each { "nss_map_attribute_$::a" => $::b }
			  uid => 'sAMAccountName',
			  uidNumber => 'msSFU30UidNumber',
			  gidNumber => 'msSFU30GidNumber',
			  cn => 'sAMAccountName',
			  uniqueMember => 'member',
			  userPassword => 'msSFU30Password',
			  homeDirectory => 'msSFU30HomeDirectory',
			  loginShell => 'msSFU30LoginShell',
			  gecos => 'name',
			 ),
			);

	configure_krb5_for_AD($authentication);

    } elsif ($kind eq 'NIS') {
	$in->do_pkgs->install(qw(ypbind autofs));
	my $domain = $netc->{NISDOMAIN};
	$domain || $authentication->{NIS_server} ne "broadcast" or die N("Can't use broadcast with no NIS domain");
	my $t = $domain ? "domain $domain" . ($authentication->{NIS_server} ne "broadcast" && " server") : "ypserver";
	substInFile {
	    $_ = "#~$_" unless /^#/;
	    $_ .= "$t $authentication->{NIS_server}\n" if eof;
	} "$::prefix/etc/yp.conf";

	set_nsswitch_priority('nis');
	#- no need to modify system-auth for nis

	$when_network_is_up->(sub {
	    run_program::rooted($::prefix, 'nisdomainname', $domain);
	    run_program::rooted($::prefix, 'service', 'ypbind', 'restart');
	}) if !$::isInstall; #- TODO: also do it during install since nis can be useful to resolve domain names. Not done because 9.2-RC
#    } elsif ($kind eq 'winbind' || $kind eq 'AD' && $authentication->{subkind} eq 'winbind') {

#	}) if !$::isInstall; 
#- TODO: also do it during install since nis can be useful to resolve domain names. Not done because 9.2-RC
    } elsif ($kind eq 'winbind') {

	my $domain = uc $netc->{WINDOMAIN};
	
	$in->do_pkgs->install('samba-winbind');
	set_nsswitch_priority('winbind');
	set_pam_authentication('winbind');

	require network::smb;
	network::smb::write_smb_conf($domain);
	run_program::rooted($::prefix, "chkconfig", "--level", "35", "winbind", "on");
	mkdir_p("$::prefix/home/$domain");
	run_program::rooted($::prefix, 'service', 'smb', 'restart');
	run_program::rooted($::prefix, 'service', 'winbind', 'restart');
	
	#- defer running smbpassword until the network is up

	$when_network_is_up->(sub {
	    run_program::rooted($::prefix, 'net', 'join', $domain, '-U', $authentication->{winuser} . '%' . $authentication->{winpass});
	});
    } elsif ($kind eq 'SMBKRB') {
	 $authentication->{AD_server} ||= 'ads.' . $authentication->{AD_domain};
	my $domain = uc $netc->{WINDOMAIN};
	my $realm = $authentication->{AD_domain};

	configure_krb5_for_AD($authentication);
	$in->do_pkgs->install('samba-winbind', 'pam_krb5', 'samba-server', 'samba-client');
	set_nsswitch_priority('winbind');
	set_pam_authentication('winbind');

		
	require network::smb;
	network::smb::write_smb_ads_conf($domain,$realm);
	run_program::rooted($::prefix, "chkconfig", "--level", "35", "winbind", "on");
	mkdir_p("$::prefix/home/$domain");
	run_program::rooted($::prefix, 'net', 'time', 'set', '-S', $authentication->{AD_server});
	run_program::rooted($::prefix, 'service', 'smb', 'restart');
	run_program::rooted($::prefix, 'service', 'winbind', 'restart');
	
	$when_network_is_up->(sub {
	    run_program::rooted($::prefix, 'net', 'ads', 'join', '-U', $authentication->{winuser} . '%' . $authentication->{winpass});
	});
    }
}


sub pam_modules() {
    'pam_ldap', 'pam_winbind', 'pam_krb5', 'pam_mkhomedir';
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

sub set_pam_authentication {
    my (@authentication_kinds) = @_;
    
    my %special = (
	auth => \@authentication_kinds,
	account => \@authentication_kinds,
	password => [ intersection(\@authentication_kinds, [ 'ldap', 'krb5' ]) ],
    );
    my %before_first = (
	session => intersection(\@authentication_kinds, [ 'winbind', 'krb5','ldap' ]) ? pam_format_line('session', 'optional', 'pam_mkhomedir', 'skel=/etc/skel/', 'umask=0022') : '',
    );
    my %after_deny = (
	session => member('krb5', @authentication_kinds) ? pam_format_line('session', 'optional', 'pam_krb5') : '',
    );

    substInFile {
	my ($type, $control, $module, @para) = split;
	if ($module = pam_module_from_path($module)) {
	    if (member($module, pam_modules())) {
		#- first removing previous config
		$_ = '';
	    }
	    if ($module eq 'pam_unix' && $special{$type} && @{$special{$type}}) {
		my @para_for_last = 
		  $type eq 'auth' ? qw(likeauth nullok use_first_pass) :
		  $type eq 'account' ? qw(use_first_pass) : @{[]};
		@para = difference2(\@para, \@para_for_last);

		my ($before, $after) = partition { $_ eq 'krb5' } @{$special{$type}};
		my @l = ((map { [ "pam_$_" ] } @$before),
			 [ 'pam_unix', @para ],
			 (map { [ "pam_$_" ] } @$after),
			 );
		push @{$l[-1]}, @para_for_last;
		$_ = join('', map { pam_format_line($type, 'sufficient', @$_) } @l);

		if ($control eq 'required') {
		    #- ensure a pam_deny line is there
		    ($control, $module, @para) = ('required', 'pam_deny');
		    $_ .= pam_format_line($type, $control, $module);
		}
	    }
	    if (my $s = delete $before_first{$type}) {
		$_ = $s . $_;
	    }
	    if ($control eq 'required' && member($module, 'pam_deny', 'pam_unix')) {
		if (my $s = delete $after_deny{$type}) {
		    $_ .= $s;
		}
	    }
	}
    } "$::prefix/etc/pam.d/system-auth";
}

sub get_pam_authentication_kinds() {
    my $before_deny = get_raw_pam_authentication();
    map { s/pam_//; $_ } keys %{$before_deny->{auth}};
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
				     dns_lookup_realm => $authentication->{AD_server} ? 'false' : 'true',
				     dns_lookup_kdc => $authentication->{AD_server} ? 'false' : 'true',
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

sub krb5_conf_update {
    my ($file, $category, %subst_) = @_;

    my %subst = map { lc($_) => [ $_, $subst_{$_} ] } keys %subst_;

    my $s;
    foreach (MDK::Common::File::cat_($file), "[NOCATEGORY]\n") {
	if (my $i = /^\s*\[\Q$category\E\]/i ... /^\[/) {
	    if ($i =~ /E/) { #- for last line of category
		chomp $s; $s .= "\n";
		$s .= " $_->[0] = $_->[1]\n" foreach values %subst;
		%subst = ();
	    } elsif (/^\s*([^=]*?)\s*=/) {
		if (my $e = delete $subst{lc($1)}) {
		    $_ = " $1 = $e->[1]\n";
		}
	      }
	}
	$s .= $_ if !/^\Q[NOCATEGORY]/;
    }

    #- if category has not been found above.
    if (keys %subst) {
	chomp $s;
	$s .= "\n[$category]\n";
	$s .= " $_->[0] = $_->[1]\n" foreach values %subst;
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

1;

