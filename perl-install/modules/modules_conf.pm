package modules::modules_conf;

use log;
use common;

our @ISA = qw(modules::any_conf);

sub get_above {
    my ($conf, $name) = @_;
    $conf->{$name} && $conf->{$name}{above};
}
sub set_above {
    my ($conf, $name, $modules) = @_;
    $conf->{$name}{above} = $modules;
}
sub remove_above {
    my ($conf, $name) = @_;
    delete $conf->{$name}{above};
}

sub get_probeall {
    my ($conf, $alias) = @_;
    $conf->{$alias}{probeall};
}
sub add_probeall {
    my ($conf, $alias, $module) = @_;

    my $l = $conf->{$alias}{probeall} ||= [];
    @$l = uniq(@$l, $module);
    log::l("setting probeall $alias to @$l");
}
sub remove_probeall {
    my ($conf, $alias, $module) = @_;

    my $l = $conf->{$alias}{probeall} ||= [];
    @$l = grep { $_ ne $module } @$l;
    log::l("setting probeall $alias to @$l");
}

1;
