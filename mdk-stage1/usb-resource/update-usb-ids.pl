#!/usr/bin/perl


sub cat_ { local *F; open F, $_[0] or $_[1] ? die "cat of file $_[0] failed: $!\n" : return; my @l = <F>; wantarray ? @l : join '', @l }


-x "../mar/mar" or die "\t*FAILED* Sorry, need ../mar/mar binary\n";


my @usbtable_tmp = cat_("/usr/share/ldetect-lst/usbtable");
my @usbtable;
foreach (@usbtable_tmp) {
    next if /\s*#/;
    /\s*(\S+)\s+(\S+)\s+"(\S+)"\s+"([^"]*)"/ or next;
    push @usbtable, { 'vendor' => $1, 'id' => $2, 'module' => $3, 'description' => $4 };
}


print '
struct usb_module_map {
	unsigned short	vendor;     /* vendor */
	unsigned short	id;         /* device */
	const char      *name;      /* human readable name */
	const char      *module;    /* module to load */
};
';

print "struct pci_module_map usb_pci_ids[] = {

";

require '/usr/bin/merge2pcitable.pl';
my $drivers = read_pcitable("/usr/share/ldetect-lst/pcitable");

while (my ($k, $v) = each %$drivers) {
    $v->[0] =~ /^usb-|^ehci-hcd/ or next;
    $k =~ /^(....)(....)/;
    printf qq|\t{ 0x%s, 0x%s, "", "%s" },\n|,
      $1, $2, $v->[0];
}

print "};
int usb_num_ids=sizeof(usb_pci_ids)/sizeof(struct pci_module_map);
";


my @t = ('usb');


foreach $type (@t) {
    my $modulez;
    foreach (glob("../../all.modules/*/${type}_modules.mar")) {
	-f $_ or die "\t*FAILED* Sorry, need $_ mar file\n";
	push @$modulez, (`../mar/mar -l $_`);
    }

    print "struct usb_module_map ${type}_usb_ids[] = {
";
    foreach my $usbentry (@usbtable) {
	grep(/^\t$usbentry->{'module'}\.o\s/, @$modulez) or next;
	printf qq|\t{ %s, %s, "%s", "%s" },\n|,
	   $usbentry->{'vendor'}, $usbentry->{'id'}, $usbentry->{'description'}, $usbentry->{'module'};
    }

    print "};
int ${type}_usb_num_ids=sizeof(${type}_usb_ids)/sizeof(struct usb_module_map);
";

}
