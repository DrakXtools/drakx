package network::adsl_consts; # $Id$

# This should probably be splited out into ldetect-lst as some provider db

use vars qw(@ISA @EXPORT);
use common;

@ISA = qw(Exporter);
@EXPORT = qw(@adsl_data);

our %adsl_data = (
                  # country|provider => { VPI, VCI_hexa, ... }
                  # dns are provided for when !usepeerdns in peers config file
                  N("Belgium") . "|Tiscali BE" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '212.35.2.1',
                   dns2 => '212.35.2.2',
                  },

                  N("Belgium") . "|Belgacom" =>
                  {
                   vpi => 8,
                   vci => 23,
                  },

                  N("France") . "|Free non dégroupé 512/128" =>
                  { 
                   vpi => 8, 
                   vci => 23,
                   dns1 => '213.228.0.68',
                   dns2 => ' 212.27.32.176',
                   method => 'pppoa',
                  },

                  N("France") . "|Free dégroupé 1024/256 (mini)" =>
                  {
                   vpi => 8,
                   vci => 24,
                   dns1 => '213.228.0.68',
                   dns2 => '212.27.32.176',
                  },

                  N("France") . "|9online 512" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '62.62.156.12',
                   dns2 => '62.62.156.13',
                   method => 'pppoa',
                  },

                  N("France") . "|Club-Internet" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '194.117.200.10',
                   dns2 => '194.117.200.15',
                   method => 'pppoa',
                  },

                  N("France") . "|Wanadoo" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '193.252.19.3',
                   dns2 => '193.252.19.4',
                   method => 'pppoa',
                  },

                  N("France") . "|Télé2 128k " =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '212.151.136.242',
                   dns2 => '130.244.127.162',
                   method => 'pppoa',
                  },

                  N("France") . "|Tiscali.fr 128k" =>
                  {
                   vpi => 8,
                   vci => 23, 
                   dns1 => '213.36.80.1',
                   dns2 => '213.36.80.2',
                   method => 'pppoa',
                  },

                  N("France") . "|Tiscali.fr 512k" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '213.36.80.1',
                   dns2 => '213.36.80.2',
                   method => 'pppoa',
                  },

                  N("Finland") . "|Sonera" =>
                  {
                   vpi => 0,
                   vci => 64,
                  },

                  N("Germany") . "|Deutsche Telekom (DT)" =>
                  {
                   vpi => 1,
                   vci => 20,
                   method => 'pppoe',
                  },

                  N("Germany") . "|1&1" =>
                  {
                   vpi => 1,
                   vci => 20,
                   dns1 => '195.20.224.234',
                   dns2 => '194.25.2.129',
                   method => 'pppoe',
                  },

                  N("Hungary") . "|Matav" =>
                  {
                   vpi => 1,
                   vci => 20,
                  },

                  N("Italy") . "|Telecom Italia" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '195.20.224.234',
                   dns2 => '194.25.2.129',
                   method => 'pppoa',
                  },

                  N("Italy") . "|Tiscali.it" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '195.20.224.234',
                   dns2 => '194.25.2.129',
                   method => 'pppoa',
                  },

                  N("Netherlands") . "|KPN" =>
                  {
                   vpi => 8,
                   vci => 30,
                  },

                  N("Poland") . "|Telekomunikacja Polska (TPSA/neostrada)" =>
                  {
                   vpi => 0,
                   vci => 23,
                   dns1 => '194.204.152.34',
                   dns2 => '217.98.63.164',
                   method => 'pppoa',
                  },

                  N("Portugal") . "|PT" =>
                  {
                   vpi => 0,
                   vci => 23,
                  },
                  
                  N("Spain") . "|Telefónica IP dinámica" =>
                  {
                   vpi => 8,
                   vci => 20,
                   dns1 => '80.58.32.33',
                   dns2 => '80.58.0.97',
                   method => 'pppoe',
                  },
                  N("Spain") . "|Telefonica ip fija" =>
                  {
                   vpi => 8,
                   vci => 20,
                   protocol => 'static',
                   dns1 => '80.58.32.33',
                   dns2 => '80.58.0.97',
                   method => 'static',
                  },

                  N("Spain") . "|Wanadoo/Eresmas" =>
                  {
                   vpi => 8,
                   vci => 23,
                   dns1 => '80.58.0.33',
                   dns2 => '80.58.32.97',
                   method => 'pppoa',
                  },

                  N("Sweden") . "|Telia" =>
                  {
                   vpi => 8,
                   vci => 23,
                  },

                  N("United Kingdom") . "|Tiscali UK " =>
                  {
                   vpi => 0,
                   vci => 26,
                  },

                  N("United Kingdom") . "|British Telecom " =>
                  {
                   vpi => 0,
                   vci => 26
                  },
                 );

1;
