package handle_configs;

# $Id$

use diagnostics;
use strict;

use common;

sub searchstr {
    # Preceed all characters which are special characters in regexps with
    # a backslash, so that the returned string used in a regexp searches
    # a literal occurence of the original string. White space is replaced
    # by "\s+"
    # "quotemeta()" does not serve for this, as it also quotes some regular
    # characters, as the space
    my ($s) = @_;
    $s =~ s/([\\\/\(\)\[\]\{\}\|\.\$\@\%\*\?\#\+\-])/\\$1/g;
    return $s;
}

sub read_directives {

    # Read one or more occurences of a directive

    my ($lines_ptr, $directive) = @_;

    my @result = ();
    my $searchdirective = searchstr($directive);
    ($_ =~ /^\s*$searchdirective\s+(\S.*)$/ and push(@result, $1)) 
	foreach @{$lines_ptr};
    (chomp) foreach @result;
    return @result;
}

sub read_unique_directive {

    # Read a directive, if the directive appears more than once, use
    # the last occurence and remove all the others, if it does not
    # occur, return the default value

    my ($lines_ptr, $directive, $default) = @_;

    if ((my @d = read_directives($lines_ptr, $directive)) > 0) {
	my $value = $d[$#d];
	set_directive($lines_ptr, "$directive $value");
	return $value;
    } else {
        return $default;
    }
}

sub insert_directive {

    # Insert a directive only if it is not already there

    my ($lines_ptr, $directive) = @_;

    my $searchdirective = searchstr($directive);
    ($_ =~ /^\s*$searchdirective$/ and return 0) foreach @{$lines_ptr};
    push(@{$lines_ptr}, "$directive\n");
    return 1;
}

sub remove_directive {

    # Remove a directive

    my ($lines_ptr, $directive) = @_;

    my $success = 0;
    my $searchdirective = searchstr($directive);
    ($_ =~ /^\s*$searchdirective/ and $_ = "" and $success = 1)
	foreach @{$lines_ptr};
    return $success;
}

sub comment_directive {

    # Comment out a directive

    my ($lines_ptr, $directive, $exactmatch) = @_;

    my $success = 0;
    my $searchdirective = searchstr($directive);
    $searchdirective .= ".*" if (!$exactmatch);
    ($_ =~ s/^\s*($searchdirective)$/\#$1/ and $success = 1)
	foreach @{$lines_ptr};
    return $success;
}

sub replace_directive {

    # Replace a directive, if it appears more than once, remove
    # the additional occurences.

    my ($lines_ptr, $olddirective, $newdirective) = @_;

    my $success = 0;
    $newdirective = "$newdirective\n";
    my $searcholddirective = searchstr($olddirective);
    ($_ =~ /^\s*$searcholddirective/ and $_ = $newdirective and 
     $success = 1 and $newdirective = "") foreach @{$lines_ptr};
    return $success;
}


sub move_directive_to_version_commented_out {

    # If there is a version of the directive "commentedout" which is
    # commented out, the directive "directive" will be moved in its place.

    my ($lines_ptr, $commentedout, $directive, $exactmatch) = @_;

    my $success = 0;
    my $searchcommentedout = searchstr($commentedout);
    $searchcommentedout .= ".*" if (!$exactmatch);
    ($_ =~ /^\s*\#$searchcommentedout$/ and 
     $success = 1 and last) foreach @{$lines_ptr};
    if ($success) {
	remove_directive($lines_ptr, $directive);
	($_ =~ s/^\s*\#($searchcommentedout)$/$directive/ and 
	 $success = 1 and last) foreach @{$lines_ptr};
    }
    return $success;
}

sub set_directive {

    # Set a directive, replace the old definition or a commented definition

    my ($lines_ptr, $directive, $full_line) = @_;

    my $olddirective = $directive;
    if (!$full_line) {
	$olddirective =~ s/^\s*(\S+)\s+.*$/$1/s;
	$olddirective ||= $directive;
    }

    my $success = (replace_directive($lines_ptr, $olddirective,
				     $directive) or
		   insert_directive($lines_ptr, $directive));
    if ($success) {
	move_directive_to_version_commented_out($lines_ptr, $directive, 
						$directive, 1);
    }
    return $success;
}

sub add_directive {

    # Add a directive, replace a commented definition

    my ($lines_ptr, $directive) = @_;

    my $success = insert_directive($lines_ptr, $directive);
    if ($success) {
	move_directive_to_version_commented_out($lines_ptr, $directive, 
						$directive, 1);
    }
    return $success;
}

1;
