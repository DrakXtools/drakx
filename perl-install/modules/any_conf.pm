package modules::any_conf;

use log;
use common;


sub vnew {
    if (c::kernel_version() =~ /^\Q2.6/) {
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

sub get_probeall {
    my ($conf, $alias) = @_;
    $conf->{$alias}{probeall};
}
sub set_probeall {
    my ($conf, $alias, $modules) = @_;
    $conf->{$alias}{probeall} = $modules;
    log::l("setting probeall $alias to $modules");
}
sub add_probeall {
    my ($conf, $alias, $module) = @_;
    my $modules = join(' ', uniq(split(' ', $conf->{$alias}{probeall}), $module));
    set_probeall($conf, $alias, $modules);
}
sub remove_probeall {
    my ($conf, $alias, $module) = @_;
    my $modules = join(' ', grep { $_ ne $module } split(' ', $conf->{$alias}{probeall}));
    set_probeall($conf, $alias, $modules);
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
	$conf->set_above($old, undef);
    }
    $conf->set_alias($alias, $module);
    $conf->set_above($module, 'snd-pcm-oss') if $module =~ /^snd-/;
}


sub read {
    my ($type, $o_file) = @_;

    my $conf = modules::any_conf::vnew();
    my $raw_conf = modules::any_conf::read_raw($o_file || $::prefix . $conf->file);

    foreach my $module (keys %$raw_conf) {
	my $raw = $raw_conf->{$module};
	my $keep = $conf->{$module} = {};
	foreach ($conf->handled_fields) {
	    $keep->{$_} = $raw->{$_} if $raw->{$_};
	}
    }

    $conf;
}

sub write {
    my ($conf, $o_file) = @_;
    my $file = $o_file || $::prefix . $conf->file;

    my %written;

    #- Substitute new config (if config has changed)
    substInFile {
	my ($type, $module, $val) = split(' ', chomp_($_), 3);
	if ($type eq 'post-install' && $module eq 'supermount') {	    
	    #- remove the post-install supermount stuff.
	    $_ = '';
	} elsif (member($type, $conf->handled_fields)) {
	    my $new_val = $conf->{$module}{$type};
	    if (!$new_val) {
		$_ = '';
	    } elsif ($new_val ne $val) {
		$_ = "$type $module $new_val\n";
	    }
	}
	$written{$module}{$type} = 1;
    } $file;

    my $to_add;
    while (my ($module, $h) = each %$conf) {
	while (my ($type, $v) = each %$h) {
	    $to_add .= "$type $module $v\n" if $v && !$written{$module}{$type};
	}
    }
    append_to_file($file, $to_add);

    modules::write_preload_conf($conf);
}




################################################################################
sub read_raw {
    my ($file) = @_;
    my %c;

    foreach (cat_($file)) {
	next if /^\s*#/;
	s/#.*$//;
	s/\s+$//;

	s/\b(snd-card-)/snd-/g;
	s/\b(snd-via686|snd-via8233)\b/snd-via82xx/g;

	my ($type, $module, $val) = split(' ', $_, 3) or next;

	$c{$module}{$type} = $val;
    }

    #- NB: not copying alias options to the module anymore, hopefully not useful :)

    \%c;
}

1;
