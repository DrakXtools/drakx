#!/usr/bin/perl

use MDK::Common;

output 'help.msg', pack("C*", 0x0E, 0x80, 0x03, 0x00),
"
                  0aWelcome to 09Mandrake Move0a help07

In most cases, the best way to get started is to simply press the 0e<Enter>07 key.
If you experience problems, you can add the following options on the command line :

 o  0fnoauto07 to disable automatic detection (generally used with 0fexpert07).
 o  0fupdatemodules07 to use the special update floppy containing modules updates.
 o  0fpatch07 to use a patch from the floppy (file named 09patch.pl07).
 o  0fcleankey07 to remove previously saved system configuration files on the USB key.
 o  0fvirtual_key=/dev/hda1,/key07 to use file 0f/key07 on device 0f/dev/hda107 as a
    virtual key instead of a physical one (must be an existing file containing a valid FS).

You can also pass some 0f<specific kernel options>07 to the Linux kernel. 
For example, try 0flinux mem=128M07 if your system has 128Mb of RAM but we
don't detect the amount correctly.
0cNOTE07: You cannot pass options to modules (SCSI, ethernet card) or devices
such as CD-ROM drives in this way. If you need to do so, use expert mode.

0c[F1-Help] [F2-Main]07\n";
