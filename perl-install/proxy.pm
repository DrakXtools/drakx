package proxy;

use diagnostics;
use strict;
use run_program;
use common;
use log;
use c;


sub main {
    my ($prefix, $in) = @_;
    my $proxy_cfg = {};
    my $config_file = "$prefix/usr/lib/wgetrc";

    # grab current config
    foreach (cat_($config_file)) {
      /http_proxy = (http:.*):(\d+)/ and ($proxy_cfg->{http_url}, $proxy_cfg->{http_port}) = ($1, $2);
      /ftp_proxy = (ftp:.*):(\d+)/ and ($proxy_cfg->{ftp_url}, $proxy_cfg->{ftp_port}) = ($1, $2);
      /http_user = (.*)/ and ($proxy_cfg->{login}) = $1;
      if (/http_passwd = (.*)/) {
        ($proxy_cfg->{passwd}) = $1;
        ($proxy_cfg->{passwd2}) = $1;
      }
    }
  begin:
    $::isWizard = 1;
    $::Wizard_no_previous = 1;
    $in->ask_okcancel(_("Proxy configuration"),
                      _("Welcome to the proxy configuration utility.\n\nHere, you'll be able to set up your http and ftp proxies\nwith or without login and password\n"
                       ), 1);

    # http proxy
  step_http_proxy:
    undef $::Wizard_no_previous;
    $proxy_cfg->{http_url} ||= "http://www.proxy.com/";
    $in->ask_from(_("Proxy configuration"),
		  _("Please fill in the http proxy informations\nLeave it blank if you don't want an http proxy"),
		  [ { label => _("URL"), val => \$proxy_cfg->{http_url} },
		    { label => _("port"), val => \$proxy_cfg->{http_port} }
		  ],
		  complete => sub {
		      if ($proxy_cfg->{http_url} && $proxy_cfg->{http_url} !~ /^http:/) {
			  $in->ask_warn('', _("Url should begin with 'http:'"));
			  return (1,0);
		      }
		      if ($proxy_cfg->{http_port} && $proxy_cfg->{http_port} !~ /^\d+$/) {
			  $in->ask_warn('', _("The port part should be numeric"));
			  return (1,1);
		      }
		      0;
		  }
		 ) or goto begin;

    # ftp proxy
    step_ftp_proxy:
    $proxy_cfg->{ftp_url} ||= "ftp://ftp.proxy.com/";
    $in->ask_from(_("Proxy configuration"),
		  _("Please fill in the ftp proxy informations\nLeave it blank if you don't want an ftp proxy"),
		  [ { label => _("URL"), val => \$proxy_cfg->{ftp_url} },
		    { label => _("port"), val => \$proxy_cfg->{ftp_port} }
		  ],
		  complete => sub {
		      if ($proxy_cfg->{ftp_url} && $proxy_cfg->{ftp_url} !~ /^(ftp|http):/) {
			  $in->ask_warn('', _("Url should begin with 'ftp:' or 'http:'"));
			  return (1,0);
		      }
		      if ($proxy_cfg->{ftp_port} && $proxy_cfg->{ftp_port} !~ /^\d+$/) {
			  $in->ask_warn('', _("The port part should be numeric"));
			  return (1,1);
		      }
		      0;
		  }
		 ) or goto step_http_proxy;

    # proxy login/passwd
    step_login:
    $in->ask_from(_("Proxy configuration"),
		  _("Please enter proxy login and password, if any.\nLeave it blank if you don't want login/passwd"),
		  [ { label => _("login"), val => \$proxy_cfg->{login} },
		    {
		     label => _("password"), val => \$proxy_cfg->{passwd}, hidden => 1 },
		    {
		     label => _("re-type password"), val => \$proxy_cfg->{passwd2}, hidden => 1 }
		  ],
		  complete => sub {
		      if ($proxy_cfg->{passwd} ne $proxy_cfg->{passwd2}) {
			  $in->ask_warn('', _("The passwords don't match. Try again!"));
			  return(1,1);
		      }
		      0;
		  }
		 ) or goto step_ftp_proxy;
    # save config
    substInFile {
        s/^(http|ftp)_proxy.*\n//;
        eof and $_ .= "http_proxy = $proxy_cfg->{http_url}:$proxy_cfg->{http_port}
ftp_proxy = $proxy_cfg->{ftp_url}:$proxy_cfg->{ftp_port}\n";
    } $config_file;
    $proxy_cfg->{login} and substInFile {
        s/^http_(user|passwd).*\n//;
        eof and $_ .= "http_user = $proxy_cfg->{login}
http_passwd = $proxy_cfg->{passwd}\n" } $config_file;
    log::l("[drakproxy] Installation complete, exiting\n");
}

#---------------------------------------------
#                WONDERFULL pad
#---------------------------------------------
1;
