package Xconfig::xfree; # $Id$

use diagnostics;
use strict;

use MDK::Common;
use Xconfig::parse;
use Xconfig::xfree3;
use Xconfig::xfree4;
use log;


sub read {
    my ($class) = @_;
    bless { xfree3 => Xconfig::xfree3->read, 
	    xfree4 => Xconfig::xfree4->read }, $class;
}
sub write {
    my ($both) = @_;
    $both->{xfree3}->write;
    $both->{xfree4}->write;
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




#-##############################################################################
#- helpers
#-##############################################################################
sub get_both {
    my ($getter, $both) = @_;

    my @l3 = $both->{xfree3}->$getter;
    my @l4 = $both->{xfree4}->$getter;
    mapn {
	my ($h3, $h4) = @_;
	my %h = %$h4;
	foreach (keys %$h3) {
	    if (exists $h{$_}) { 
		my $s4  = join(", ", deref_array($h{$_}));
		my $s3  = join(", ", deref_array($h3->{$_}));
		my $s3_ = join(", ", map { qq("$_") } deref_array($h3->{$_}));
		if ($s4 eq $s3_) {
		    #- keeping the non-double-quoted value
		    $h{$_} = $h3->{$_};
		} else {
		    $s4 eq $s3 or log::l(qq(XFree: conflicting value for $_, "$s4" and "$s3" are different));
		}
	    } else {
		$h{$_} = $h3->{$_};
	    }
	}
	\%h;
    } \@l3, \@l4;
}
sub set_both {
    my ($setter, $both, @l) = @_;

    $both->{xfree3}->$setter(@l);
    $both->{xfree4}->$setter(@l);
}



1;
