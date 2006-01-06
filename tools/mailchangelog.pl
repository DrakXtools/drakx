#!/usr/bin/perl

open F, '|/usr/sbin/sendmail -oi -t';

chomp($ver = <STDIN>);

print F 
q(Subject: [DrakX] DrakX snapshot #), $ver, q( uploaded
From: DrakX Builder Robot <devel@mandriva.com>
To: changelog@mandrivalinux.org
Reply-To: install@mandriva.com

);
print F foreach <STDIN>;
