package help; # $Id$

use common qw(:common);

%steps = (
empty => '',

selectLanguage =>
 __("Please choose your preferred language for installation and system usage."),

license =>
 __("You need to accept the terms of the above license to continue installation.


Please click on \"Accept\" if you are agree with its terms.


Please click on \"Refuse\" if you disagree with its terms. Installation will end without modifying your current
configuration."),

selectKeyboard =>
 __("Choose the layout corresponding to your keyboard from the list above"),

selectLangs => 
 __("If you wish other languages (than the one you choose at
beginning of installation) will be available after installation, please chose
them in list above. If you want select all, you just need to select \"All\"."),

selectInstallClass =>
 __("Please choose \"Install\" if there are no previous version of Linux-Mandrake
installed or if you wish to use several operating systems.


Please choose \"Update\" if you wish to update an already installed version of Linux-Mandrake.


Depend of your knowledge in GNU/Linux, you can choose one of the following levels to install or update your
Linux-Mandrake operating system:

	* Recommanded: if you have never installed a GNU/Linux operating system choose this. Installation will be
	  be very easy and you will be asked only on few questions.


	* Customized: if you are familiar enough with GNU/Linux, you may choose the primary usage (workstation, server,
	  development) of your sytem. You will need to answer to more questions than in \"Recommanded\" installation
	  class, so you need to know how GNU/Linux works to choose this installation class.


	* Expert: if you have a good knowledge in GNU/Linux, you can choose this installation class. As in \"Customized\"
	  installation class, you will be able to choose the primary usage (workstation, server, development). Be very
	  careful before choose this installation class. You will be able to perform a higly customized installation.
	  Answer to some questions can be very difficult if you haven't a good knowledge in GNU/Linux. So, don't choose
	  this installation class unless you know what you are doing."),

selectInstallClassCorpo =>
 __("Select:

  - Customized: If you are familiar enough with GNU/Linux, you may then choose
    the primary usage for your machine. See below for details.


  - Expert: This supposes that you are fluent with GNU/Linux and want to
    perform a highly customized installation. As for a \"Customized\"
    installation class, you will be able to select the usage for your system.
    But please, please, DO NOT CHOOSE THIS UNLESS YOU KNOW WHAT YOU ARE DOING!"),

selectInstallClass2 =>
 __("You must now define your machine usage. Choices are:

	* Workstation: this the ideal choice if you intend to use your machine primarily for everyday use, at office or
	  at home.


	* Development: if you intend to use your machine primarily for software development, it is the good choice. You
	  will then have a complete collection of software installed in order to compile, debug and format source code,
	  or create software packages.


	* Server: if you intend to use this machine as a server, it is the good choice. Either a file server (NFS or
	  SMB), a print server (Unix style or Microsoft Windows style), an authentication server (NIS), a database
	  server and so on. As such, do not expect any gimmicks (KDE, GNOME, etc.) to be installed."),

setupSCSI => 
 __("DrakX will attempt to look for PCI SCSI adapter(s). If DrakX
finds an SCSI adapter and knows which driver to use, it will be automatically
installed.


If you have no SCSI adapter, an ISA SCSI adapter or a PCI SCSI adapter that
DrakX doesn't recognize, you will be asked if a SCSI adapter is present in your
system. If there is no adapter present, you can click on \"No\". If you click on
\"Yes\", a list of drivers will be presented from which you can select your
specific adapter.


If you have to manually specify your adapter, DrakX will ask if you want to
specify options for it. You should allow DrakX to probe the hardware for the
options. This usually works well.


If not, you will need to provide options to the driver. Please review the User
Guide (chapter 3, section \"Collective informations on your hardware) for hints
on retrieving this information from hardware documentation, from the
manufacturer's Web site (if you have Internet access) or from Microsoft Windows
(if you have it on your system)."),

doPartitionDisks => 
 __("At this point, you need to choose where to install your
Linux-Mandrake operating system on your hard drive. If it is empty or if an
existing operating system uses all the space available on it, you need to
partition it. Basically, partitioning a hard drive consists of logically
dividing it to create space to install your new Linux-Mandrake system.


Because the effects of the partitioning process are usually irreversible,
partitioning can be intimidating and stressful if you are an inexperienced user.
This wizard simplifies this process. Before beginning, please consult the manual
and take your time.


You need at least two partitions. One is for the operating system itself and the
other is for the virtual memory (also called Swap).


If partitions have been already defined (from a previous installation or from
another partitioning tool), you just need choose those to use to install your
Linux system.


If partitions haven't been already defined, you need to create them. 
To do that, use the wizard available above. Depending of your hard drive
configuration, several solutions can be available:

	* Use existing partition: the wizard has detected one or more existing Linux partitions on your hard drive. If
	  you want to keep them, choose this option. 


	* Erase entire disk: if you want delete all data and all partitions present on your hard drive and replace them by
	  your new Linux-Mandrake system, you can choose this option. Be careful with this solution, you will not be
	  able to revert your choice after confirmation.


	* Use the free space on the Windows partition: if Microsoft Windows is installed on your hard drive and takes
	  all space available on it, you have to create free space for Linux data. To do that you can delete your
	  Microsoft Windows partition and data (see \"Erase entire disk\" or \"Expert mode\" solutions) or resize your
	  Microsoft Windows partition. Resizing can be performed without loss of any data. This solution is
	  recommended if you want use both Linux-Mandrake and Microsoft Windows on same computer.


	  Before choosing this solution, please understand that the size of your Microsoft
	  Windows partition will be smaller than at present time. It means that you will have less free space under
	  Microsoft Windows to store your data or install new software.


	* Expert mode: if you want to partition manually your hard drive, you can choose this option. Be careful before
	  choosing this solution. It is powerful but it is very dangerous. You can lose all your data very easily. So,
	  don't choose this solution unless you know what you are doing."),

partition_with_diskdrake => 
 __("At this point, you need to choose what
partition(s) to use to install your new Linux-Mandrake system. If partitions
have been already defined (from a previous installation of GNU/Linux or from
another partitioning tool), you can use existing partitions. In other cases,
hard drive partitions must be defined.


To create partitions, you must first select a hard drive. You can select the
disk for partitioning by clicking on \"hda\" for the first IDE drive, \"hdb\" for
the second or \"sda\" for the first SCSI drive and so on.


To partition the selected hard drive, you can use these options:

   * Clear all: this option deletes all partitions available on the selected hard drive.


   * Auto allocate:: this option allows you to automatically create Ext2 and swap partitions in free space of your
     hard drive.


   * Rescue partition table: if your partition table is damaged, you can try to recover it using this option. Please
     be careful and remember that it can fail.


   * Undo: you can use this option to cancel your changes.


   * Reload: you can use this option if you wish to undo all changes and load your initial partitions table


   * Wizard: If you wish to use a wizard to partition your hard drive, you can use this option. It is recommended if
     you do not have a good knowledge in partitioning.


   * Restore from floppy: if you have saved your partition table on a floppy during a previous installation, you can
     recover it using this option.


   * Save on floppy: if you wish to save your partition table on a floppy to be able to recover it, you can use this
     option. It is strongly recommended to use this option


   * Done: when you have finished partitioning your hard drive, use this option to save your changes.


For information, you can reach any option using the keyboard: navigate trough the partitions using Tab and Up/Down arrows.


When a partition is selected, you can use:

           * Ctrl-c to create a new partition (when a empty partition is selected)

           * Ctrl-d to delete a partition

           * Ctrl-m to set the mount point"),

ask_mntpoint_s => 
 __("Above are listed the existing Linux partitions detected on
your hard drive. You can keep choices make by the wizard, they are good for a
common usage. If you change these choices, you must at least define a root
partition (\"/\"). Don't choose a too little partition or you will not be able
to install enough software. If you want store your data on a separate partition,
you need also to choose a \"/home\" (only possible if you have more than one
Linux partition available).


For information, each partition is listed as follows: \"Name\", \"Capacity\".


\"Name\" is coded as follow: \"hard drive type\", \"hard drive number\",
\"partition number\" (for example, \"hda1\").


\"Hard drive type\" is \"hd\" if your hard drive is an IDE hard drive and \"sd\"
if it is an SCSI hard drive.


\"Hard drive number\" is always a letter after \"hd\" or \"sd\". With IDE hard drives:

   * \"a\" means \"master hard drive on the primary IDE controller\",

   * \"b\" means \"slave hard drive on the primary IDE controller\",

   * \"c\" means \"master hard drive on the secondary IDE controller\",

   * \"d\" means \"slave hard drive on the secondary IDE controller\".


With SCSI hard drives, a \"a\" means \"primary hard drive\", a \"b\" means \"secondary hard drive\", etc..."),

takeOverHdChoose => 
 __("Choose the hard drive you want to erase to install your
new Linux-Mandrake partition. Be careful, all data present on it will be lost
and will not be recoverable."),

takeOverHdConfirm => 
 __("Click on \"OK\" if you want to delete all data and
partitions present on this hard drive. Be careful, after clicking on \"OK\", you
will not be able to recover any data and partitions present on this hard drive,
including any Windows data.


Click on \"Cancel\" to cancel this operation without losing any data and
partitions present on this hard drive."),

resizeFATChoose => 
 __("More than one Microsoft Windows partition have been
detected on your hard drive. Please choose the one you want resize to install
your new Linux-Mandrake operating system.


For information, each partition is listed as follow; \"Linux name\", \"Windows
name\" \"Capacity\".

\"Linux name\" is coded as follow: \"hard drive type\", \"hard drive number\",
\"partition number\" (for example, \"hda1\").


\"Hard drive type\" is \"hd\" if your hard dive is an IDE hard drive and \"sd\"
if it is an SCSI hard drive.


\"Hard drive number\" is always a letter putted after \"hd\" or \"sd\". With IDE hard drives:

   * \"a\" means \"master hard drive on the primary IDE controller\",

   * \"b\" means \"slave hard drive on the primary IDE controller\",

   * \"c\" means \"master hard drive on the secondary IDE controller\",

   * \"d\" means \"slave hard drive on the secondary IDE controller\".

With SCSI hard drives, a \"a\" means \"primary hard drive\", a \"b\" means \"secondary hard drive\", etc.


\"Windows name\" is the letter of your hard drive under Windows (the first disk
or partition is called \"C:\")."),

resizeFATWait => 
 __("Please be patient. This operation can take several minutes."),

formatPartitions => 
 __("Any partitions that have been newly defined must be
formatted for use (formatting meaning creating a filesystem).


At this time, you may wish to reformat some already existing partitions to erase
the data they contain. If you wish do that, please also select the partitions
you want to format.


Please note that it is not necessary to reformat all pre-existing partitions.
You must reformat the partitions containing the operating system (such as \"/\",
\"/usr\" or \"/var\") but do you no have to reformat partitions containing data
that you wish to keep (typically /home).


Please be careful selecting partitions, after formatting, all data will be
deleted and you will not be able to recover any of them.


Click on \"OK\" when you are ready to format partitions.


Click on \"Cancel\" if you want to choose other partitions to install your new
Linux-Mandrake operating system."),

choosePackages => 
 __("You may now select the group of packages you wish to
install or upgrade.


DrakX will then check whether you have enough room to install them all. If not,
it will warn you about it. If you want to go on anyway, it will proceed onto the
installation of all selected groups but will drop some packages of lesser
interest. At the bottom of the list you can select the option 
\"Individual package selection\"; in this case you will have to browse through
more than 1000 packages..."),

choosePackagesTree => 
 __("You can now choose individually all the packages you
wish to install.


You can expand or collapse the tree by clicking on options in the left corner of
the packages window.


If you prefer to see packages sorted in alphabetic order, click on the icon
\"Toggle flat and group sorted\".


If you want not to be warned on dependencies, click on \"Automatic
dependencies\". If you do this, note that unselecting one package may silently
unselect several other packages which depend on it."),

chooseCD => 
 __("If you have all the CDs in the list above, click Ok. If you have
none of those CDs, click Cancel. If only some CDs are missing, unselect them,
then click Ok."),

installPackages => 
 __("Your new Linux-Mandrake operating system is currently being
installed. This operation should take a few minutes (it depends on size you
choose to install and the speed of your computer).


Please be patient."),

selectMouse => 
 __( "You can now test your mouse. Use buttons and wheel to verify
if settings are good. If not, you can click on \"Cancel\" to choose another
driver."),

selectSerialPort => 
 __("Please select the correct port. For example, the COM1
port under MS Windows is named ttyS0 under GNU/Linux."),

configureNetwork => 
 __("If you wish to connect your computer to the Internet or
to a local network please choose the correct option. Please turn on your device
before choosing the correct option to let DrakX detect it automatically.


If you do not have any connection to the Internet or a local network, choose
\"Disable networking\".


If you wish to configure the network later after installation or if you have
finished to configure your network connection, choose \"Done\"."),

configureNetworkNoModemFound => 
 __("No modem has been detected. Please select the serial port on which it is plugged.


For information, the first serial port (called \"COM1\" under Microsoft
Windows) is called \"ttyS0\" under Linux."),

configureNetworkDNS => 
 __("You may now enter dialup options. If you don't know
or are not sure what to enter, the correct informations can be obtained from
your Internet Service Provider. If you do not enter the DNS (name server)
information here, this information will be obtained from your Internet Service
Provider at connection time."),

configureNetworkISDN => 
 __("If your modem is an external modem, please turn on it now to let DrakX detect it automatically."),

configureNetworkADSL => 
 __("Please turn on your modem and choose the correct one."),

configureNetworkADSL2 => 
 __("If you are not sure if informations above are
correct or if you don't know or are not sure what to enter, the correct
informations can be obtained from your Internet Service Provider. If you do not
enter the DNS (name server) information here, this information will be obtained
from your Internet Service Provider at connection time."),

configureNetworkCable => 
 __("You may now enter your host name if needed. If you
don't know or are not sure what to enter, the correct informations can be
obtained from your Internet Service Provider."),

configureNetworkIP => 
 __("You may now configure your network device.

   * IP address: if you don't know or are not sure what to enter, ask your network administrator.
     You should not enter an IP address if you select the option \"Automatic IP\" below.

   * Netmask: \"255.255.255.0\" is generally a good choice. If you don't know or are not sure what to enter,
     ask your network administrator.

   * Automatic IP: if your network uses BOOTP or DHCP protocol, select this option. If selected, no value is needed in
    \"IP address\". If you don't know or are not sure if you need to select this option, ask your network administrator."),

configureNetworkHost => 
 __("You may now enter your host name if needed. If you
don't know or are not sure what to enter, ask your network administrator."),

configureNetworkHostDHCP => 
 __("You may now enter your host name if needed. If you
don't know or are not sure what to enter, leave blank."),

configureNetworkISP =>
 __("You may now enter dialup options. If you're not sure what to enter, the
correct information can be obtained from your ISP."),

configureNetworkProxy =>
 __("If you will use proxies, please configure them now. If you don't know if
you should use proxies, ask your network administrator or your ISP."),

installCrypto =>
 __("You can install cryptographic package if your internet connection has been
set up correctly. First choose a mirror where you wish to download packages and
after that select the packages to install.


Note you have to select mirror and cryptographic packages according
to your legislation."),

configureTimezone =>
 __("You can now select your timezone according to where you live."),

configureTimezoneGMT => 
 __("GNU/Linux manages time in GMT (Greenwich Manage
Time) and translates it in local time according to the time zone you have
selected.


If you use Microsoft Windows on this computer, choose \"No\"."),

configureServices =>
 __("You may now choose which services you want to start at boot time.


When your mouse comes over an item, a small balloon help will popup which
describes the role of the service.


Be very careful in this step if you intend to use your machine as a server: you
will probably want not to start any services that you don't need. Please
remember that several services can be dangerous if they are enable on a server.
In general, select only the services that you really need."),

configurePrinter => 
 __("You can configure a local printer (connected to your computer) or remote
printer (accessible via a Unix, Netware or Microsoft Windows network)."),

configurePrinterSystem => 
 __("If you wish to be able to print, please choose one printing system between
CUPS and LPR.


CUPS is a new, powerful and flexible printing system for Unix systems (CUPS
means \"Common Unix Printing System\"). It is the default printing system in
Linux-Mandrake.


LPR is the old printing system used in previous Linux-Mandrake distributions.


If you don't have printer, click on \"None\"."),

configurePrinterConnected => 
 __("GNU/Linux can deal with many types of printer. Each of these types requires
a different setup.


If your printer is physically connected to your computer, select \"Local
printer\".


If you want to access a printer located on a remote Unix machine, select
\"Remote printer\".


If you want to access a printer located on a remote Microsoft Windows machine
(or on Unix machine using SMB protocol), select \"SMB/Windows 95/98/NT\"."),

configurePrinterLocal => 
 __("Please turn on your printer before continuing to let DrakX detect it.

You have to enter some informations here.


   * Name of printer: the print spooler uses \"lp\" as default printer name. So, you must have a printer named \"lp\".
     If you have only one printer, you can use several names for it. You just need to separate them by a pipe
     character (a \"|\"). So, if you prefer a more meaningful name, you have to put it first, eg: \"My printer|lp\".
     The printer having \"lp\" in its name(s) will be the default printer.


   * Description: this is optional but can be useful if several printers are connected to your computer or if you allow
     other computers to access to this printer.


   * Location: if you want to put some information on your
     printer location, put it here (you are free to write what
     you want, for example \"2nd floor\").
"),

configurePrinterLPR => 
__("You need to enter some informations here.


   * Name of queue: the print spooler uses \"lp\" as default printer name. So, you need have a printer named \"lp\".
    If you have only one printer, you can use several names for it. You just need to separate them by a pipe
    character (a \"|\"). So, if you prefer to have a more meaningful name, you have to put it first, eg: \"My printer|lp\".
    The printer having \"lp\" in its name(s) will be the default printer.

  
   * Spool directory: it is in this directory that printing jobs are stored. Keep the default choice
     if you don't know what to use


   * Printer Connection: If your printer is physically connected to your computer, select \"Local printer\".
     If you want to access a printer located on a remote Unix machine, select \"Remote lpd printer\".


     If you want to access a printer located on a remote Microsoft Windows machine (or on Unix machine using SMB
     protocol), select \"SMB/Windows 95/98/NT\".


     If you want to acces a printer located on NetWare network, select \"NetWare\".
"),

configurePrinterDev => 
 __("Your printer has not been detected. Please enter the name of the device on
which it is connected.


For information, most printers are connected on the first parallel port. This
one is called \"/dev/lp0\" under GNU/Linux and \"LPT1\" under Microsoft Windows."),

configurePrinterType => 
 __("You must now select your printer in the above list."),

configurePrinterOptions => 
__("Please select the right options according to your printer.
Please see its documentation if you don't know what choose here.


You will be able to test your configuration in next step and you will be able to modify it if it doesn't work as you want."),

setRootPassword => 
 __("You can now enter the root password for your Linux-Mandrake system.
The password must be entered twice to verify that both password entries are identical.


Root is the system's administrator and is the only user allowed to modify the
system configuration. Therefore, choose this password carefully. 
Unauthorized use of the root account can be extemely dangerous to the integrity
of the system, its data and other system connected to it.


The password should be a mixture of alphanumeric characters and at least 8
characters long. It should never be written down.


Do not make the password too long or complicated, though: you must be able to
remember it without too much effort."),

setRootPasswordMd5 =>
 __("To enable a more secure system, you should select \"Use shadow file\" and
\"Use MD5 passwords\"."),

setRootPasswordNIS =>
 __("If your network uses NIS, select \"Use NIS\". If you don't know, ask your
network administrator."),

addUser =>
 __("You may now create one or more \"regular\" user account(s), as
opposed to the \"privileged\" user account, root. You can create
one or more account(s) for each person you want to allow to use
the computer. Note that each user account will have its own
preferences (graphical environment, program settings, etc.)
and its own \"home directory\", in which these preferences are
stored.


First of all, create an account for yourself! Even if you will be the only user
of the machine, you may NOT connect as root for daily use of the system: it's a
very high security risk. Making the system unusable is very often a typo away.


Therefore, you should connect to the system using the user account
you will have created here, and login as root only for administration
and maintenance purposes."),

createBootdisk => 
 __("Creating a boot disk is strongly recommended. If you can't
boot your computer, it's the only way to rescue your system without
reinstalling it."),

setupBootloaderBeginner =>
 __("You need to indicate where you wish
to place the information required to boot to GNU/Linux.


Unless you know exactly what you are doing, choose \"First sector of
drive (MBR)\"."),

setupBootloader =>
 __("Unless you know specifically otherwise, the usual choice is \"/dev/hda\"
 (primary master IDE disk) or \"/dev/sda\" (first SCSI disk)."),

setupBootloaderAddEntry =>
 __("LILO (the LInux LOader) and Grub are bootloaders: they are able to boot
either GNU/Linux or any other operating system present on your computer.
Normally, these other operating systems are correctly detected and
installed. If this is not the case, you can add an entry by hand in this
screen. Be careful as to choose the correct parameters.


You may also want not to give access to these other operating systems to
anyone, in which case you can delete the corresponding entries. But
in this case, you will need a boot disk in order to boot them!"),

setupBootloaderGeneral =>
 __("LILO and grub main options are:
  - Boot device: Sets the name of the device (e.g. a hard disk
partition) that contains the boot sector. Unless you know specifically
otherwise, choose \"/dev/hda\".


  - Delay before booting default image: Specifies the number in tenths
of a second the boot loader should wait before booting the first image.
This is useful on systems that immediately boot from the hard disk after
enabling the keyboard. The boot loader doesn't wait if \"delay\" is
omitted or is set to zero.


  - Video mode: This specifies the VGA text mode that should be selected
when booting. The following values are available: 

    * normal: select normal 80x25 text mode.

    * <number>:  use the corresponding text mode."),

setupSILOAddEntry =>
 __("SILO is a bootloader for SPARC: it is able to boot
either GNU/Linux or any other operating system present on your computer.
Normally, these other operating systems are correctly detected and
installed. If this is not the case, you can add an entry by hand in this
screen. Be careful as to choose the correct parameters.


You may also want not to give access to these other operating systems to
anyone, in which case you can delete the corresponding entries. But
in this case, you will need a boot disk in order to boot them!"),

setupSILOGeneral =>
 __("SILO main options are:
  - Bootloader installation: Indicate where you want to place the
information required to boot to GNU/Linux. Unless you know exactly
what you are doing, choose \"First sector of drive (MBR)\".


  - Delay before booting default image: Specifies the number in tenths
of a second the boot loader should wait before booting the first image.
This is useful on systems that immediately boot from the hard disk after
enabling the keyboard. The boot loader doesn't wait if \"delay\" is
omitted or is set to zero."),

configureX =>
 __("Now it's time to configure the X Window System, which is the
core of the GNU/Linux GUI (Graphical User Interface). For this purpose,
you must configure your video card and monitor. Most of these
steps are automated, though, therefore your work may only consist
of verifying what has been done and accept the settings :)


When the configuration is over, X will be started (unless you
ask DrakX not to) so that you can check and see if the
settings suit you. If they don't, you can come back and
change them, as many times as necessary."),

configureXmain =>
 __("If something is wrong in X configuration, use these options to correctly
configure the X Window System."),

configureXxdm =>
 __("If you prefer to use a graphical login, select \"Yes\". Otherwise, select
\"No\"."),

miscellaneous =>
 __("You can now select some miscellaneous options for your system.

* Use hard drive optimizations: this option can improve hard disk performance but is only for advanced users. Some buggy
  chipsets can ruin your data, so beware. Note that the kernel has a builtin blacklist of drives and chipsets, but if
  you want to avoid bad surprises, leave this option unset.


* Choose security level: you can choose a security level for your system. Please refer to the manual for complete
  information. Basically, if you don't know what to choose, keep the default option.


* Precise RAM if needed: unfortunately, there is no standard method to ask the BIOS about the amount of RAM present in
  your computer. As consequence, Linux may fail to detect your amount of RAM correctly. If this is the case, you can
  specify the correct amount or RAM here. Please note that a difference of 2 or 4 MB between detected memory and memory
  present in your system is normal.


* Removable media automounting: if you would prefer not to manually mount removable media (CD-Rom, floppy, Zip, etc.) by
  typing \"mount\" and \"umount\", select this option.


* Clean \"/tmp\" at each boot: if you want delete all files and directories stored in \"/tmp\" when you boot your system,
  select this option.


* Enable num lock at startup: if you want NumLock key enabled after booting, select this option. Please note that you
  should not enable this option on laptops and that NumLock may or may not work under X."),

exitInstall =>
 __("Your system is going to reboot.

After rebooting, your new Linux Mandrake system will load automatically.
If you want to boot into another existing operating system, please read
the additional instructions."),
);

#-#- ################################################################################
#-#- NO LONGER UP-TO-DATE...
#-%steps_long = (
#-selectLanguage =>
#- __("Choose preferred language for install and system usage."),
#-
#-selectKeyboard =>
#- __("Choose the layout corresponding to your keyboard from the list above"),
#-
#-selectPath =>
#- __("Choose \"Installation\" if there are no previous versions of GNU/Linux
#-installed, or if you wish to use multiple distributions or versions.
#-
#-
#-Choose \"Update\" if you wish to update a previous version of Mandrake
#-Linux: 5.1 (Venice), 5.2 (Leeloo), 5.3 (Festen) or 6.0 (Venus)."),
#-
#-selectInstallClass =>
#- __("Select:
#-
#-  - Beginner: If you have never installed GNU/Linux before, and wish to
#-install the distribution elected \"Product of the year\" for 1999,
#-click here.
#-
#-  - Developer: If you are familiar with GNU/Linux and will be using the
#-computer primarily for software development, you will find happiness
#-here.
#-
#-  - Server: If you wish to install a general purpose server, or the
#-GNU/Linux distribution elected \"Distribution/Server\" for 1999, select
#-this.
#-
#-  - Expert: If you are fluent with GNU/Linux and want to perform
#-a highly customized installation, this Install Class is for you."),
#-
#-setupSCSI =>
#- __("DrakX will attempt at first to look for one or more PCI
#-SCSI adapter(s). If it finds it (or them)  and knows which driver(s)
#-to use, it will insert it (them)  automatically.
#-
#-If your SCSI adapter is ISA, or is PCI but DrakX doesn't know
#-which driver to use for this card, or if you have no SCSI adapters
#-at all, you will then be prompted on whether you have one or not.
#-If you have none, answer \"No\". If you have one or more, answer
#-\"Yes\". A list of drivers will then pop up, from which you will
#-have to select one.
#-
#-After you have selected the driver, DrakX will ask if you
#-want to specify options for it. First, try and let the driver
#-probe for the hardware: it usually works fine.
#-
#-If not, do not forget the information on your hardware that you
#-could get from you documentation or from Windows (if you have
#-it on your system), as suggested by the installation guide.
#-These are the options you will need to provide to the driver."),
#-
#-partitionDisks =>
#- __("In this stage, you may choose what partition(s) use to install your
#-Linux-Mandrake system."),
#-
#-#At this point, hard drive partitions must be defined. (Unless you
#-#are overwriting a previous install of GNU/Linux and have already defined
#-#your hard drive partitions as desired.) This operation consists of
#-#logically dividing the computer's hard drive capacity into separate
#-#areas for use.
#-#
#-#
#-#Two common partition are: the root partition (/), which is the starting
#-#point of the filesystem's directory hierarchy, and /boot, which contains
#-#all files necessary to start the operating system when the
#-#computer is first turned on.
#-#
#-#
#-#Because the effects of this process are usually irreversible, partitioning
#-#can be intimidating and stressful to the unexperienced. DiskDrake
#-#simplifies the process so that it need not be. Consult the documentation
#-#and take your time before proceeding."),
#-
#-formatPartitions =>
#- __("Any partitions that have been newly defined must be formatted for
#-use (formatting meaning creating a filesystem). At this time, you may
#-wish to re-format some already existing partitions to erase the data
#-they contain. Note: it is not necessary to re-format pre-existing
#-partitions, particularly if they contain files or data you wish to keep.
#-Typically retained are /home and /usr/local."),
#-
#-choosePackages =>
#- __("You may now select the packages you wish to install.
#-
#-
#-Please note that some packages require the installation of others.
#-These are referred to as package dependencies. The packages you select,
#-and the packages they require will be automatically selected for
#-install. It is impossible to install a package without installing all
#-of its dependencies.
#-
#-
#-Information on each category and specific package is available in the
#-area titled \"Info\",  located between list of packages and the five
#-buttons \"Install\", \"Select more/less\" and \"Show more/less\"."),
#-
#-doInstallStep =>
#- __("The packages selected are now being installed.
#-
#-
#-This operation should take a few minutes."),
#-
#-selectMouse =>
#- __("If DrakX failed to find your mouse, or if you want to
#-check what it has done, you will be presented the list of mice
#-above.
#-
#-
#-If you agree with DrakX' settings, just jump to the section
#-you want by clicking on it in the menu on the left. Otherwise,
#-choose a mouse type in the menu which you think is the closest
#-match for your mouse.
#-
#-In case of a serial mouse, you will also have to tell DrakX
#-which serial port it is connected to."),
#-
#-configureNetwork =>
#- __("This section is dedicated to configuring a local area network,
#-or LAN. If you answer \"Yes\" here, DrakX will try to find an
#-Ethernet adapter on your machine. PCI adapters should be found and
#-initialized automatically. However, if your peripheral is ISA,
#-autodetection will not work, and you will have to choose a driver
#-from the list that will appear then.
#-
#-
#-As for SCSI adapters, you can let the driver probe for the adapter
#-in the first time, otherwise you will have to specify the options
#-to the driver that you will have fetched from Windows' control
#-panel.
#-
#-
#-If you install a Linux-Mandrake system on a machine which is part
#-of an already existing network, the network administrator will
#-have given you all necessary information (IP address, network
#-submask or netmask for short, and hostname). If you're setting
#-up a private network at home for example, you should choose
#-addresses "),
#-
#-configureTimezone =>
#- __("Help"),
#-
#-configureServices =>
#- __("Help"),
#-
#-configurePrinter =>
#- __("GNU/Linux can deal with many types of printer. Each of these
#-types require a different setup.
#-
#-
#-If your printer is directly connected to your computer, select
#-\"Local printer\". You will then have to tell which port your
#-printer is connected to, and select the appropriate filter.
#-
#-
#-If you want to access a printer located on a remote Unix machine,
#-you will have to select \"Remote lpd queue\". In order to make
#-it work, no username or password is required, but you will need
#-to know the name of the printing queue on this server.
#-
#-
#-If you want to access a SMB printer (which means, a printer located
#-on a remote Windows 9x/NT machine), you will have to specify its
#-SMB name (which is not its TCP/IP name), and possibly its IP address,
#-plus the username, workgroup and password required in order to
#-access the printer, and of course the name of the printer.The same goes
#-for a NetWare printer, except that you need no workgroup information."),
#-
#-setRootPassword =>
#- __("You must now enter the root password for your Linux-Mandrake
#-system. The password must be entered twice to verify that both
#-password entries are identical.
#-
#-
#-Root is the administrator of the system, and is the only user
#-allowed to modify the system configuration. Therefore, choose
#-this password carefully! Unauthorized use of the root account can
#-be extremely dangerous to the integrity of the system and its data,
#-and other systems connected to it. The password should be a
#-mixture of alphanumeric characters and a least 8 characters long. It
#-should *never* be written down. Do not make the password too long or
#-complicated, though: you must be able to remember without too much
#-effort."),
#-
#-addUser =>
#- __("You may now create one or more \"regular\" user account(s), as
#-opposed to the \"privileged\" user account, root. You can create
#-one or more account(s) for each person you want to allow to use
#-the computer. Note that each user account will have its own
#-preferences (graphical environment, program settings, etc.)
#-and its own \"home directory\", in which these preferences are
#-stored.
#-
#-
#-First of all, create an account for yourself! Even if you will be the only user
#-of the machine, you may NOT connect as root for daily use of the system: it's a
#-very high security risk. Making the system unusable is very often a typo away.
#-
#-
#-Therefore, you should connect to the system using the user account
#-you will have created here, and login as root only for administration
#-and maintenance purposes."),
#-
#-createBootdisk =>
#- __("Please, please, answer \"Yes\" here! Just for example, when you
#-reinstall Windows, it will overwrite the boot sector. Unless you have
#-made the bootdisk as suggested, you won't be able to boot into GNU/Linux
#-any more!"),
#-
#-setupBootloader =>
#- __("You need to indicate where you wish
#-to place the information required to boot to GNU/Linux.
#-
#-
#-Unless you know exactly what you are doing, choose \"First sector of
#-drive (MBR)\"."),
#-
#-configureX =>
#- __("Now it's time to configure the X Window System, which is the
#-core of the GNU/Linux GUI (Graphical User Interface). For this purpose,
#-you must configure your video card and monitor. Most of these
#-steps are automated, though, therefore your work may only consist
#-of verifying what has been done and accept the settings :)
#-
#-
#-When the configuration is over, X will be started (unless you
#-ask DrakX not to) so that you can check and see if the
#-settings suit you. If they don't, you can come back and
#-change them, as many times as necessary."),
#-
#-exitInstall =>
#- __("Help"),
#-);
