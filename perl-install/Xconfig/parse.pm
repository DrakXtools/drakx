package Xconfig::parse; # $Id$

use diagnostics;
use strict;

use common;


sub read_XF86Config {
    my ($file) = @_;
    my $raw_X = raw_from_file($file);
    from_raw(@$raw_X);
    $raw_X;
}

sub write_XF86Config {
    my ($raw_X, $file) = @_;
    my @blocks = map { raw_to_string(before_to_string({ %$_ }, 0)) } @$raw_X;
    @blocks ? output($file, @blocks) : unlink $file;
}

sub read_XF86Config_from_string {
    my ($s) = @_;
    my $raw_X = raw_from_file('-', [ split "\n", $s ]);
    from_raw(@$raw_X);
    $raw_X;
}

#-###############################################################################
#- raw reading/saving
#-###############################################################################
sub raw_from_file { #- internal
    my ($file, $lines) = @_;
    my $raw_X = [];

    $lines ||= [ cat_($file) ];
    my $line;
    my $weird = sub { warn "$file:$line: strange $_[0]" };

    my ($comment, $obj, @objs);

    my $attach_comment = sub {
	$obj || @objs or warn "$file:$line: can't attach comment\n";
	if ($comment) {
	    $comment =~ s/\n+$/\n/;
	    ($obj || $objs[0])->{$_[0] . '_comment'} = $comment;
	    $comment = '';
	}
    };

    foreach (@$lines) {
	$line++;
	s/^\s*//; s/\s*$//;

	if (/^$/) {
	    $comment .= "\n" if $comment;
	    next;
	} elsif (/^#\W/ || /^#$/) {
	    s/^#\s+/# /;
	    $comment .= "$_\n";
	    next;
	}

	if (/^Section\s+"(.*)"/i) {
	    die "$file:$line: missing EndSection\n" if @objs;
	    my $e = { name => $1, l => [], kind => 'Section' };
	    push @$raw_X, $e;
	    unshift @objs, $e; $obj = '';
	    $attach_comment->('pre');
	} elsif (/^Subsection\s+"(.*)"/i) {
	    die "$file:$line: missing EndSubsection\n" if  @objs && $objs[0]{kind} eq 'Subsection';
	    die "$file:$line: not in Section\n"        if !@objs || $objs[0]{kind} ne 'Section';
	    my $e = { name => $1, l => [], kind => 'Subsection' };
	    push @{$objs[0]{l}}, $e;
	    unshift @objs, $e; $obj = '';
	    $attach_comment->('pre');
	} elsif (/^EndSection/i) {
	    die "$file:$line: not in Section\n"        if !@objs || $objs[0]{kind} ne 'Section';
	    $attach_comment->('post');
	    shift @objs; $obj = '';
	} elsif (/^EndSubsection/i) {
	    die "$file:$line: not in Subsection\n"     if !@objs || $objs[0]{kind} ne 'Subsection';
	    $attach_comment->('post');
	    my $e = shift @objs; $obj = '';
	} else {
	    die "$file:$line: not in Section\n" if !@objs;

	    my $commented = s/^#//;

	    my $comment_on_line;
	    s/(\s*#.*)/$comment_on_line = $1; ''/e;

	    if (/^$/) {
		die "$file:$line: weird";
	    }

	    (my $name, my $Option, $_)  = 
 	      /^Option\s*"(.*?)"(.*)/ ? ($1, 1, $2) : /^(\S+)(.*)/ ? ($1, 0, $2) : internal_error($_);
	    my ($val) = /(\S.*)/;

	    my %e = (Option => $Option, commented => $commented, comment_on_line => $comment_on_line, pre_comment => $comment);
	    $comment = '';
	    $obj = { name => $name, val => $val };
	    $e{$_} and $obj->{$_} = $e{$_} foreach keys %e;

	    push @{$objs[0]{l}}, $obj;
	}
    }
    $raw_X;
}

sub raw_to_string {
    my ($e, $want_spacing) = @_;
    my $s = do {
	if ($e->{l}) {
	    my $inside = join('', map_index { raw_to_string($_, $::i) } @{$e->{l}});
	    $inside =~ s/^/    /mg;
	    qq(\n$e->{kind} "$e->{name}"\n) . $inside . "End$e->{kind}";
	} else {
	    ($e->{commented} ? '#' : '') .
	      ($e->{Option} ? qq(Option "$e->{name}") : $e->{name}) .
	      (defined $e->{val} ? ($e->{Option} && $e->{val} !~ /^"/ ? qq( "$e->{val}") : qq( $e->{val})) : '');
	}
    };
    ($e->{pre_comment} ? ($want_spacing ? "\n" : '') . $e->{pre_comment} : '') . $s . ($e->{comment_on_line} || '') . "\n" . ($e->{post_comment} || '');
}

#-###############################################################################
#- refine the data structure for easier use
#-###############################################################################
my %kind_names = (
    Pointer  => [ qw(Protocol Device Emulate3Buttons Emulate3Timeout) ],
    Mouse    => [ qw(DeviceName Protocol Device AlwaysCore Emulate3Buttons Emulate3Timeout) ], # Subsection in XInput
    Keyboard => [ qw(Protocol Driver XkbModel XkbLayout XkbDisable) ],
    Monitor  => [ qw(Identifier VendorName ModelName HorizSync VertRefresh) ],
    Device   => [ qw(Identifier VendorName BoardName Chipset Driver VideoRam Screen BusID DPMS power_saver) ],
    Display  => [ qw(Depth Modes) ], # Subsection in Device
    Screen   => [ qw(Identifier Driver Device Monitor DefaultColorDepth) ],
    InputDevice => [ qw(Identifier Driver Protocol Device Type Mode XkbModel XkbLayout XkbDisable Emulate3Buttons Emulate3Timeout) ],
    ServerLayout => [ qw(Identifier) ],
);
my @want_string = qw(Identifier DeviceName VendorName ModelName BoardName Driver Device Chipset Monitor Protocol XkbModel XkbLayout Load BusID);

%kind_names = map_each { lc $::a => [ map { lc } @$::b ] } %kind_names;
@want_string = map { lc } @want_string;

sub from_raw {
    foreach my $e (@_) {
	($e->{l}, my $l) = ({}, $e->{l});
	from_raw__rec($e, $_) foreach @$l;

	delete $e->{kind};
    }

    sub from_raw__rec {
	my ($current, $e) = @_;
	if ($e->{l}) {
	    from_raw($e);
	    push @{$current->{l}{$e->{name}}}, $e;
	} else {
	    if (member(lc $e->{name}, @want_string)) {
		$e->{val} =~ s/^"(.*)"$/$1/ or warn "$e->{name} $e->{val} has no quote\n";
	    }

	    if (member(lc $e->{name}, @{$kind_names{lc $current->{name}} || []})) {
		if ($current->{l}{$e->{name}} && !$current->{l}{$e->{name}}{commented}) {
		    warn "skipping conflicting line for $e->{name} in $current->{name}\n" if !$e->{commented};
		} else {
		    $current->{l}{$e->{name}} = $e;
		}
	    } else {
		push @{$current->{l}{$e->{name}}}, $e;
	    }
	}
	delete $e->{name};
    }
}

sub before_to_string {
    my ($e, $depth) = @_;

    if ($e->{l}) {
	$e->{kind} = $depth ? 'Subsection' : 'Section';

	my %rated = map_index { $_ => $::i + 1 } @{$kind_names{lc $e->{name}} || []};
	my @sorted = sort { ($rated{lc $a} || 99) <=> ($rated{lc $b} || 99) } keys %{$e->{l}};
	$e->{l} = [ map {		  
	    my $name = $_;
	    map { 
		before_to_string({ name => $name, %$_ }, $depth+1);
	    } deref_array($e->{l}{$name});
	} @sorted ];
    } elsif (member(lc $e->{name}, @want_string)) {
	$e->{val} = qq("$e->{val}");
    }
    $e;
}
