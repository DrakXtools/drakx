package harddrake::ui;

use strict;

require harddrake::data;
use common;
use my_gtk qw(:helpers :wrappers :various);
use interactive;


# { field => [ short_translation, full_description] }
my %fields = 
    (
     "alternative_drivers" => [ N("Alternative drivers"),
                                N("the list of alternative drivers for this sound card")],
     "bus" => 
     [ N("Bus"), 
       N("this is the physical bus on which the device is plugged (eg: PCI, USB, ...)")],
     "channel" => [N("Channel"), N("EIDE/SCSI channel")],
	 "bogomips" => [N("Bogomips"), N("The GNU/Linux kernel needs to do run a calculation loop at boot time
	 to initialize a timer counter.  Its result is stored as bogomips as a way to \"benchmark\" the cpu.")],
     "bus_id" => 
     [ N("Bus identification"), 
       N("- PCI and USB devices: this list the vendor, device, subvendor and subdevice PCI/USB ids")],
     "bus_location" => 
     [ N("Location on the bus"), 
       N("- pci devices: this gives the PCI slot, device and function of this card
- eide devices: the device is either a slave or a master device
- scsi devices: the scsi bus and the scsi device ids")],
     "cache size" => [ N("Cache size"), N("Size of the (second level) cpu cache") ],
     "coma_bug" => [ N("Coma bug:"), N("Does this cpu has Cyrix 6x86 Coma bug ?") ],
     "cpu family" => [ N("Cpuid family"), N("Family of the cpu (eg: 6 for i686 class)")],
     "cpuid level" => [ N("Cpuid level"), N("Information level that one can obtain through the cpuid instruction")],
     "cpu MHz" => [ N("Frequency (MHz)"), N("The cpu frequency in Mhz (Mega herz which in first approximation may be coarsely assimilated to number of instructions the cpu is able to execute per second)")],
     "description" => [ N("Description"), N("This field describe the device")],
     "device" => [ N("Old device file"),
                   N("old static device name used in dev package")],
     "devfs_device" => [ N("New devfs device"),  
                         N("new dinamic device name generated by incore kernel devfs")],
     "driver" => [ N("Module"), N("the module of the GNU/Linux kernel that handle that device")],
     "flags" => [ N("Flags"), N("CPU flags reported by the kernel")],
     "fdiv_bug" => [ N("Fdiv bug"), 
                     N("Early Intel Pentium chips manufactured have a bug in their floating point processor which did not achieve the attended precision when performing a Floating point DIVision (FDIV)") ],


     "fpu" => [ N("Is FPU present"), N("yes means the processor has an arithmetic coprocessor")],
     "fpu_exception" => [ N("Does FPU have an irq vector"), N("yes means the arithmetic coprocessor has an exception vector attached")],
     "f00f_bug" => [N("F00f bug"), N("Early pentium were buggy and freezed when decoding the F00F bytecode")],
     "hlt_bug" => [ N("Halt bug"), 
                    N("Some of the early i486DX-100 chips cannot reliably return to operating mode after the \"halt\" instruction is used") ],

     "info" => [N("Floppy format"), N("Format of floppies the drive accept")],
     "level" => [N("Level"), N("Sub generation of the cpu")],
     "media_type" => [ N("Media class"), N("class of hardware device")],
     "Model" => [N("Model"), N("hard disk model")],
     "model" => [N("Model"), N("Generation of the cpu (eg: 8 for PentiumIII, ...)")],
     "model name" => [N("Model name"), N("Official vendor name of the cpu")],
     "nbuttons" => [ N("Number of buttons"), "the number of buttons the mouse have"],
     "name" => [ N("Name"), "the name of the cpu"],
     "port" => [N("Port"), N("network printer port")],
     "processor" => [ N("Processor ID"), N("the number of the processor")],
     "stepping" => [ N("Model stepping"), N("Stepping of the cpu (sub model (generation) number)") ],
     "type" => [ N("Type"), N("The type of bus on which the mouse is connected")],
     "Vendor" => [ N("Vendor"), N("the vendor name of the device")],
     "vendor_id" => [ N("Vendor"), N("the vendor name of the processor")]
     );


my ($in, %IDs, $pid, $w);

my (%options, %check_boxes);
my $conffile = "/etc/sysconfig/harddrake2/ui.conf";

my ($modem_check_box, $printer_check_box,  $current_device);

my @menu_items = 
    (
     {   path => N("/_File"), type => '<Branch>' },
     {   path => N("/_File").N("/_Quit"), accelerator => N("<control>Q"), callback => \&quit_global    },
     {   path => N("/_Options").N("/Autodetect _printers"), type => '<CheckItem>',
         callback => sub { $options{PRINTERS_DETECTION} = $check_boxes{PRINTERS_DETECTION}->active } },
     {   path => N("/_Options").N("/Autodetect _modems"), type => '<CheckItem>',
         callback => sub { $options{MODEMS_DETECTION} = $check_boxes{MODEMS_DETECTION}->active } },
     {   path => N("/_Help"), type => '<Branch>' },
     {
         path => N("/_Help").N("/_Help..."), 
         callback => sub {
             if ($current_device) {
                 $in->ask_warn(N("Harddrake help"), 
                               N("Description of the fields:\n\n")
                               . join("\n\n", map { if_($fields{$_}[0], "$fields{$_}[0]: $fields{$_}[1]") } sort keys %$current_device))
                 } else {
                     $in->ask_warn(N("Select a device !"), N("Once you've selected a device, you'll be able to see explanations on fields displayed on the right frame (\"Information\")"))
                 }
             }
     },
     {   path => N("/_Help").N("/_Report Bug"),
         callback => sub { unless (fork) { exec("drakbug --report harddrake2 &") } } },
     {   path => N("/_Help").N("/_About..."), 
         callback => sub {
             $in->ask_warn(N("About Harddrake"), 
                           join ("", N("This is HardDrake, a Mandrake hardware configuration tool.\nVersion:"), " $harddrake::data::version\n", 
                                 N("Author:"), " Thierry Vignaud <tvignaud\@mandrakesoft.com> \n\n",
                                 formatAlaTeX($::license)));
         }
     }
     );

# fill the devices tree
sub detect {
    my @class_tree;
    foreach (@harddrake::data::tree) {
        my ($Ident, $title, $icon, $configurator, $detector) = @$_;
        next if ref($detector) ne "CODE"; #skip class witouth detector
        next if $Ident =~ /(MODEM|PRINTER)/ && $::testing;
        next if $Ident =~ /MODEM/ && !$options{MODEMS_DETECTION};
        next if $Ident =~ /PRINTER/ && !$options{PRINTERS_DETECTION};
#    print N("Probing %s class\n", $Ident);
#    standalone::explanations("Probing %s class\n", $Ident);

        my @devices = &$detector;
        next if !listlength(@devices); # Skip empty class (no devices)
        my $devices_list;
        foreach (@devices) {
            $_->{custom_id} = harddrake::data::custom_id($_, $title);
            if (exists $_->{bus} && $_->{bus} eq "PCI") {
                my $i = $_;
                $_->{bus_id} = join ':', map { if_($i->{$_} ne "65535",  sprintf("%lx", $i->{$_})) } qw(vendor id subvendor subid);
                $_->{bus_location} = join ':', map { sprintf("%lx", $i->{$_}) } qw(pci_bus pci_device pci_function);
            }
            # split description into manufacturer/description
            ($_->{Vendor}, $_->{description}) = split(/\|/, $_->{description}) if exists $_->{description};
            
            if (exists $_->{val}) { # Scanner ?
                my $val = $_->{val};
                ($_->{Vendor}, $_->{description}) = split(/\|/, $val->{DESCRIPTION});
            }
            # EIDE detection incoherency:
            if (exists $_->{bus} && $_->{bus} eq 'ide') {
                $_->{channel} = $_->{channel} ? N("secondary") : N("primary");
                delete $_->{info};
            } elsif ((exists $_->{id}) && $_->{bus} !~ /USB|PCI/) {
                # SCSI detection incoherency:
                my $i = $_;
                $_->{bus_location} = join ':', map { sprintf("%lx", $i->{$_}) } qw(bus id);
            }
            if ($Ident eq "AUDIO") {
                require harddrake::sound;
                my $alter = harddrake::sound::get_alternative($_->{driver});
                $_->{alternative_drivers} = join(':', @$alter) if $alter->[0] ne 'unknown';
            }
            foreach my $i (qw(vendor id subvendor subid pci_bus pci_device pci_function MOUSETYPE XMOUSETYPE unsafe val devfs_prefix wacom auxmouse)) { delete $_->{$i} }
            $_->{device} = '/dev/'.$_->{device} if exists $_->{device};
            push @$devices_list, $_;
        }
        push @class_tree, [ $devices_list, [ [$title], 5], $icon, [ 0, ($title =~ /Unknown/ ? 0 : 1) ], $title, $configurator ];
    }
    @class_tree;
}

sub new {
    my ($sig_id, $wait);
    unless ($::isEmbedded) {
        # so we don't stop the mcc's animation while detecting hw & building ui
        $in = 'interactive'->vnew('su', 'default');
        $wait = $in->wait_message(N("Please wait"), N("Detection in progress"));
        my_gtk::flush();
    }
    %options = getVarsFromSh($conffile);
    my @class_tree = &detect;

    # Build the gui
    add_icon_path('/usr/share/pixmaps/harddrake2/');
    $w = my_gtk->new(N("Harddrake2 version ") . $harddrake::data::version);
    $w->{window}->set_usize(760, 550) unless $::isEmbedded;

    $w->{window}->add(my $main_vbox = gtkadd(gtkadd($::isEmbedded ? new Gtk::VBox(0, 0) :
                                                    gtkadd(new Gtk::VBox(0, 0),
                                                           my $menubar = ugtk::create_factory_menu($w->{rwindow}, @menu_items)),
                                                    my $hpaned = new Gtk::HPaned),
                                             my $statusbar = new Gtk::Statusbar));
    $main_vbox->set_child_packing($statusbar, 0, 0, 0, 'start');
    if ($::isEmbedded) {
        $main_vbox->add(gtksignal_connect(my $but = new Gtk::Button(N("Quit")),
                                          'clicked' => \&quit_global));
        $main_vbox->set_child_packing($but, 0, 0, 0, 'start');
    } else { $main_vbox->set_child_packing($menubar, 0, 0, 0, 'start') }

    $hpaned->pack1(gtkadd(new Gtk::Frame(N("Detected hardware")), createScrolledWindow(my $tree = new Gtk::CTree(1, 0))), 1, 1);
    $hpaned->pack2(my $vbox = gtkadd(gtkadd(gtkadd(new Gtk::VBox,
                                                   gtkadd(new Gtk::Frame(N("Information")),
                                                          gtkadd(new Gtk::HBox, 
                                                                 createScrolledWindow(my $text = new Gtk::Text)))), 
                                            my $module_cfg_button = new Gtk::Button(N("Configure module"))),
                                     my $config_button = new Gtk::Button(N("Run config tool"))), 1, 1);
    $vbox->set_child_packing($config_button, 0, 0, 0, 'start');
    $vbox->set_child_packing($module_cfg_button, 0, 0, 0, 'start');

    my $color = gtkcolor(0x3100, 0x6400, 0xbc00);
    my $wcolor = gtkcolor(0xFFFF, 0x6400, 0x6400);
    $tree->set_column_auto_resize(0, 1);

    $tree->signal_connect('select_row', sub {
        my ($ctree, $row, $column, $event) = @_;
        my $node = $ctree->node_nth($row);
        my ($name, undef) = $tree->node_get_pixtext($node,0);
        $current_device = $tree->{data}{$name};

        if ($current_device) {
            $text->hide;
            $text->backward_delete($text->get_point);
            foreach my $i (sort keys %$current_device) {
                if ($fields{$i}[0]) {
                    $text->insert("", $text->style->black, "", $fields{$i}[0] . ": ");
                    $text->insert("", $i eq 'driver' && $current_device->{$i} eq 'unknown' ? $wcolor : $color,
                                  "", "$current_device->{$i}\n\n");
                } else { print "Skip \"$i\" field => \"$current_device->{$i}\"\n\n" }
            }
            disconnect($module_cfg_button, 'module');

            # we've valid driver, let's offer to configure it
            if (exists $current_device->{driver} &&  $current_device->{driver} !~ /(unknown|.*\|.*)/ &&  $current_device->{driver} !~ /^Card:/) {
                $module_cfg_button->show;
                $IDs{module} = $module_cfg_button->signal_connect(clicked => sub {
                    require modules::interactive;
                    modules::interactive::config_window($in, $current_device);
                    gtkset_mousecursor_normal();
                });
            }
            disconnect($config_button, 'tool');
            $text->show;
            my $configurator = $tree->{configurator}{$name};

            return unless -x $configurator;
            
            # we've a configurator, let's add a button for it and show it
            $IDs{tool} = $config_button->signal_connect(clicked => sub {
                return if defined $pid;
                if ($pid = fork()) {
                    $sig_id = $statusbar->push($statusbar->get_context_id("id"), N("Running \"%s\" ...", $configurator));
                } else { exec($configurator) or die "$configurator missing\n" }
            });
            $config_button->show;
        } else {
            $text->backward_delete($text->get_point); # erase all previous text
            $config_button->hide;
            $module_cfg_button->hide;
        }
    });

    # Fill the graphic tree with a "tree branch" widget per device category
    foreach (@class_tree) {
        my ($devices_list, $arg, $icon, $arg2, $title, $configurator) = @$_;
        my $hw_class_tree = $tree->insert_node(undef, undef, @$arg, (gtkcreate_png($icon)) x 2, @$arg2);
        # Fill the graphic tree with a "tree leaf" widget per device
        foreach (@$devices_list) {
            my $custom_id = $_->{custom_id};
            delete $_->{custom_id};
            $custom_id .= ' ' while exists($tree->{data}{$custom_id});
            my $hw_item = $tree->insert_node($hw_class_tree, undef, [$custom_id ], 5, (undef) x 4, 1, 0);
            $tree->{data}{$custom_id} = $_;
            $tree->{configurator}{$custom_id} = $configurator;
        }
    }

    $SIG{CHLD} = sub { undef $pid; $statusbar->pop($sig_id) };
    $w->{rwindow}->signal_connect(delete_event => \&quit_global);
    $w->{rwindow}->set_position('center') unless $::isEmbedded;

    foreach (['PRINTERS_DETECTION', N("/Autodetect printers")], ['MODEMS_DETECTION', N("/Autodetect modems")]) {
        $check_boxes{$_->[0]} = $menubar->{factory}->get_widget("<main>".N("/Options").$_->[1]);
        $options{$_->[0]} = 0 unless defined($options{$_->[0]}); # force detection by default
        $check_boxes{$_->[0]}->set_active($options{$_->[0]});    # restore saved values
    }

    $w->{rwindow}->show_all();
    undef $wait;
    gtkset_mousecursor_normal();
    foreach ($module_cfg_button, $config_button) { $_->hide };
    $in = 'interactive'->vnew('su', 'default') if $::isEmbedded;
    $w->main;
}


sub quit_global {
    kill(15, $pid) if $pid;
    setVarsInSh($conffile, \%options);
    my_gtk->exit(0);
}

# remove a signal handler from a button & hide it if needed
sub disconnect {
    my ($button, $id) = @_;
    if ($IDs{$id}) {
        $button->signal_disconnect($IDs{$id});
        $button->hide;
        undef $IDs{$id};
    }
}

1;
