#!/usr/bin/perl

open F, '| /usr/sbin/sendmail -f devel@mandrakesoft.com';

print F 
q(Subject: [DrakX] new DrakX snapshot uploaded
From: devel@mandrakesoft.com
To: changelog@linux-mandrake.com, install@mandrakesoft.com
Reply-To: install@mandrakesoft.com

);
print F foreach <STDIN>;
