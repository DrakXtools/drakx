package modules::modules_conf;

use log;
use common;

our @ISA = qw(modules::any_conf);


sub file { '/etc/modules.conf' }
sub handled_fields { qw(alias above options probeall) }

sub get_above {
    my ($conf, $module) = @_;
    $conf->{$module} && $conf->{$module}{above};
}
sub set_above {
    my ($conf, $module, $o_modules) = @_;
    if ($o_modules) {
	$conf->{$module}{above} = $o_modules;
    } else {
	delete $conf->{$module}{above};
    }
}

sub read {
    my ($type, $o_file) = @_;

    my $conf = modules::any_conf::read($type, $o_file);

    #- convert old aliases to new probeall
    foreach my $name ('scsi_hostadapter', 'usb-interface') {
	my @old_aliases = 
	  map { $_->[0] } sort { $a->[1] <=> $b->[1] } 
	  map { if_(/^$name(\d*)/ && $conf->{$_}{alias}, [ $_, $1 || 0 ]) } keys %$conf;
	foreach my $alias (@old_aliases) {
	    $conf->add_probeall($name, delete $conf->{$alias}{alias});
	}
    }

    $conf;
}

sub write {
    my ($conf, $o_file) = @_;
    my $file = $o_file || do {
	my $f = $::prefix . file();
	rename "$::prefix/etc/conf.modules", $f; #- make the switch to new name if needed
	$f;
    };

    modules::any_conf::write($conf, $file);
}

1;
