#!/usr/bin/perl -w

#
# Guillaume Cottenceau (gc@mandrakesoft.com)
#
# Copyright 2000 MandrakeSoft
#
# This software may be freely redistributed under the terms of the GNU
# public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#

# Tool to avoid common grammar errors in po files.


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


my $line_number = 0;

# --- Problems potentially common to multiple languages

sub mixed_case($)
{
    (/[\^ ][A-Z][A-Z][a-z]/ && !/XFree/ || /[\^ ][a-z][A-Z]/) and print("**.po possible-mixed-case         $_");
}

sub uppercase_after_comma($)
{
    /, [A-Z]/ and print("**.po uppercase-after-comma       $_");
}

sub lowercase_after_dot($)
{
    /\. [a-z]/ and print("**.po lowercase-after-dot         $_");
}

sub no_space_after_simple_ponct($)
{
    /[a-zA-Z\.]+@[a-zA-Z]/ and return;
    /[,\.][a-zA-Z]/ and print("**.po no-space-after-simple-ponct $_");
}

sub space_before_simple_ponct($)
{
    / \.\./ and return;
    / [,\.]/ and print("**.po space-before-simple-ponct   $_");
}



# --- fr.po

foreach (get_file("fr.po"))
{
    /\s*#/ and next;
    /ez [^ ]+ez/ and print("fr.po infinitive-form-with-ez     $_");
    /è[ \.,;:]/ and  print("fr.po grave-accent-at-end-of-word $_");
    (/[éêè][éêè]/ && !/créé/) and print("fr.po strange-accents-succession  $_");
    /G[nN][uU]\/[lL]inux/ and print("fr.po GNU-slash-Linux-found       $_");
    mixed_case($_);
    uppercase_after_comma($_);
    lowercase_after_dot($_);
    no_space_after_simple_ponct($_);
    space_before_simple_ponct($_);
}
