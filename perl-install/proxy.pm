package proxy;

use diagnostics;
use strict;
use run_program;
use common qw(:common :system :file);
use log;
use c;

sub main {
    my ($prefix, $in, $install) = @_;
  begin:
    $::isWizard = 1;
    $::Wizard_no_previous = 1;
    $in->ask_okcancel(_("Proxy configuration"), _("blabla proxy"), 1) or quit_global($in, 0);
   
    # http proxy
    my $http_proxy = {};
    $http_proxy->{url} = "http://bla.foo.fr/";
    $in->ask_from_entries_refH(_("Proxy configuration"),
                               _("Please fill in the http proxy informations"),
         [
           { label => _("URL"), val => \$http_proxy->{url} },
           { label => _("port"), val => \$http_proxy->{port} }
	 ]
    );
    undef $::Wizard_no_previous;
    # ftp proxy
    my $ftp_proxy = {};
    $ftp_proxy->{url} = "http://bla.foo.fr/";
    $in->ask_from_entries_refH(_("Proxy configuration"),
                               _("Please fill in the ftp proxy informations"),
         [
           { label => _("URL"), val => \$ftp_proxy->{url} },
           { label => _("port"), val => \$ftp_proxy->{port} }
	 ]
    );
    # proxy login/passwd
    my $proxy_login = {};
    $in->ask_from_entries_refH(_("Proxy configuration"),
                               _("Please enter proxy login and password, if any"),
         [
	   { label => _("login"), val => \$proxy_login->{login} },
	   { label => _("password"), val => \$proxy_login->{passwd} }
	 ]
    );
    
    print "http: $http_proxy->{url}:$http_proxy->{port}\n";
    print "ftp: $ftp_proxy->{url}:$ftp_proxy->{port}\n";
    print "login: $proxy_login->{login}, $proxy_login->{passwd}\n";
    
    log::l("[drakproxy] Installation complete, exiting\n");
}

#---------------------------------------------
#                WONDERFULL pad
#---------------------------------------------
1;
