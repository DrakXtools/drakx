package modules::any_conf;

use log;
use common;


sub vnew {
    if (0 && c::kernel_version() =~ /^\Q2.6/) {
	require modules::modprobe_conf;
	modules::modprobe_conf->new;
    } else {
	require modules::modules_conf;
	modules::modules_conf->new;
    }    
}


sub new {
    my ($type) = @_;
    bless {}, ref($type) || $type;
}

sub read {
    my ($_type, $o_file) = @_;

    my $conf = vnew();
    my $raw_conf = modules::read_conf($o_file || "$::prefix/etc/modules.conf");
    foreach my $key (keys %$raw_conf) {
	my $raw = $raw_conf->{$key};
	my $keep = $conf->{$key} = {};
	$keep->{alias} ||= $raw->{alias};
	$keep->{above} ||= $raw->{above};
	$keep->{options} = $raw->{options} if $raw->{options};
	push @{$keep->{probeall} ||= []}, deref($raw->{probeall}) if $raw->{probeall};
    }
    $conf;
}

sub write {
    my ($conf) = @_;
    modules::write_conf($conf);
}

sub modules {
    my ($conf) = @_;
    keys %$conf;
}

sub get_alias {
    my ($conf, $alias) = @_;
    $conf->{$alias}{alias};
}
sub get_options {
    my ($conf, $name) = @_;
    $conf->{$name}{options};
}
sub set_options {
    my ($conf, $name, $new_option) = @_;
    log::l(qq(set option "$new_option" for module "$name"));
    $conf->{$name}{options} = $new_option;
}
sub get_parameters {
    my ($conf, $name) = @_;
    map { if_(/(.*)=(.*)/, $1 => $2) } split(' ', $conf->get_options($name));
}


sub set_alias { 
    my ($conf, $alias, $module) = @_;
    $module =~ /ignore/ and return;
    /\Q$alias/ && $conf->{$_}{alias} && $conf->{$_}{alias} eq $module and return $_ foreach keys %$conf;
    log::l("adding alias $alias to $module");
    $conf->{$alias}{alias} = $module;
    $alias;
}


sub remove_alias {
    my ($conf, $name) = @_;
    log::l(qq(removing alias "$name"));
    $conf->remove_alias_regexp("^$name\$");
}

sub remove_alias_regexp {
    my ($conf, $aliased) = @_;
    log::l(qq(removing all aliases that match "$aliased"));
    foreach (keys %$conf) {
        delete $conf->{$_}{alias} if /$aliased/;
    }
}

sub remove_alias_regexp_byname {
    my ($conf, $name) = @_;
    log::l(qq(removing all aliases which names match "$name"));
    foreach (keys %$conf) {
        delete $conf->{$_} if /$name/;
    }
}

sub remove_module {
    my ($conf, $name) = @_;
    $conf->remove_alias($name);
    log::l("removing module $name");
    delete $conf->{$name};
    0;
}

sub set_sound_slot {
    my ($conf, $alias, $module) = @_;
    if (my $old = $conf->get_alias($alias)) {
	$conf->remove_above($old);
    }
    $conf->set_alias($alias, $module);
    $conf->set_above($module, 'snd-pcm-oss') if $module =~ /^snd-/;
}

1;
