#!/usr/bin/perl

use CGI ':all';
use CGI::Carp;

my $default_append = "ramdisk_size=128000 root=/dev/ram3";
my $default_acpi = "acpi=ht";
my $default_vga = "vga=788";

my $cgi_name = "/" . ($0 =~ m|([^/]+)$|)[0];

print
  header(),
  start_html(-TITLE => 'hd_grub configuration');

if (param()) {
    print_menu_lst();
} else {
    print_form();
}

print end_html;


sub menu_lst {
    my ($hd, $hd_linux, $partition_number, $directory) = @_;

    my $grub_partition_number = $partition_number - 1;

    <<EOF;
timeout 0
default 0

title Mandriva Install

root ($hd,$grub_partition_number)
kernel $directory/isolinux/alt0/vmlinuz $default_append $default_acpi $default_vga automatic=method:disk,partition:$hd_linux$partition_number,directory:$directory
initrd $directory/isolinux/alt0/all.rdz
EOF

}

sub print_menu_lst {
    my $directory = param('directory');
    $directory =~ s!^/!!;
    print
      ol(li(qq(Select the text below and save it in a file "menu.lst")),
	 li(qq(Create a floppy from $directory/images/hd_grub.img (eg: <tt>dd if=hd_grub.img of=/dev/fd0</tt>))),
	 li(qq(Copy the file "menu.lst" to the floppy, overwriting the existing one)),
	 ),
      p(),
      start_form(-name => 'form', -action => $cgi_name, -method => 'get'),
      textarea(-default => menu_lst(param('hd'), param('hd_linux'), param('partition_number'), "/$directory"),
	       -rows => 15, -columns => 120,
	      ),
      end_form(),
}

sub print_form {
    print
      p(),
      start_form(-name => 'form', -action => $cgi_name, -method => 'get'),
      ul("Please choose the partition where Mandrivalinux is copied.",
	 li(popup_menu(-name => "hd", -default => 'hd0', 
		       -values => [ 'hd0' .. 'hd3' ],
		       -labels => { hd0 => '1st BIOS hard drive (usually hda or sda)',
				    hd1 => '2nd BIOS hard drive',
				    hd2 => '3rd BIOS hard drive',
				    hd3 => '4th BIOS hard drive',
				  })),
	 li(popup_menu(-name => "hd_linux", -default => 'hda', 
		       -values => [ 'hda' .. 'hdd', 'sda' .. 'sdc', 'hde' .. 'hdh' ],
		       -labels => { 
				    hda => '1st IDE hard drive (hda)',
				    hdb => '2nd IDE hard drive (hdb)',
				    hdc => '3rd IDE hard drive (hdc)',
				    hdd => '4th IDE hard drive (hdd)',
				    hde => '5th IDE hard drive (hde)',
				    hdf => '6th IDE hard drive (hdf)',
				    hdg => '7th IDE hard drive (hdg)',
				    hdh => '8th IDE hard drive (hdh)',
				    sda => '1st SCSI hard drive (sda)',
				    sdb => '2nd SCSI hard drive (sdb)',
				    sdc => '3rd SCSI hard drive (sdc)',
				  })),
	 li(popup_menu(-name => "partition_number", -default => '0', 
		       -values => [ 1 .. 15 ],
		       -labels => { 1 => '1st primary partition (hda1, sda1 or ...)',
				    2 => '2nd primary partition',
				    3 => '3rd primary partition',
				    4 => '4th primary partition',
				    5 => '5th partition (hda5, sda5 or ...) (first logical partition)',
				    map { $_ => $_ . 'th partition' } 6 .. 15
				  })),
       ),
      p(),
      ul("Please enter the directory containing the Mandrivalinux Distribution (relative to the partition chosen above)",
	 li(textfield(-name => 'directory', -default => '/cooker/i586', size => 40)),
	 ),
      p(submit(-name => 'Go')),
      end_form();
}
