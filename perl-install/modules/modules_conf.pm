package modules::modules_conf; # $Id$

use log;
use common;

our @ISA = qw(modules::any_conf);


sub file { '/etc/modules.conf' }
sub handled_fields { qw(alias above options probeall) }

sub mapping {
    my ($_conf, @modules) = @_;
    my @l = map { modules::mapping_26_24($_) } @modules;
    wantarray() ? @l : $l[0];
}

sub get_above {
    my ($conf, $module) = @_;
    $module = $conf->mapping($module);

    $conf->{$module} && split(' ', $conf->{$module}{above});
}
sub set_above {
    my ($conf, $module, $o_modules) = @_;
    $module = $conf->mapping($module);

    if ($o_modules) {
	my $modules = join(' ', $conf->mapping(split(' ', $o_modules)));
	$conf->{$module}{above} = $modules;
    } else {
	delete $conf->{$module}{above};
    }
}

sub read {
    my ($type, $o_file) = @_;

    my $conf = modules::any_conf::read_handled($type, $o_file);

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

    if ($::isInstall) {
	require modules::modprobe_conf;
	modules::modprobe_conf::create_from_old();
    }
}

1;
