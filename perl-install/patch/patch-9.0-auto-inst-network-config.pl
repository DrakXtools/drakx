package install_steps;
log::l("fixing network module probe & configuration in interactive auto_install");
my $old_configureNetwork = \&configureNetwork;
undef *configureNetwork;
*configureNetwork = sub {
    modules::load_category('network/main|usb');
    &$old_configureNetwork;
};
