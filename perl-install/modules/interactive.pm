package modules::interactive;
use interactive;
use common;

sub config_window {
    my ($in, $data) = @_;
    require modules;
    modules::mergein_conf('/etc/modules.conf');
    my %conf = modules::get_parameters($data->{driver});
    require modparm;
    my @l;
    foreach (modparm::parameters($data->{driver})) {
	   my ($name, $format, $description) = @$_;
	   push @l, { label => $name, help => "$description\n[$format]", val => \$conf{$name} };
    }
    if ($in->ask_from("Module configuration", _("You can configure each parameter of the module here."), \@l)) {
	   my $options = join(' ', map { if_($conf{$_}, "$_=$conf{$_}") } keys %conf);
	   if ($options) {
		  modules::set_options($_->{driver}, $options);
		    modules::write_conf;
		}
    }
}

1;
