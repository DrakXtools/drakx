open F, "isdndb.txt" or die "file $file not found";
open G, ">tutu" or die "file $file not found";
foreach (<F>) {
    s/\#.*//;
#    s/\[City\]\s+National//;
    /\[Country\]\s*(.*)/ and $country = $1;
    /\[City\]\s*(.*)/ and $city = $1;
    /\[Name\]\s*(.*)/ and $name = $1;
    /\[Prefix\]\s*(.*)/ and $prefix = $1;
    /\[ISDN\]\s*(.*)/ and $isdn = $1;
    /\[Encaps\]\s*.*/ and  do { defined $dns1 and $dns2=""; };
    /\[Domain\]\s*(.*)/ and $domain = $1;
    /\[DNS\]\s*(.*)/ and ($dns1 ? $dns2 : $dns1) = $1;
    /\[End\]\s*(.*)/ and do { 	undef $name; undef $prefix; undef $isdn; undef $domain; undef $dns1; undef $dns2; };
    if ($isdn && !$prefix) { $prefix = "" }
    if (defined $name && defined $isdn && defined $domain && defined $dns1 && defined $dns2) {
	print G join("|", $country, $city, join("=>", $name, $prefix . $isdn, $domain, $dns1, $dns2)), "\n";
	undef $name;
	undef $prefix;
	undef $isdn;
	undef $domain;
	undef $dns1;
	undef $dns2;
    }
}
