package modules::interactive;
use interactive;
use modules;
use common;

sub config_window {
    my ($in, $data) = @_;
    require modules;
    modules::mergein_conf('/etc/modules.conf');
    my %conf = modules::get_parameters($data->{driver});
    require modules::parameters;
    my @l;
    foreach (modules::parameters::parameters($data->{driver})) {
	   my ($name, $format, $description) = @$_;
	   push @l, { label => $name, help => "$description\n[$format]", val => \$conf{$name} };
    }
    if ($in->ask_from("Module configuration", N("You can configure each parameter of the module here."), \@l)) {
	   my $options = join(' ', map { if_($conf{$_}, "$_=$conf{$_}") } keys %conf);
	   if ($options) {
		  modules::set_options($data->{driver}, $options);
		    modules::write_conf;
		}
    }
}

sub load_category {
    my ($in, $category, $auto, $at_least_one) = @_;

    my @l;
    {
	my $w;
	my $wait_message = sub { $w = wait_load_module($in, $category, @_) };
	@l = modules::load_category($category, $wait_message);
	@l = modules::load_category($category, $wait_message, 'force') if !@l && $at_least_one;
    }
    if (my @err = grep { $_ } map { $_->{error} } @l) {
	$in->ask_warn('', join("\n", @err));
    }
    return @l if $auto && (@l || !$at_least_one);

    @l = map { $_->{description} } @l;

    if ($at_least_one && !@l) {
	@l = load_category__prompt($in, $category) or return;
    }

    load_category__prompt_for_more($in, $category, @l);
}

sub load_category__prompt_for_more {
    my ($in, $category, @l) = @_;

    (my $msg_type = $category) =~ s/\|.*//;

    while (1) {
	my $msg = @l ?
	  [ N("Found %s %s interfaces", join(", ", @l), $msg_type),
	    N("Do you have another one?") ] :
	  N("Do you have any %s interfaces?", $msg_type);

	my $opt = [ N_("Yes"), N_("No") ];
	push @$opt, N_("See hardware info") if $::expert;
	my $r = $in->ask_from_list_('', $msg, $opt, "No") or return;
	if ($r eq "No") { return @l }
	if ($r eq "Yes") {
	    push @l, load_category__prompt($in, $category) || next;
	} else {
	    $in->ask_warn('', [ detect_devices::stringlist() ]);
	}
    }
}

sub wait_load_module {
    my ($in, $category, $text, $module) = @_;
    $in->wait_message('',
		     [ 
		      #-PO: the first %s is the card type (scsi, network, sound,...)
		      #-PO: the second is the vendor+model name
		      N("Installing driver for %s card %s", $category, $text), if_($::expert, N("(module %s)", $module))
		     ]);
}

sub load_module__ask_options {
    my ($in, $module_descr, $parameters) = @_;

    my @parameters = map { [ @$_[0, 1, 2] ] } @$parameters;

    if (@parameters) {
	$in->ask_from('', 
		      N("You may now provide its options to module %s.\nNote that any address should be entered with the prefix 0x like '0x123'", $module_descr), 
		      [ map { { label => $_->[0] . ($_->[1] ? " ($_->[1])" : ''), help => $_->[2], val => \$_->[3] } } @parameters ],
		     ) or return;
	[ map { if_($_->[3], "$_->[0]=$_->[3]") } @parameters ];
    } else {
	my $s = $in->ask_from_entry('',
N("You may now provide options to module %s.
Options are in format ``name=value name2=value2 ...''.
For instance, ``io=0x300 irq=7''", $module_descr), N("Module options:")) or return;
	[ split ' ', $s ];
    }
}

sub load_category__prompt {
    my ($in, $category) = @_;

    (my $msg_type = $category) =~ s/\|.*//;
    my %available_modules = map_each { $::a => $::b ? "$::a ($::b)" : $::a } modules::category2modules_and_description($category);
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
properly, although it normally works fine without. Would you like to specify
extra options for it or allow the driver to probe your machine for the
information it needs? Occasionally, probing will hang a computer, but it should
not cause any damage.", $module_descr)), [ N_("Autoprobe"), N_("Specify options") ], 'Autoprobe') ne 'Autoprobe') {
	$options = load_module__ask_options($in, $module_descr, \@parameters) or return;
    }
    while (1) {
	eval {
	    my $_w = wait_load_module($in, $category, $module_descr, $module);
	    log::l("user asked for loading module $module (type $category, desc $module_descr)");
	    modules::load([ $module, @$options ]);
	};
	return $module_descr if !$@;

	$in->ask_yesorno('',
N("Loading module %s failed.
Do you want to try again with other parameters?", $module_descr), 1) or return;

	$options = load_module__ask_options($in, $module_descr, \@parameters) or return;
    }
}

1;
