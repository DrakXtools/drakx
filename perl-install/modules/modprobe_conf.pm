package modules::modprobe_conf;

use log;
use common;

our @ISA = qw(modules::any_conf);


sub get_above {
    my ($conf, $name) = @_;
    after_modules($name, $conf->{$name}{install});
}
sub set_above {
    my ($conf, $name, $modules) = @_;
    #TODO
}

sub get_probeall {
    my ($conf, $alias) = @_;
    #TODO
}
sub add_probeall {
    my ($conf, $alias, $module) = @_;

    #TODO
    my $l = $conf->{$alias}{probeall} ||= [];
    @$l = uniq(@$l, $module);
    log::l("setting probeall $alias to @$l");
}
sub remove_probeall {
    my ($conf, $alias, $module) = @_;

    #TODO
    my $l = $conf->{$alias}{probeall} ||= [];
    @$l = grep { $_ ne $module } @$l;
    log::l("setting probeall $alias to @$l");
}



################################################################################
sub remove_braces {
    my ($s) = @_;
    $s =~ s/^\s*\{\s*(.*)\s*;\s*\}\s*$/$1/;
    $s;
}

sub non_virtual {
    my ($module, $s) = @_;
    my ($before, $options, $after) = 
      $s =~ m!^(?:(.*);)?
              \s*(?:/sbin/)?modprobe\s+(-\S+\s+)*\Q$module\E
              \s*(?:&&\s*(.*))?$!x 
		or return;
    $options =~ /--ignore-(install|remove)\b/ or return;

    ($before, $after) = map { remove_braces($_ || '') } $before, $after;
    $after =~ s!\s*;\s*/bin/true$!!;

    $before, $after;
}

sub after_modules {
    my ($module, $s) = @_;
    my (undef, $after) = non_virtual($module, $s) or return;
    
}

sub probeall {
    my ($module, $s) = @_;

    non_virtual($module, $s) and return;
    if ($s =~ /[{&|]/) {
	log::l("weird install line in modprobe.conf for $module: $s");
	return;
    }
    $s ne '/bin/true' or return; #- we have "alias $module off" here

    $s =~ s!\s*;\s*/bin/true$!!;

    my @l = split(/\s*;\s*/, $s);

    [ map {
	if (m!^(?:/sbin/)?modprobe\s+(\S+)$!) {
	    $1
	} else {
	    log::l("weird probeall string $_ (from install $module $s)");
	    ();
	}
    } @l ];
}

sub parse {
    my ($type, $module, $s) = @_;

    member($type, 'install', 'remove') or return;

    if (my ($before, $after) = non_virtual($module, $s)) {
	[
	 if_($after, [ "post-$type", $after ]),
	 if_($before, [ "pre-$type", $before ]),
	];	  
    } elsif (my $l = probeall($module, $s)) {
	[ [ 'probeall', @$l ] ];
    }
}

1;
