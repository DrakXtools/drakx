package Xconfig::xfree; # $Id$

use diagnostics;
use strict;

use common;
use Xconfig::parse;
use Xconfig::xfree3;
use Xconfig::xfree4;
use log;


#- files are optional
sub read {
    my ($class, $xfree3_file, $xfree4_file) = @_;
    bless { xfree3 => eval { Xconfig::xfree3->read($xfree3_file) } || [], 
	    xfree4 => eval { Xconfig::xfree4->read($xfree4_file) } || [] }, $class;
}
#- files are optional
sub write {
    my ($both, $xfree3_file, $xfree4_file) = @_;
    $both->{xfree3} ? $both->{xfree3}->write($xfree3_file) : unlink($xfree3_file);
    $both->{xfree4} ? $both->{xfree4}->write($xfree4_file) : unlink($xfree4_file);
}

sub empty_config {
    my ($class) = @_;
    bless { xfree3 => Xconfig::xfree3->empty_config, 
	    xfree4 => Xconfig::xfree4->empty_config }, $class;
}

sub get_keyboard { get_both('get_keyboard', @_) }
sub set_keyboard { set_both('set_keyboard', @_) }
sub get_mice     { get_both('get_mice', @_) }
sub set_mice     { set_both('set_mice', @_) }

sub get_resolution { get_both('get_resolution', @_) }
sub set_resolution { set_both('set_resolution', @_) }

sub get_device   { get_both('get_device', @_) }
sub get_devices  { get_both('get_devices', @_) }
sub set_devices  { set_both('set_devices', @_) }

sub set_wacoms { set_both('set_wacoms', @_) }

sub get_monitor  { get_both('get_monitor', @_) }
sub get_monitors { get_both('get_monitors', @_) }
sub set_monitors { set_both('set_monitors', @_) }

sub is_fbdev { get_both('is_fbdev', @_) }

#-##############################################################################
#- helpers
#-##############################################################################
sub get_both {
    my ($getter, $both) = @_;

    if (is_empty_array_ref($both->{xfree3})) {
	$both->{xfree3}->$getter;
    } elsif (is_empty_array_ref($both->{xfree4})) {
	$both->{xfree3}->$getter;
    } else {
	my @l3 = $both->{xfree3}->$getter;
	my @l4 = $both->{xfree4}->$getter;
	merge_values(\@l3, \@l4);
    }
}
sub set_both {
    my ($setter, $both, @l) = @_;

    $both->{xfree3}->$setter(@l) if !is_empty_array_ref($both->{xfree3});
    $both->{xfree4}->$setter(@l) if !is_empty_array_ref($both->{xfree4});
}

sub merge_values {
    my ($l3, $l4) = @_;

    sub merge_values__hashes {
	my ($h3, $h4) = @_;
	$h3 || $h4 or return;
	$h3 or return $h4;
	$h4 or return $h3;

	my %h = %$h4;
	foreach (keys %$h3) {
	    if (exists $h{$_}) {
		if (ref($h{$_}) eq 'HASH' && ref($h3->{$_}) eq 'HASH') {
		    #- needed for "Options" of Devices
		    $h{$_} = +{ %{$h3->{$_}}, %{$h{$_}} };
		} else {
		    my $s4  = join(", ", deref_array($h{$_}));
		    my $s3  = join(", ", deref_array($h3->{$_}));
		    my $s3_ = join(", ", map { qq("$_") } deref_array($h3->{$_}));
		    if ($s4 eq $s3_) {
			#- keeping the non-double-quoted value
			$h{$_} = $h3->{$_};
		    } else {
			$s4 eq $s3 or log::l(qq(XFree: conflicting value for $_, "$s4" and "$s3" are different));
		    }
		}
	    } else {
		$h{$_} = $h3->{$_};
	    }
	}
	\%h;
    }

    my @r = mapn(\&merge_values__hashes, $l3, $l4);

    @r == 1 ? $r[0] : @r;
}

1;
