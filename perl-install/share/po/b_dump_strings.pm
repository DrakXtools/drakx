package b_dump_strings;

use B qw(minus_c save_BEGINs peekop class walkoptree walkoptree_exec
         main_start main_root cstring sv_undef);

BEGIN { open OUT, ">$ENV{OUTFILE}" }

sub B::CV::debug {
    my ($sv) = @_;
    B::walkoptree_exec($sv->START, "debug");
}

sub B::OP::debug {
    my ($op) = @_;
#    print "OP ", class($op), " ", $op->name, "\n";
    eval {
	if ($op->name eq 'entersub') {
	    $op2 = $op->first->first or return;

	    if ($op2->name eq 'pushmark') {
		my $s = $op2->sibling->sv->PV;
		my $l;
		for ($l = $op2->sibling; ${$l->sibling}; $l = $l->sibling) {}

		$s =~ s/"/\\"/g;
		if ($l->first->sv->NAME eq '_') {
		    print OUT qq($::pkg N("$s")\n);
		}
	    }
	}
    };
}
sub B::RV::debug {
    my ($op) = @_;
    $op->RV->debug;
}
sub B::SVOP::debug {
    my ($op) = @_;
    $op->sv->debug;
}
sub B::PV::debug {
    my ($sv) = @_;
#    print "STRING ", $sv->PV, "\n";
}
sub B::IV::debug {
    my ($sv) = @_;
#    printf "IV\t%d\n", $sv->IV;
}
sub B::NV::debug {
    my ($sv) = @_;
#    printf "NV\t%s\n", $sv->NV;
}
sub B::PVIV::debug {
    my ($sv) = @_;
#    printf "IV\t%d\n", $sv->IV;
}
sub B::PVNV::debug {
    my ($sv) = @_;
#    printf "NV\t%s\n", $sv->NV;
}
sub B::AV::debug {
    my ($av) = @_;
#    print "ARRAY\n";
}
sub B::GV::debug {
    my ($gv) = @_;
#    printf "GV %s::%s\n", $gv->STASH->NAME, $gv->SAFENAME;
}
sub B::NULL::debug { 
#    print "NUL\n";
}
sub B::SPECIAL::debug {}

sub B::SV::debug { die "SV"; }
sub B::BM::debug { 
    die "BM"; 
}
sub B::PVLV::debug { die "PVLV"; }

sub B::GV::pgv {
    my ($gv) = @_;
#    print $gv->NAME, "\n";
    $gv->SV->debug;
    $gv->HV->debug;
    $gv->AV->debug;
    $gv->CV->debug;
}




sub search {

foreach my $pkg (grep { /^[a-z]/ && !/^(diagnostics|strict|attributes|main)/ } grep { /\w+::$/ } keys %main::) {
    $::pkg = $pkg;
    foreach (keys %{$main::{$pkg}}) {
	print STDERR "$pkg $_ XXXXX\n";
	local *f = *{$main::{$pkg}{$_}};
	B::svref_2object(\*f)->pgv;
    }
}
print STDERR "DONE\n";
}

CHECK { search() }
INIT { exit 0 }

#use lib qw(. /home/pixel/gi/perl-install);
##use commands;
#require '/tmp/t.pl';
#search();

1;
