package proxy;

use diagnostics;
use strict;
use run_program;
use common qw(:common :system :file);
use log;
use c;

my $config_file = "/usr/lib/wgetrc";

sub main {
    my ($prefix, $in, $install) = @_;
  begin:
    $::isWizard = 1;
    $::Wizard_no_previous = 1;
    $in->ask_okcancel(_("Proxy configuration"),
                      _("Welcome to the proxy configuration utility.\n\nHere, you'll be able to set up your http and ftp proxies\nwith or without login and password\n"
	               ), 1) or quit_global($in, 0);
  
    my $proxy_cfg = {};

    # grab current config
    open F, $config_file;
    while (<F>)
    {
      if (/http_proxy = (http:.*):(.*)/)
      {
        $proxy_cfg->{http_url} = $1;
	$proxy_cfg->{http_port} = $2;
      }
      if (/ftp_proxy = (ftp:.*):(.*)/)
      {
        $proxy_cfg->{ftp_url} = $1;
	$proxy_cfg->{ftp_port} = $2;
      }
      /http_user = (.*)/ and $proxy_cfg->{login} = $1;
      /http_passwd = (.*)/ and $proxy_cfg->{passwd} = $1;
    }
    
    # http proxy
    $in->ask_from_entries_refH(_("Proxy configuration"),
                               _("Please fill in the http proxy informations"),
         [
           { label => _("URL"), val => \$proxy_cfg->{http_url} },
           { label => _("port"), val => \$proxy_cfg->{http_port} }
	 ]
    );
    undef $::Wizard_no_previous;
    # ftp proxy
    $in->ask_from_entries_refH(_("Proxy configuration"),
                               _("Please fill in the ftp proxy informations"),
         [
           { label => _("URL"), val => \$proxy_cfg->{ftp_url} },
           { label => _("port"), val => \$proxy_cfg->{ftp_port} }
	 ]
    );
    # proxy login/passwd
    $in->ask_from_entries_refH(_("Proxy configuration"),
                               _("Please enter proxy login and password, if any.\nLeave it blank if you don't want login/passwd"),
         [
	   { label => _("login"), val => \$proxy_cfg->{login} },
	   { label => _("password"), val => \$proxy_cfg->{passwd} }
	 ]
    );
    
    # save config
    substInFile { s/^http_proxy.*\n//; $_ .= "http_proxy = $proxy_cfg->{http_url}:$proxy_cfg->{http_port}\n" if eof } $config_file;
    substInFile { s/^ftp_proxy.*\n//; $_ .= "ftp_proxy = $proxy_cfg->{ftp_url}:$proxy_cfg->{ftp_port}\n" if eof } $config_file;
    if ($proxy_cfg->{login})
    {
      substInFile { s/^http_user.*\n//; $_ .= "http_user = $proxy_cfg->{login}\n" if eof } $config_file;
      substInFile { s/^http_passwd.*\n//; $_ .= "http_passwd = $proxy_cfg->{passwd}\n" if eof } $config_file;
    }
    log::l("[drakproxy] Installation complete, exiting\n");
}

#---------------------------------------------
#                WONDERFULL pad
#---------------------------------------------
1;
