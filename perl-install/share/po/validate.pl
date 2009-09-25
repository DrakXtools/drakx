#!/usr/bin/perl -w

#
# Guillaume Cottenceau (gc@mandrakesoft.com)
#
# Copyright 2000 Mandrakesoft
#
# This software may be freely redistributed under the terms of the GNU
# public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#

# Tool to avoid common grammar errors in po files.

use MDK::Common;

my $col = $ENV{GREP_COLOR} || "01";
sub colorize { "[1;$col;40m@_[0m" }

sub get_file($)
{
    local *FIL;
    open FIL, "$_[0]" or die "Can't open $_[0]";
    my @file_content = <FIL>;
    close FIL;
    my @out;
    my $msgstr = 0;
    my $line_number = 0;
    foreach (@file_content)
    {
	$line_number++;
	/msgid/ and $msgstr = 0;
	/msgstr/ and $msgstr = 1;
	$msgstr and push @out, sprintf("%4d ", $line_number).$_;
    }
    @out;
}


sub check
{
    my ($category, $condition, $msg, @exceptions) = @_;
    my $line = $_;
    my $rest = '';
    #- kinda hard to make multiple match and still can highlight the right one..
    my $adv = sub { $rest .= substr $line, 0, 1; $line =~ s/^.// };
    while (length($line) > 1) {
	$line =~ /$condition/ or return;
	my ($rest_, $before, $match, $after) = ($rest, $`, $&, $');
	$adv->() foreach 1 .. length($before);
	$_->($before, $match, $after) and goto next_char foreach @exceptions;
	printf "$category: %-30s ", $msg; print $rest_, $before, colorize($match), $after;
      next_char:
	$adv->() foreach 1 .. length($match);
    }
}


my @names = qw(XFree MHz GHz KBabel XFdrake IPv4 MTools iBook DrakX MacOS MacOSX G3 G4 DVD
               Drakbackup Inc Gnome Mandrake IceWM MySQL PostgreSQL Enlightenment Window WindowMaker Fvwm
               SunOS ReiserFS iMac
               CD OF LPRng ext2FS PowerBook OSs CUPS NIS KDE GNOME BootX TVout
               WebDAV IP SMB Boston MA MtoolsFM PCI USB ISA PnP XawTV PSC LaserJet Sony LPT\d
               Frank Thomas Sergey XSane M ClusterNFS 3Com drakTermServ RAMdisk LOCAL);

sub match {
    my ($e) = @_; sub {
	my ($before, $match, $after) = @_;
	$match =~ /^$e/
    }
}
sub match_after {
    my ($e) = @_; sub {
	my ($before, $match, $after) = @_;
	"$match$after" =~ /^$e/
    }
}
sub match_full {
    my ($e) = @_; sub {
	my ($before, $match, $after) = @_;
	"$match$after" =~ /^$e/
    }
}

sub mixed_case($)
{
    check('**', '\b\w[A-Z]\w*[a-z]\b', 'mixed-case',
	  sub { my ($b, $m, $a) = @_; $b =~ /\\$/ && $m =~ /^t/ },
	  sub { my ($b, $m, $a) = @_; $b =~ /\\$/ && $m =~ /^fI/ },
	  match('_[A-Z][a-z]+\b'),
	  map { match_after($_.'\b') } @names);
    check('**', '\b\w[a-z]\w*[A-Z]\b', 'mixed-case',
	  map { match_after($_.'\b') } @names);
}

sub uppercase_after_comma($)
{
    check('**', ', [A-Z]', 'uppercase-after-comma',
	  map { match_after(", $_".'\b') } @names);
}

sub lowercase_after_dot($)
{
    check('**', '\. [a-z]', 'lowercase-after-dot',
	  sub { my ($b, $m, $a) = @_; any { $b =~ /$_$/ } qw(id ex) },
	  sub { my ($b, $m, $a) = @_; any { $b =~ /\Q$_\E$/ } qw (S.A N.B) },
	  map { match_after('\. '.$_) } @names);
}

sub no_space_after_ponct($)
{
    check('**', '[,\.:;]\w', 'no-space-after-ponct',
	  sub { my ($b, $m, $a) = @_; any { my ($beg, $end) = /^(.)(..)/; $b =~ /$beg$/ && $m eq $end } qw(S.A N.B M.N L.P) },
	  sub { my ($b, $m, $a) = @_; any { my ($beg, $end) = /^(...)(..)/; $b =~ /\Q$beg\E$/ && $m eq $end } qw(M.N.F L.P.I) },
	  sub { my ($b, $m, $a) = @_; any { "$m$a" =~ /\S*\.$_\b/ }
		  qw(com fr h d htm o org php php3 cf conf img deny pfm afm cfg tftpd allow bin uk lzrom nbi net old dir scale tbxi) },
	  match_after('\.ex\.'),    #- p.ex.
	  match(':[a-fA-F]'),       #- ipv6
	  map { match_after(".$_") } qw(cmode mclk vmode LTR rpmnew backupignore root_squash all_squash), 0..9 );
}

sub doubly_ponct($)
{
    check('**', '([\.,:;])\1', 'doubly-ponct',
	  match_after(quotemeta('...')));
}

sub space_before_simple_ponct($)
{
    check('**', '\s[,\.]', 'space-before-simple-ponct',
	  map { match_after('\s\.'.$_) } qw(rpmnew backupignore afm pfm));
}



# --- fr.po

foreach (get_file("fr.po"))
{
    #- line oriented verifications
    /\s*#/ and next;

    check('fr', 'ez\s+\S+ez', 'infinitive-form-with-ez');
    check('fr', 'è[ \.,;:]', 'grave-accent-at-end-of-word');
    check('fr', '\b\w*[éêè][éêè]\w*\b', 'strange-accents-succession',
	  map { match($_) } qw(créé réécrire));
    mixed_case($_);
    uppercase_after_comma($_);
    lowercase_after_dot($_);
    no_space_after_ponct($_);
    doubly_ponct($_);
    space_before_simple_ponct($_);
}
