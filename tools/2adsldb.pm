open F, "isplist.txt" or die "file $file not found";
open G, ">tutu" or die "file $file not found";
foreach (<F>) {
    s/\#.*//;
    /.*ADSL.*/ or  next;
#| NOM | PAYS | CONNECTION | MAILTYPE | SMTP | MAILSERVER | NEWS | MY1DNS | MY2DNS | PROXY | PROXYSERVER | DHCP | EMAIL
    s/(.*)france(.*)/$1France$2/;
    s/(.*)FRANCE(.*)/$1France$2/;
    s/(.*)USA(.*)/$1United States$2/;
    s/(.*)U.S.A(.*)/$1United States$2/;
    s/(.*)US(.*)/$1United States$2/;
    s/(.*)usa(.*)/$1United States$2/;
    s/(.*)club-internet(.*)/$1club internet$2/;
    my ($name, $country, $connexion, $mailtype, $smtp, $popserver, $mailserver, $news, $dns1, $dns2, $proxy, $proxyserver, $dhcp, $email) = split /\|/;
    print G join("|", $country, join("=>", $name,   $dns1, $dns2)), "\n"; #$domain,
}

