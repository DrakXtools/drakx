package modules::interactive; # $Id$

use modules;
use common;

sub config_window {
    my ($in, $data) = @_;
    require modules;
    my $modules_conf = modules::any_conf->read;
    my %conf = $modules_conf->get_parameters($data->{driver});
    require modules::parameters;
    my @l;
    foreach (modules::parameters::parameters($data->{driver})) {
	   my ($name, $description) = @$_;
	   push @l, { label => $name, help => $description,
		      val => \$conf{$name}, allow_empty_list => 1 };
    }
    if (!@l) {
        $in->ask_warn(N("Error"), N("This driver has no configuration parameter!"));
        return;
    }
    if ($in->ask_from(N("Module configuration"), N("You can configure each parameter of the module here."), \@l)) {
	   my $options = join(' ', map { if_($conf{$_}, "$_=$conf{$_}") } keys %conf);
	   if ($options) {
	       $modules_conf->set_options($data->{driver}, $options);
	       $modules_conf->write;
	   }
    }
}

sub load_category {
    my ($in, $modules_conf, $category, $b_auto, $b_at_least_one) = @_;

    my @l;
    {
	my $w;
	my $wait_message = sub { undef $w; $w = wait_load_module($in, $category, @_) };
	@l = modules::load_category($modules_conf, $category, $wait_message);
	undef $w; #- help perl_checker
    }
    if (my @err = grep { $_ } map { $_->{error} } @l) {
	my $return = $in->ask_warn('', join("\n", @err));
	$in->exit(1) if !defined($return);
    }
    return @l if $b_auto && (@l || !$b_at_least_one);

    @l = map { $_->{description} } @l;

    if ($b_at_least_one && !@l) {
	@l = load_category__prompt($in, $modules_conf, $category) or return;
    }

    load_category__prompt_for_more($in, $modules_conf, $category, @l);
}

sub load_category__prompt_for_more {
    my ($in, $modules_conf, $category, @l) = @_;

    (my $msg_type = $category) =~ s/\|.*//;

    while (1) {
	my $msg = @l ?
	  [ N("Found %s interfaces", join(", ", map { qq("$_") } @l)),
	    N("Do you have another one?") ] :
	  N("Do you have any %s interfaces?", $msg_type);

	my $r = 'No';
	$in->ask_from_({ messages => $msg,
			 if_($category =~ m!disk/.*(ide|sata|scsi|hardware_raid|usb|firewire)!, interactive_help_id => 'setupSCSI'),
		       }, 
		       [ { list => [ N_("Yes"), N_("No"), N_("See hardware info") ], val => \$r, type => 'list', format => \&translate } ]);
	if ($r eq "No") { return @l }
	if ($r eq "Yes") {
	    push @l, load_category__prompt($in, $modules_conf, $category) || next;
	} else {
	    $in->ask_warn('', join("\n", detect_devices::stringlist()));
	}
    }
}

my %category2text = (
    'bus/usb' => N_("Installing driver for USB controller"),
    'bus/firewire' => N_("Installing driver for firewire controller %s"),
    'disk/ide|scsi|hardware_raid|sata|firewire' => N_("Installing driver for hard drive controller %s"),
    list_modules::ethernet_categories() => N_("Installing driver for ethernet controller %s"),
);

sub wait_load_module {
    my ($in, $category, $text, $_module) = @_;
    my $msg = do {
	if (my $t = $category2text{$category}) {
	    sprintf(translate($t), $text);
	} else {
	    #-PO: the first %s is the card type (scsi, network, sound,...)
	    #-PO: the second is the vendor+model name
	    N("Installing driver for %s card %s", $category, $text);
	}
    };
    $in->wait_message('', $msg);
}

sub load_module__ask_options {
    my ($in, $module_descr, $parameters) = @_;

    #- deep copying
    my @parameters = map { [ @$_[0, 1] ] } @$parameters;

    if (@parameters) {
	$in->ask_from('', 
		      N("You may now provide options to module %s.\nNote that any address should be entered with the prefix 0x like '0x123'", $module_descr), 
		      [ map { { label => $_->[0], help => $_->[1], val => \$_->[2] } } @parameters ],
		     ) or return;
	join(' ', map { if_($_->[2], "$_->[0]=$_->[2]") } @parameters);
    } else {
	my $s = $in->ask_from_entry('',
N("You may now provide options to module %s.
Options are in format ``name=value name2=value2 ...''.
For instance, ``io=0x300 irq=7''", $module_descr), N("Module options:")) or return;
	$s;
    }
}

sub load_category__prompt {
    my ($in, $modules_conf, $category) = @_;

    (my $msg_type = $category) =~ s/\|.*//;

    my %available_modules = map_each { my $dsc = $::b; $dsc =~ s/\s+/ /g; $::a => $dsc ? "$::a ($dsc)" : $::a } modules::category2modules_and_description($category);
    my $module = $in->ask_from_listf('',
#-PO: the %s is the driver type (scsi, network, sound,...)
			       N("Which %s driver should I try?", $msg_type),
			       sub { $available_modules{$_[0]} },
			       [ keys %available_modules ]) or return;
    my $module_descr = $available_modules{$module};

    my $options;
    require modules::parameters;
    my @parameters = modules::parameters::parameters($module);
    if (@parameters && $in->ask_from_list_('',
formatAlaTeX(N("In some cases, the %s driver needs to have extra information to work
properly, although it normally works fine without them. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $module_descr)), [ N_("Autoprobe"), N_("Specify options") ], 'Autoprobe') ne 'Autoprobe') {
	$options = load_module__ask_options($in, $module_descr, \@parameters) or return;
    }
    while (1) {
	eval {
	    my $_w = wait_load_module($in, $category, $module_descr, $module);
	    log::l("user asked for loading module $module (type $category, desc $module_descr)");
	    modules::load_and_configure($modules_conf, $module, $options);
	};
	return $module_descr if !$@;

	$in->ask_yesorno('',
N("Loading module %s failed.
Do you want to try again with other parameters?", $module_descr), 1) or return;

	$options = load_module__ask_options($in, $module_descr, \@parameters) or return;
    }
}

1;
