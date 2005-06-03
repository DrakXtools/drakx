package network::adsl_consts; # $Id$

# This should probably be splitted out into ldetect-lst as some provider db

use vars qw(@ISA @EXPORT);
use common;
use utf8;

@ISA = qw(Exporter);
@EXPORT = qw(@adsl_data);

# Originally from :
# http://www.eagle-usb.org/article.php3?id_article=23
# http://www.sagem.com/web-modems/download/support-fast1000-fr.htm
# http://perso.wanadoo.fr/michel-m/protocolesfai.htm

our %adsl_data = (
                  ## format chosen is the following :
                  # country|provider => { VPI, VCI_hexa, ... } all parameters
                  # country is automagically translated into LANG with N function
                  # provider is kept "as-is", not translated
                  # provider_id is used by eagleconfig to identify an ISP (I use ISO_3166-1)
                  #      see http://en.wikipedia.org/wiki/ISO_3166-1
                  # url_tech : technical URL providing info about ISP
                  # vpi : virtual path identifier
                  # vci : virtual channel identifier (in hexa below !!)
                  # Encapsulation:
                  #     1=PPPoE LLC, 2=PPPoE VCmux (never used ?)
                  #     3=RFC1483/2684 Routed IP LLC,
                  #     4=RFC1483/2684 Routed IP (IPoA VCmux)
                  #     5 RFC2364 PPPoA LLC,
                  #     6 RFC2364 PPPoA VCmux
                  #      see http://faq.eagle-usb.org/wakka.php?wiki=AdslDescription
                  # dns are provided for when !usepeerdns in peers config file
                  #     dnsServer2 dnsServer3 : main DNS
                  #     dnsServers_text : string with any valid DNS (when more than 2)
                  # DOMAINNAME2 : used for search key in /etc/resolv.conf
                  # method : PPPoA, pppoe, static or dhcp
                  # methods_all : all methods for connection with this ISP (when more than 1)
                  # modem : model of modem provided by ISP or tested with ISP
                  # please forward updates to http://forum.eagle-usb.org
                  # try to order alphabetically by country (in English) / ISP (local language)

                  N("Algeria") . "|Wanadoo" =>
                  {
                   provider_id => 'DZ01',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                   dnsServer2 => '82.101.136.29',
                   dnsServer3 => '82.101.136.206',
                  },

                  N("Argentina") . "|Speedy" =>
                  {
                   provider_id => 'AR01',
                   vpi => 1,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                   dnsServer2 => '200.51.254.238',
                   dnsServer3 => '200.51.209.22',
                  },

                  N("Austria") . "|Any" =>
                  {
                   provider_id => 'AT00',
                   vpi => 8,
                   vci => 30,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Austria") . "|AON" =>
                  {
                   provider_id => 'AT01',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Austria") . "|Telstra" =>
                  {
                   provider_id => 'AT02',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Belgium") . "|ADSL Office" =>
                  {
                   provider_id => 'BE04',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Belgium") . "|Tiscali BE" =>
                  {
                   provider_id => 'BE01',
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
                   provider_id => 'BE03',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Belgium") . "|Turboline" =>
                  {
                   provider_id => 'BE02',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 5,
                   method => 'pppoa',
                  },

                  N("Brazil") . "|Speedy/Telefonica" =>
                  {
                   provider_id => 'BR01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                   dnsServer2 => '200.204.0.10',
                   dnsServer3 => '200.204.0.138',
                  },

                  N("Brazil") . "|Velox/Telemar" =>
                  {
                   provider_id => 'BR02',
                   vpi => 0,
                   vci => 21,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Brazil") . "|Turbo/Brasil Telecom" =>
                  {
                   provider_id => 'BR03',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Brazil") . "|Rio Grande do Sul (RS)" =>
                  {
                   provider_id => 'BR04',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Bulgaria") . "|BTK ISDN" =>
                  {
                   provider_id => 'BG02',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Bulgaria") . "|BTK POTS" =>
                  {
                   provider_id => 'BG01',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Beijing" =>
                  {
                   provider_id => 'CN01',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Changchun" =>
                  {
                   provider_id => 'CN02',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Harbin" =>
                  {
                   provider_id => 'CN03',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Jilin" =>
                  {
                   provider_id => 'CN04',
                   vpi => 0,
                   vci => 27,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Lanzhou" =>
                  {
                   provider_id => 'CN05',
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Tianjin" =>
                  {
                   provider_id => 'CN06',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Xi'an" =>
                  {
                   provider_id => 'CN07',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Chongqing" =>
                  {
                   provider_id => 'CN08',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Fujian" =>
                  {
                   provider_id => 'CN09',
                   vpi => 0,
                   vci => 0xc8,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Guangxi" =>
                  {
                   provider_id => 'CN10',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Guangzhou" =>
                  {
                   provider_id => 'CN11',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Hangzhou" =>
                  {
                   provider_id => 'CN12',
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Netcom|Hunan" =>
                  {
                   provider_id => 'CN13',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Nanjing" =>
                  {
                   provider_id => 'CN14',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Shanghai" =>
                  {
                   provider_id => 'CN15',
                   vpi => 8,
                   vci => 51,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Shenzhen" =>
                  {
                   provider_id => 'CN16',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Urumqi" =>
                  {
                   provider_id => 'CN17',
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Wuhan" =>
                  {
                   provider_id => 'CN18',
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Yunnan" =>
                  {
                   provider_id => 'CN19',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("China") . "|China Telecom|Zhuhai" =>
                  {
                   provider_id => 'CN20',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Czech Republic") . "|Cesky Telecom" =>
                  {
                   provider_id => 'CZ01',
                   url_tech => 'http://www.telecom.cz/domacnosti/internet/pristupove_sluzby/broadband/vse_o_kz_a_moznostech_instalace.php',
                   vpi => 8,
                   vci => 48,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Denmark") . "|Any" =>
                  {
                   provider_id => 'DK01',
                   vpi => 0,
                   vci => 65,
                   method => 'pppoe',
                   Encapsulation => 3,
                  },

                  N("Finland") . "|Sonera" =>
                  {
                   provider_id => 'FI01',
                   vpi => 0,
                   vci => 64,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("France") . "|Free non dégroupé 512/128 & 1024/128" =>
                  {
                   provider_id => 'FR01',
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
                   provider_id => 'FR04',
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
                   provider_id => 'FR05',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.30.93.108',
                   dnsServer3 => '212.203.124.146',
                   method => 'pppoa',
                  },

                  N("France") . "|Cegetel non dégroupé 512 IP/ADSL et dégroupé" =>
                  {
                   provider_id => 'FR08',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.94.174.85',
                   dnsServer3 => '212.94.174.86',
                   method => 'pppoa',
                  },

                  N("France") . "|Club-Internet" =>
                  {
                   provider_id => 'FR06',
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
                   provider_id => 'FR09',
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
                   provider_id => 'FR02',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.151.136.242',
                   dnsServer3 => '130.244.127.162',
                   method => 'pppoa',
                  },

                  N("France") . "|Tiscali.fr 128k" =>
                  {
                   provider_id => 'FR03',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 5,
                   dnsServer2 => '213.36.80.1',
                   dnsServer3 => '213.36.80.2',
                   method => 'pppoa',
                  },

                  N("France") . "|Tiscali.fr 512k" =>
                  {
                   provider_id => 'FR07',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '213.36.80.1',
                   dnsServer3 => '213.36.80.2',
                   method => 'pppoa',
                  },

                  N("Germany") . "|Deutsche Telekom (DT)" =>
                  {
                   provider_id => 'DE01',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Germany") . "|1&1" =>
                  {
                   provider_id => 'DE02',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   dnsServer2 => '195.20.224.234',
                   dnsServer3 => '194.25.2.129',
                   method => 'pppoe',
                  },

                  N("Greece") . "|Any" =>
                  {
                   provider_id => 'GR01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Hungary") . "|Matav" =>
                  {
                   provider_id => 'HU01',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Ireland") . "|Any" =>
                  {
                   provider_id => 'IE01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Israel") . "|Bezeq" =>
                  {
                   provider_id => 'IL01',
                   vpi => 8,
                   vci => 30,
                   Encapsulation => 6,
                   dnsServer2 => '192.115.106.10',
                   dnsServer3 => '192.115.106.11',
                   method => 'pppoa',
                  },

                  N("Italy") . "|Libero.it" =>
                  {
                   provider_id => 'IT04',
                   url_tech => 'http://internet.libero.it/assistenza/adsl/installazione_ass.phtml',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '193.70.192.25',
                   dnsServer3 => '193.70.152.25',
                   method => 'pppoa',
                  },

                  N("Italy") . "|Telecom Italia" =>
                  {
                   provider_id => 'IT01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '195.20.224.234',
                   dnsServer3 => '194.25.2.129',
                   method => 'pppoa',
                  },

                  N("Italy") . "|Telecom Italia/Office Users (ADSL Smart X)" =>
                  {
                   provider_id => 'IT02',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'static',
                  },

                  N("Italy") . "|Tiscali.it, Alice" =>
                  {
                   provider_id => 'IT03',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '195.20.224.234',
                   dnsServer3 => '194.25.2.129',
                   method => 'pppoa',
                  },

                  N("Lithuania") . "|Lietuvos Telekomas" =>
                  {
                   provider_id => 'LT01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Morocco") . "|Maroc Telecom" =>
                  {
                   provider_id => 'MA01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '212.217.0.1',
                   dnsServer3 => '212.217.0.12',
                   method => 'pppoa',
                  },

                  N("Netherlands") . "|KPN" =>
                  {
                   provider_id => 'NL01',
                   vpi => 8,
                   vci => 30,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Netherlands") . "|Eager Telecom" =>
                  {
                   provider_id => 'NL02',
                   vpi => 0,
                   vci => 21,
                   Encapsulation => 3,
                   method => 'dhcp',
                  },

                  N("Netherlands") . "|Tiscali" =>
                  {
                   provider_id => 'NL03',
                   vpi => 0,
                   vci => 22,
                   Encapsulation => 3,
                   method => 'dhcp',
                  },

                  N("Netherlands") . "|Versatel" =>
                  {
                   provider_id => 'NL04',
                   vpi => 0,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'dhcp',
                  },

                  N("Norway") . "|Bluecom" =>
                    {
                        method => 'dhcp',
                    },

                  N("Norway") . "|Firstmile" =>
                    {
                        method => 'dhcp',
                    },

                  N("Norway") . "|NextGenTel" =>
                    {
                        method => 'dhcp',
                    },

                  N("Norway") . "|SSC" =>
                    {
                        method => 'dhcp',
                    },

                  N("Norway") . "|Tele2" =>
                    {
                        method => 'dhcp',
                    },

                  N("Norway") . "|Telenor ADSL" =>
                    {
                        method => 'PPPoE',
                    },

                  N("Norway") . "|Tiscali" =>
                    {
                        vpi => 8,
                        vci => 35,
                        method => 'dhcp',
                    },

                  N("Poland") . "|Telekomunikacja Polska (TPSA/neostrada)" =>
                  {
                   provider_id => 'PL01',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '194.204.152.34',
                   dnsServer3 => '217.98.63.164',
                   method => 'pppoa',
                  },

                  N("Poland") . "|Netia neostrada" =>
                  {
                   provider_id => 'PL02',
                   url_tech => 'http://www.netia.pl/?o=d&s=210',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   dnsServer2 => '195.114.181.130',
                   dnsServer3 => '195.114.161.61',
                   method => 'pppoe',
                  },

                  N("Portugal") . "|PT" =>
                  {
                   provider_id => 'PT01',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Russia") . "|MTU-Intel" =>
                  {
                   provider_id => 'RU01',
                   url_tech => 'http://stream.ru/s-requirements',
                   vpi => 1,
                   vci => 50,
                   Encapsulation => 1,
                   dnsServer2 => '212.188.4.10',
                   dnsServer3 => '195.34.32.116',
                   method => 'pppoe',
                  },

                  N("Slovenia") . "|SiOL" =>
                  {
                   provider_id => 'SL01',
                   vpi => 1,
                   vci => 20,
                   method => 'pppoe',
                   Encapsulation => 1,
                   dnsServer2 => '193.189.160.11',
                   dnsServer3 => '193.189.160.12',
                   DOMAINNAME2 => 'siol.net',
                  },

                  N("Spain") . "|Telefónica IP dinámica" =>
                  {
                   provider_id => 'ES01',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   dnsServer2 => '80.58.32.33',
                   dnsServer3 => '80.58.0.97',
                   method => 'pppoe',
                  },

                  N("Spain") . "|Telefónica ip fija" =>
                  {
                   provider_id => 'ES02',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'static',
                   dnsServer2 => '80.58.32.33',
                   dnsServer3 => '80.58.0.97',
                  },

                  N("Spain") . "|Wanadoo/Eresmas Retevision" =>
                  {
                   provider_id => 'ES03',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 6,
                   dnsServer2 => '80.58.0.33',
                   dnsServer3 => '80.58.32.97',
                   method => 'pppoa',
                  },

                  N("Spain") . "|Wanadoo PPPoE" =>
                  {
                   provider_id => 'ES04',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Spain") . "|Wanadoo ip fija" =>
                  {
                   provider_id => 'ES05',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'static',
                  },

                  N("Spain") . "|Tiscali" =>
                  {
                   provider_id => 'ES06',
                   vpi => 1,
                   vci => 20,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Arrakis" =>
                  {
                   provider_id => 'ES07',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Auna" =>
                  {
                   provider_id => 'ES08',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Communitel" =>
                  {
                   provider_id => 'ES09',
                   vpi => 0,
                   vci => 21,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Euskatel" =>
                  {
                   provider_id => 'ES10',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Spain") . "|Uni2" =>
                  {
                   provider_id => 'ES11',
                   vpi => 1,
                   vci => 21,
                   Encapsulation => 6,
                   method => 'pppoa',
                  },

                  N("Spain") . "|Ya.com PPPoE" =>
                  {
                   provider_id => 'ES12',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 1,
                   method => 'pppoe',
                  },

                  N("Spain") . "|Ya.com static" =>
                  {
                   provider_id => 'ES13',
                   vpi => 8,
                   vci => 20,
                   Encapsulation => 3,
                   method => 'static',
                  },

                  N("Sweden") . "|Telia" =>
                  {
                   provider_id => 'SE01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Switzerland") . "|Any" =>
                  {
                   provider_id => 'CH01',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 3,
                   method => 'pppoe',
                  },

                  N("Switzerland") . "|BlueWin / Swisscom" =>
                  {
                   provider_id => 'CH02',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 5,
                   dnsServer2 => '195.186.4.108',
                   dnsServer3 => '195.186.4.109',
                   method => 'pppoa',
                  },

                  N("Switzerland") . "|Tiscali.ch" =>
                  {
                   provider_id => 'CH03',
                   vpi => 8,
                   vci => 23,
                   Encapsulation => 1,
                   method => 'pppoa',
                  },

                  N("Thailand") . "|Asianet" =>
                  {
                   provider_id => 'TH01',
                   vpi => 0,
                   vci => 64,
                   Encapsulation => 1,
                   dnsServer2 => '203.144.225.242',
                   dnsServer3 => '203.144.225.72',
                   method => 'pppoe',
                  },

                  N("Tunisia") . "|Planet.tn" =>
                  {
                   provider_id => 'TH01',
                   url_tech => 'http://www.planet.tn/',
                   vpi => 0,
                   vci => 23,
                   Encapsulation => 5,
                   dnsServer2 => '193.95.93.77',
                   dnsServer3 => '193.95.66.10',
                   method => 'pppoe',
                  },

                  N("United Arab Emirates") . "|Etisalat" =>
                  {
                   provider_id => 'AE01',
                   vpi => 0,
                   vci => 32,
                   Encapsulation => 5,
                   dnsServer2 => '213.42.20.20',
                   dnsServer3 => '195.229.241.222',
                   method => 'pppoa',
                  },

                  N("United Kingdom") . "|Tiscali UK " =>
                  {
                   provider_id => 'UK01',
                   vpi => 0,
                   vci => 26,
                   Encapsulation => 6,
                   dnsServer2 => '212.74.112.66',
                   dnsServer3 => '212.74.112.67',
                   method => 'pppoa',
                  },

                  N("United Kingdom") . "|British Telecom " =>
                  {
                   provider_id => 'UK02',
                   vpi => 0,
                   vci => 26,
                   Encapsulation => 6,
                   dnsServer2 => '194.74.65.69',
                   dnsServer3 => '194.72.9.38',
                   method => 'pppoa',
                  },

                 );


1;
