#!/usr/bin/perl

open F, '|/usr/sbin/sendmail -oi -t';

chomp($ver = <STDIN>);

print F 
q(Subject: [DrakX] DrakX snapshot #), $ver, q( uploaded
From: DrakX Builder Robot <devel@mandrakesoft.com>
To: changelog@linux-mandrake.com
Reply-To: install@mandrakesoft.com

);
print F foreach <STDIN>;
