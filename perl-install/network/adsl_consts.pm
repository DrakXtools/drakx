package network::adsl_consts; # $Id$

# This should probably be splitted out into ldetect-lst as some provider db

use vars qw(@ISA @EXPORT);
use common;
use utf8;

@ISA = qw(Exporter);
@EXPORT = qw(@adsl_data);

# From:
# http://www.eagle-usb.org/article.php3?id_article=23
# http://www.sagem.com/web-modems/download/support-fast1000-fr.htm
# http://perso.wanadoo.fr/michel-m/protocolesfai.htm

our %adsl_data = (
                  # country|provider => { VPI, VCI_hexa, ... }
                  # Encapsulation:
                  #     1=PPPoE LLC, 2=PPPoE VCmux (never used ?)
                  #     3=RFC1483/2684 Routed IP LLC,
                  #     4=RFC1483/2684 Routed IP (IPoA VCmux)
                  #     5 RFC2364 PPPoA LLC,
                  #     6 RFC2364 PPPoA VCmux
                  # dns are provided for when !usepeerdns in peers config file
                  # method : PPPoA, pppoe, static or dhcp
                  # please forward updates to http://forum.eagle-usb.org
                  # order alphabetically by country (in English) / ISP (local language)

                  N("Algeria") . "|Wanadoo" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                   dnsServer2 => '82.101.136.29',
                   dnsServer3 => '82.101.136.206',
                  },

                  N("Argentina") . "|Speedy" =>
                  {
                   vpi => 1,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                   dnsServer2 => '200.51.254.238',
                   dnsServer3 => '200.51.209.22',
                  },

                  N("Austria") . "|Any" =>
                  {
                   vpi => 8,
                   vci => 30,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Austria") . "|AON" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Austria") . "|Telstra" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Belgium") . "|ADSL Office" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Belgium") . "|Tiscali BE" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                   dnsServer2 => '212.35.2.1',
                   dnsServer3 => '212.35.2.2',
                   DOMAINNAME2 => 'tiscali.be',
                  },

                  N("Belgium") . "|Belgacom" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Belgium") . "|Turboline" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 5,
                   method => 'pppoa',
                  },

                  N("Brazil") . "|Speedy/Telefonica" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                   dnsServer2 => '200.204.0.10',
                   dnsServer3 => '200.204.0.138',
                  },

                  N("Brazil") . "|Velox/Telemar" =>
                  {
                   vpi => 0,
                   vci => 21,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Brazil") . "|Turbo/Brasil Telecom" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Brazil") . "|Rio Grande do Sul (RS)" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Bulgaria") . "|BTK ISDN" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Bulgaria") . "|BTK POTS" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Beijing" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Changchun" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Harbin" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Jilin" =>
                  {
                   vpi => 0,
                   vci => 27,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Lanzhou" =>
                  {
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Tianjin" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Xi'an" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Chongqing" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Fujian" =>
                  {
                   vpi => 0,
                   vci => 0xc8,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Guangxi" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Guangzhou" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Hangzhou" =>
                  {
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Hunan" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Nanjing" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Shanghai" =>
                  {
                   vpi => 8,
                   vci => 51,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Shenzhen" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Urumqi" =>
                  {
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Wuhan" =>
                  {
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Yunnan" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Zhuhai" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Czech Republic") . "|Cesky Telecom" =>
                  {
                   vpi => 8,
                   vci => 48,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Denmark") . "|Any" =>
                  {
                   vpi => 0,
                   vci => 65,
                   method => 'pppoe',
                   Encapsulation => 3,
                  },

                  N("Finland") . "|Sonera" =>
                  {
                   vpi => 0,
                   vci => 64,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("France") . "|Free non dégroupé 512/128 & 1024/128" =>
                  { 
                   vpi => 8, 
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '213.228.0.23',
                   dnsServer3 => '212.27.32.176',
                   method => 'pppoa',
                   DOMAINNAME2 => 'free.fr',
                  },

                  N("France") . "|Free dégroupé 1024/256 (mini)" =>
                  {
                   vpi => 8,
                   vci => 24,
                   Encapsulation => 4,
                   dnsServer2 => '213.228.0.23',
                   dnsServer3 => '212.27.32.176',
                   method => 'dhcp',
                   DOMAINNAME2 => 'free.fr',
                  },

                  N("France") . "|n9uf tel9com 512 & dégroupé 1024" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.30.93.108',
                   dnsServer3 => '212.203.124.146',
                   method => 'pppoa',
                  },

                  N("France") . "|Cegetel non dégroupé 512 IP/ADSL et dégroupé" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.94.174.85',
                   dnsServer3 => '212.94.174.86',
                   method => 'pppoa',
                  },

                  N("France") . "|Club-Internet" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '194.117.200.10',
                   dnsServer3 => '194.117.200.15',
                   method => 'pppoa',
                   DOMAINNAME2 => 'club-internet.fr',
                  },

                  N("France") . "|Wanadoo" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '80.10.246.2',
                   dnsServer3 => '80.10.246.129',
                   method => 'pppoa',
                   DOMAINNAME2 => 'wanadoo.fr',
                  },

                  N("France") . "|Télé2" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.151.136.242',
                   dnsServer3 => '130.244.127.162',
                   method => 'pppoa',
                  },

                  N("France") . "|Tiscali.fr 128k" =>
                  {
                   vpi => 8,
                   vci => 23, 
                   Encapsulation => 5,
                   dnsServer2 => '213.36.80.1',
                   dnsServer3 => '213.36.80.2',
                   method => 'pppoa',
                  },

                  N("France") . "|Tiscali.fr 512k" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '213.36.80.1',
                   dnsServer3 => '213.36.80.2',
                   method => 'pppoa',
                  },

                  N("Germany") . "|Deutsche Telekom (DT)" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Germany") . "|1&1" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   dnsServer2 => '195.20.224.234',
                   dnsServer3 => '194.25.2.129',
                   method => 'pppoe',
                  },

                  N("Greece") . "|Any" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Hungary") . "|Matav" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Ireland") . "|Any" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Israel") . "|Bezeq" =>
                  {
                   vpi => 8,
                   vci => 30,
                   Encapsulation => 6,
                   dnsServer2 => '192.115.106.10',
                   dnsServer3 => '192.115.106.11',
                   method => 'pppoa',
                  },

                  N("Italy") . "|Telecom Italia" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '195.20.224.234',
                   dnsServer3 => '194.25.2.129',
                   method => 'pppoa',
                  },
		  
                  N("Italy") . "|Libero.it" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '193.70.192.25',
                   dnsServer3 => '193.70.152.25',
                   method => 'pppoa',
                  },

                  N("Italy") . "|Telecom Italia/Office Users (ADSL Smart X)" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'manual',
                  },

                  N("Italy") . "|Tiscali.it, Alice" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '195.20.224.234',
                   dnsServer3 => '194.25.2.129',
                   method => 'pppoa',
                  },

                  N("Lithuania") . "|Lietuvos Telekomas" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Morocco") . "|Maroc Telecom" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.217.0.1',
                   dnsServer3 => '212.217.0.12',
                   method => 'pppoa',
                  },

                  N("Netherlands") . "|KPN" =>
                  {
                   vpi => 8,
                   vci => 30,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Netherlands") . "|Eager Telecom" =>
                  {
                   vpi => 0,
                   vci => 21,
                   Encapsulation => 3,
                   method => 'dhcp',
                  },

                  N("Netherlands") . "|Tiscali" =>
                  {
                   vpi => 0,
                   vci => 22,
                   Encapsulation => 3,
                   method => 'dhcp',
                  },

                  N("Netherlands") . "|Versatel" =>
                  {
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'dhcp',
                  },

                  N("Poland") . "|Telekomunikacja Polska (TPSA/neostrada)" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '194.204.152.34',
                   dnsServer3 => '217.98.63.164',
                   method => 'pppoa',
                  },

                  N("Poland") . "|Netia neostrada" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   dnsServer2 => '195.114.181.130',
                   dnsServer3 => '195.114.161.61',
                   method => 'pppoe',
                  },

                  N("Portugal") . "|PT" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Russia") . "|MTU-Intel" =>
                  {
                   vpi => 1,
                   vci => 50,
                   Encapsulation => 1,
                   dnsServer2 => '212.188.4.10',
                   dnsServer3 => '195.34.32.116',
                   method => 'pppoe',
                  },

                  N("Slovenia") . "|SiOL" =>
                  {
                   dnsServer2 => '193.189.160.11',
                   dnsServer3 => '193.189.160.12',
                   vpi => 1,
                   vci => 20,
                   method => 'pppoe',
                   DOMAINNAME2 => 'siol.net',
                   Encapsulation => 1,
                  },

                  N("Spain") . "|Telefónica IP dinámica" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   dnsServer2 => '80.58.32.33',
                   dnsServer3 => '80.58.0.97',
                   method => 'pppoe',
                  },
                  N("Spain") . "|Telefónica ip fija" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   dnsServer2 => '80.58.32.33',
                   dnsServer3 => '80.58.0.97',
                   method => 'static',
                  },

                  N("Spain") . "|Wanadoo/Eresmas Retevision" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '80.58.0.33',
                   dnsServer3 => '80.58.32.97',
                   method => 'pppoa',
                  },

                  N("Spain") . "|Wanadoo PPPoE" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Spain") . "|Wanadoo ip fija" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'static',
                  },

                  N("Spain") . "|Tiscali" =>
                  {
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Arrakis" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Auna" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Communitel" =>
                  {
                   vpi => 0,
                   vci => 21,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Euskatel" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Spain") . "|Uni2" =>
                  {
                   vpi => 1,
                   vci => 21,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Ya.com PPPoE" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Spain") . "|Ya.com static" =>
                  {
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'static',
                  },

                  N("Sweden") . "|Telia" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Switzerland") . "|Any" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Switzerland") . "|BlueWin / Swisscom" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 5,
                   dnsServer2 => '195.186.4.108',
                   dnsServer3 => '195.186.4.109',
                   method => 'pppoa',
                  },

                  N("Switzerland") . "|Tiscali.ch" =>
                  {
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoa',
                  },

                  N("Thailand") . "|Asianet" =>
                  {
                   vpi => 0,
                   vci => 64,
                   Encapsulation => 1,
                   dnsServer2 => '203.144.225.242',
                   dnsServer3 => '203.144.225.72',
                   method => 'pppoe',
                  },

                  N("Tunisia") . "|Planet.tn" =>
                  {
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 5,
                   dnsServer2 => '193.95.93.77',
                   dnsServer3 => '193.95.66.10',
                   method => 'pppoe',
                  },

                  N("United Arab Emirates") . "|Etisalat" =>
                  {
                   vpi => 0,
                   vci => 32,
                   Encapsulation => 5,
                   dnsServer2 => '213.42.20.20',
                   dnsServer3 => '195.229.241.222',
                   method => 'pppoa',
                  },

                  N("United Kingdom") . "|Tiscali UK " =>
                  {
                   vpi => 0,
                   vci => 26,
                   Encapsulation => 6,
                   dnsServer2 => '212.74.112.66',
                   dnsServer3 => '212.74.112.67',
                   method => 'pppoa',
                  },

                  N("United Kingdom") . "|British Telecom " =>
                  {
                   vpi => 0,
                   vci => 26,
                   Encapsulation => 6,
                   dnsServer2 => '194.74.65.69',
                   dnsServer3 => '194.72.9.38',
                   method => 'pppoa',
                  },

                 );


1;
