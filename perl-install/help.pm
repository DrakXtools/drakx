package help;

use common qw(:common);

%steps = (
selectLanguage =>
__("Choose preferred language for install and system usage."),

selectKeyboard =>
 __("Choose the layout corresponding to your keyboard from the list above"),

selectInstallClass =>
 __("Choose \"Install\" if there are no previous versions of GNU/Linux
installed, or if you wish to use multiple distributions or versions.

Choose \"Upgrade\" if you wish to update a previous version of Mandrake Linux:
5.1 (Venice), 5.2 (Leloo), 5.3 (Festen), 6.0 (Venus), 6.1 (Helios), Gold 2000
or 7.0 (Air).


Select:

  - Automated (recommended): If you have never installed GNU/Linux before, choose this. NOTE:
    networking will not be configured during installation, use \"LinuxConf\"
    to configure it after the install completes.

  - Customized: If you are familiar enough with GNU/Linux, you may then choose
    the primary usage for your machine. See below for details.

  - Expert: This supposes that you are fluent with GNU/Linux and want to
    perform a highly customized installation. As for a \"Customized\"
    installation class, you will be able to select the usage for your system.
    But please, please, DO NOT CHOOSE THIS UNLESS YOU KNOW WHAT YOU ARE DOING!
"),

selectInstallClassCorpo =>
 __("Select:

  - Customized: If you are familiar enough with GNU/Linux, you may then choose
    the primary usage for your machine. See below for details.

  - Expert: This supposes that you are fluent with GNU/Linux and want to
    perform a highly customized installation. As for a \"Customized\"
    installation class, you will be able to select the usage for your system.
    But please, please, DO NOT CHOOSE THIS UNLESS YOU KNOW WHAT YOU ARE DOING!
"),

selectInstallClass2 =>
__("The different choices for your machine's usage (provided, hence, that you have
chosen either \"Custom\" or \"Expert\" as an installation class) are the
following:

  - Normal: choose this if you intend to use your machine primarily for
    everyday use (office work, graphics manipulation and so on). Do not
    expect any compiler, development utility et al. installed.

  - Development: as its name says. Choose this if you intend to use your
    machine primarily for software development. You will then have a complete
    collection of software installed in order to compile, debug and format
    source code, or create software packages.

  - Server: choose this if the machine which you're installing Linux-Mandrake
    on is intended to be used as a server. Either a file server (NFS or SMB),
    a print server (Unix' lp (Line Printer) protocol or Windows style SMB
    printing), an authentication server (NIS), a database server and so on. As
    such, do not expect any gimmicks (KDE, GNOME...) to be installed.
"),

setupSCSI =>
 __("DrakX will attempt to look for PCI SCSI adapter(s). 
If DrakX finds a SCSI adapter and knows which driver to use it will
automatically install it (or them).

If you have no SCSI adapter, an ISA SCSI adapter, or a
PCI SCSI adapter that DrakX doesn't recognize you will be asked if a
SCSI adapter is present in your system. If there is no adapter present
you can just click 'No'. If you click 'Yes' a list of drivers will be
presented from which you can select your specific adapter.


If you had to manually specify your adapter, DrakX will
ask if you want to specify options for it.  You should allow DrakX to
probe the hardware for the options. This usually works well.

If not, you will need to provide options to the driver.
Review the Installation Guide for hints on retrieving this
information from Windows (if you have it on your system),
from hardware documentation, or from the manufacturer's
website (if you have Internet access)."),

partitionDisks =>
 __("At this point, you may choose what partition(s) to use to install
your Linux-Mandrake system if they have been already defined (from a
previous install of GNU/Linux or from another partitioning tool). In other
cases, hard drive partitions must be defined. This operation consists of
logically dividing the computer's hard drive capacity into separate
areas for use.


If you have to create new partitions, use \"Auto allocate\" to automatically
create partitions for GNU/Linux. You can select the disk for partitioning by
clicking on \"hda\" for the first IDE drive,
\"hdb\" for the second or \"sda\" for the first SCSI drive and so on.


Two common partition are: the root partition (/), which is the starting
point of the filesystem's directory hierarchy, and /boot, which contains
all files necessary to start the operating system when the
computer is first turned on.


Because the effects of this process are usually irreversible, partitioning
can be intimidating and stressful to the unexperienced user. DiskDrake
simplifies the process so that it must not be. Consult the documentation
and take your time before proceeding.


You can reach any option using the keyboard: navigate through the partitions
using Tab and Up/Down arrows. When a partition is selected, you can use:

- Ctrl-c  to create a new partition (when an empty partition is selected)

- Ctrl-d  to delete a partition

- Ctrl-m  to set the mount point
"),

formatPartitions =>
 __("Any partitions that have been newly defined must be formatted for
use (formatting meaning creating a filesystem). At this time, you may
wish to re-format some already existing partitions to erase the data
they contain. Note: it is not necessary to re-format pre-existing
partitions, particularly if they contain files or data you wish to keep.
Typically retained are /home and /usr/local."),

choosePackages =>
 __("You may now select the group of packages you wish to
install or upgrade.

DrakX will then check whether you have enough room to install them all. If not,
it will warn you about it. If you want to go on anyway, it will proceed onto
the installation of all selected groups but will drop some packages of lesser
interest. At the bottom of the list you can select the option
\"Individual package selection\"; in this case you will have to browse
through more than 1000 packages..."),

chooseCD =>
 __("If you have all the CDs in the list above, click Ok.
If you have none of those CDs, click Cancel.
If only some CDs are missing, unselect them, then click Ok."),

doInstallStep =>
 __("The packages selected are now being installed. This operation
should take a few minutes unless you have chosen to upgrade an
existing system, in that case it can take more time even before
upgrade starts."),

selectMouse =>
 __("If DrakX failed to find your mouse, or if you want to
check what it has done, you will be presented the list of mice
above.


If you agree with DrakX's settings, just click 'Ok'.
Otherwise you may choose the mouse that more closely matches your own
from the menu above.


In case of a serial mouse, you will also have to tell DrakX
which serial port it is connected to."),

selectSerialPort =>
 __("Please select the correct port. For example, the COM1 port under MS Windows
is named ttyS0 under GNU/Linux."),

configureNetwork =>
 __("This section is dedicated to configuring a local area
network (LAN) or a modem.

Choose \"Local LAN\" and DrakX will
try to find an Ethernet adapter on your machine. PCI adapters
should be found and initialized automatically.
However, if your peripheral is ISA, autodetection will not work,
and you will have to choose a driver from the list that will appear then.


As for SCSI adapters, you can let the driver probe for the adapter
in the first time, otherwise you will have to specify the options
to the driver that you will have fetched from documentation of your
hardware.


If you install a Linux-Mandrake system on a machine which is part
of an already existing network, the network administrator will
have given you all necessary information (IP address, network
submask or netmask for short, and hostname). If you're setting
up a private network at home for example, you should choose
addresses.


Choose \"Dialup with modem\" and the Internet connection with
a modem will be configured. DrakX will try to find your modem,
if it fails you will have to select the right serial port where
your modem is connected to."),

configureNetworkIP =>
 __("Enter:

  - IP address: if you don't know it, ask your network administrator or ISP.


  - Netmask: \"255.255.255.0\" is generally a good choice. If you are not
sure, ask your network administrator or ISP.


  - Automatic IP: If your network uses BOOTP or DHCP protocol, select 
this option. If selected, no value is needed in \"IP address\". If you are
not sure, ask your network administrator or ISP.
"),

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
 __("You can now select your timezone according to where you live.


GNU/Linux manages time in GMT or \"Greenwich Mean Time\" and translates it
in local time according to the time zone you have selected."),

configureServices =>
 __("You may now choose which services you want to see started at boot time.
When your mouse comes over an item, a small balloon help will popup which
describes the role of the service.

Be especially careful in this step if you intend to use your machine as a
server: you will probably want not to start any services which you don't
want."),

configurePrinter =>
 __("GNU/Linux can deal with many types of printer. Each of these
types require a different setup. Note however that the print
spooler uses 'lp' as the default printer name; so you
must have one printer with such a name; but you can give
several names, separated by '|' characters, to a printer.
So, if you prefer to have a more meaningful name you just have
to put it first, eg: \"My Printer|lp\".
The printer having \"lp\" in its name(s) will be the default printer.


If your printer is physically connected to your computer, select
\"Local printer\". You will then have to tell which port your
printer is connected to, and select the appropriate filter.


If you want to access a printer located on a remote Unix machine,
you will have to select \"Remote lpd\". In order to make
it work, no username or password is required, but you will need
to know the name of the printing queue on this server.


If you want to access a SMB printer (which means, a printer located
on a remote Windows 9x/NT machine), you will have to specify its
SMB name (which is not its TCP/IP name), and possibly its IP address,
plus the username, workgroup and password required in order to
access the printer, and of course the name of the printer. The same goes
for a NetWare printer, except that you need no workgroup information."),

setRootPassword =>
 __("You can now enter the root password for your Linux-Mandrake
system. The password must be entered twice to verify that both
password entries are identical.


Root is the administrator of the system, and is the only user
allowed to modify the system configuration. Therefore, choose
this password carefully! Unauthorized use of the root account can
be extremely dangerous to the integrity of the system and its data,
and other systems connected to it. The password should be a
mixture of alphanumeric characters and a least 8 characters long. It
should NEVER be written down. Do not make the password too long or
complicated, though: you must be able to remember without too much
effort."),

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
 __("It is strongly recommended that you answer \"Yes\" here. If you install
Microsoft Windows at a later date it will overwrite the boot sector.
Unless you have made a bootdisk as suggested, you will not be able to
boot into GNU/Linux any more."),

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

  - Use hard drive optimizations: this option can improve hard disk performance
    but is only for advanced users: some buggy chipsets can ruin your data, so
    beware. Note that the kernel has a builtin blacklist of drives and
    chipsets, but if you want to avoid bad surprises, leave this option unset.

  - Choose security level: you can choose a security level for your
    system. Please refer to the manual for complete information. Basically: if
    you don't know, select \"Medium\".

  - Precise RAM size if needed: unfortunately, in today's PC world, there is no
    standard method to ask the BIOS about the amount of RAM present in your
    computer. As a consequence, GNU/Linux may fail to detect your amount of RAM
    correctly. If this is the case, you can specify the correct amount of RAM
    here. Note that a difference of 2 or 4 MB is normal.

  - Removable media automounting: if you would prefer not to manually
    mount removable media (CD-ROM, Floppy, Zip) by typing \"mount\" and
    \"umount\", select this option. 

  - Enable NumLock at startup: if you want NumLock enabled after booting,
    select this option (Note: NumLock may or may not work under X)."),

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
