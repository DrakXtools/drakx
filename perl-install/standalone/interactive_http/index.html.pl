use MDK::Common;

print '<html>
';
foreach (map { chomp_($_) } cat_('authorised_progs')) {
    my $name = basename($_);
    print 
qq(<a href="/interactive_http.cgi?state=new&prog=$_">$name</a>
<br>
);
}
print '
</html>
';
