package handle_configs;

# $Id$

use diagnostics;
use strict;

use common;

sub read_directives {

    # Read one or more occurences of a directive

    my ($lines_ptr, $directive) = @_;

    my @result = ();
    my $searchdirective = $directive;
    $searchdirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
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
	my $value = @d[$#d];
	set_directive($lines_ptr, "$directive $value");
	return $value;
    } else {
        return $default;
    }
}

sub insert_directive {

    # Insert a directive only if it is not already there

    my ($lines_ptr, $directive) = @_;

    my $searchdirective = $directive;
    $searchdirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
    ($_ =~ /^\s*$searchdirective$/ and return 0) foreach @{$lines_ptr};
    splice(@{$lines_ptr}, -1, 0, "$directive\n");
    return 1;
}

sub remove_directive {

    # Remove a directive

    my ($lines_ptr, $directive) = @_;

    my $success = 0;
    my $searchdirective = $directive;
    $searchdirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
    ($_ =~ /^\s*$searchdirective/ and $_ = "" and $success = 1)
	foreach @{$lines_ptr};
    return $success;
}

sub comment_directive {

    # Comment out a directive

    my ($lines_ptr, $directive) = @_;

    my $success = 0;
    my $searchdirective = $directive;
    $searchdirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
    ($_ =~ s/^(\s*$searchdirective)/\#$1/ and $success = 1)
	foreach @{$lines_ptr};
    return $success;
}

sub replace_directive {

    # Replace a directive, if it appears more than once, remove
    # the additional occurences.

    my ($lines_ptr, $olddirective, $newdirective) = @_;

    my $success = 0;
    $newdirective = "$newdirective\n";
    my $searcholddirective = $olddirective;
    $searcholddirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
    ($_ =~ /^\s*$searcholddirective/ and $_ = $newdirective and 
     $success = 1 and $newdirective = "") foreach @{$lines_ptr};
    return $success;
}


sub move_directive_to_version_commented_out {

    # If there is a version of the directive "commentedout" which is
    # commented out, the directive "directive" will be moved in its place.

    my ($lines_ptr, $commentedout, $directive, $exactmatch) = @_;

    my $success = 0;
    my $searchcommentedout = $commentedout;
    $searchcommentedout =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
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

    # Set a directive in the cupsd.conf, replace the old definition or
    # a commented definition

    my ($lines_ptr, $directive) = @_;

    my $searchdirective = $directive;
    $searchdirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
    my $olddirective = $searchdirective;
    $olddirective =~ s/^\s*(\S+)\s+.*$/$1/s;

    my $success = (replace_directive($lines_ptr, $olddirective,
				     $directive) or
		   insert_directive($lines_ptr, $directive));
    if ($success) {
	move_directive_to_version_commented_out($lines_ptr, 
						"$directive\$", 
						$directive) or
	move_directive_to_version_commented_out($lines_ptr, 
						$olddirective, $directive);
    }
    return $success;
}

sub add_directive {

    # Set a directive in the cupsd.conf, replace the old definition or
    # a commented definition

    my ($lines_ptr, $directive) = @_;

    my $searchdirective = $directive;
    $searchdirective =~ s/([\\\/\(\)\[\]\|\.\$\@\%\*\?])/\\$1/g;
    my $olddirective = $searchdirective;
    $olddirective =~ s/^\s*(\S+)\s+.*$/$1/s;

    my $success = insert_directive($lines_ptr, $directive);
    if ($success) {
	move_directive_to_version_commented_out($lines_ptr, $directive, 
						$directive, 1) or
	move_directive_to_version_commented_out($lines_ptr, 
						$olddirective, $directive);
    }
    return $success;
}

1;
