package dbus_object;

sub system_bus {
    my %params = @_;
    #- use nomainloop => 1 to disable Net::DBus::Reactor main loop
    require Net::DBus;
    Net::DBus->system(%params);
}

sub new {
    my ($type, $bus, $service, $path, $interface) = @_;
    my $o = {
	bus => $bus,
	service => $service,
	path => $path,
	interface => $interface,
    };
    attach_object($o);
    bless $o, $type;
}

sub attach_object {
    my ($o) = @_;
    my $service = $o->{bus}->get_service($o->{service});
    $o->{object} = $service->get_object($o->{path}, $o->{interface});
}

sub call_method {
    my ($o, $method, @args) = @_;
    $o->{object}->$method(@args);
}

sub safe_call_method {
    my ($o, $method, @args) = @_;
    my @ret;
    eval {
        @ret = $o->call_method($method, @args);
    };
    if ($@) {
        print STDERR "($method) exception: $@\n";
        $o->{bus}{connection}->dispatch;
        return;
    }
    @ret;
}

sub set_gtk2_watch {
    my ($o) = @_;
    set_gtk2_watch_helper($o->{bus});
}

sub set_gtk2_watch_helper {
    my ($bus) = @_;
    $bus->{connection}->set_watch_callbacks(sub {
        my ($con, $watch) = @_;
        my $flags = $watch->get_flags;
        require Net::DBus::Binding::Watch;
	require Gtk2::Helper;
        if ($flags & &Net::DBus::Binding::Watch::READABLE) {
            Gtk2::Helper->add_watch($watch->get_fileno, 'in', sub {
                $watch->handle(&Net::DBus::Binding::Watch::READABLE);
                $con->dispatch;
                1;
            });
        }
        #- do nothing for WRITABLE watch, we dispatch when needed
    }, undef, undef); #- do nothing when watch is disabled or toggled yet

    $bus->{connection}->dispatch;
}

1;
