#!/usr/bin/perl

open F, '| /usr/sbin/sendmail -f devel@mandrakesoft.com';

chomp($ver = <STDIN>);

print F 
q(Subject: [DrakX] DrakX snapshot #), $ver, q( uploaded
From: devel@mandrakesoft.com
To: changelog@linux-mandrake.com, install@mandrakesoft.com
Reply-To: install@mandrakesoft.com

);
print F foreach <STDIN>;
