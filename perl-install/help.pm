package help;
use common;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.

%steps = (
empty => '',

addUser => 
__("GNU/Linux is a multiuser system, and this means that each user can have his
own preferences, his own files and so on. You can read the ``User Guide''
to learn more. But unlike \"root\", which is the administrator, the users
you will add here will not be entitled to change anything except their own
files and their own configuration. You will have to create at least one
regular user for yourself. That account is where you should log in for
routine use. Although it is very practical to log in as \"root\" everyday,
it may also be very dangerous! The slightest mistake could mean that your
system would not work any more. If you make a serious mistake as a regular
user, you may only lose some information, but not the entire system.

First, you have to enter your real name. This is not mandatory, of course -
as you can actually enter whatever you want. DrakX will then take the first
word you have entered in the box and will bring it over to the \"User
name\". This is the name this particular user will use to log into the
system. You can change it. You then have to enter a password here. A
non-privileged (regular) user's password is not as crucial as that of
\"root\" from a security point of view, but that is no reason to neglect it
- after all, your files are at risk.

If you click on \"Accept user\", you can then add as many as you want. Add
a user for each one of your friends: your father or your sister, for
example. When you finish adding all the users you want, select \"Done\".

Clicking the \"Advanced\" button allows you to change the default \"shell\"
for that user (bash by default)."),

ask_mntpoint_s => 
__("Listed above are the existing Linux partitions detected on your hard drive.
You can keep the choices made by the wizard, they are good for most common
installs. If you make any changes, you must at least define a root
partition (\"/\"). Do not choose too small a partition or you will not be
able to install enough software. If you want to store your data on a
separate partition, you will also need to create a partition for \"/home\"
(only possible if you have more than one Linux partition available).

Each partition is listed as follows: \"Name\", \"Capacity\".

\"Name\" is structured: \"hard drive type\", \"hard drive number\",
\"partition number\" (for example, \"hda1\").

\"Hard drive type\" is \"hd\" if your hard drive is an IDE hard drive and
\"sd\" if it is a SCSI hard drive.

\"Hard drive number\" is always a letter after \"hd\" or \"sd\". For IDE
hard drives:

 * \"a\" means \"master hard drive on the primary IDE controller\",

 * \"b\" means \"slave hard drive on the primary IDE controller\",

 * \"c\" means \"master hard drive on the secondary IDE controller\",

 * \"d\" means \"slave hard drive on the secondary IDE controller\".

With SCSI hard drives, an \"a\" means \"lowest SCSI ID\", a \"b\" means
\"second lowest SCSI ID\", etc."),

chooseCd => 
__("The Mandrake Linux installation is spread out over several CD-ROMs. DrakX
knows if a selected package is located on another CD-ROM and will eject the
current CD and ask you to insert a different one as required."),

choosePackages => 
__("It is now time to specify which programs you wish to install on your
system. There are thousands of packages available for Mandrake Linux, and
you are not supposed to know them all by heart.

If you are performing a standard installation from CD-ROM, you will first
be asked to specify the CDs you currently have (in Expert mode only). Check
the CD labels and highlight the boxes corresponding to the CDs you have
available for installation. Click \"OK\" when you are ready to continue.

Packages are sorted in groups corresponding to a particular use of your
machine. The groups themselves are sorted into four sections:

 * \"Workstation\": if you plan to use your machine as a workstation, select
one or more of the corresponding groups.

 * \"Development\": if the machine is to be used for programming, choose the
desired group(s).

 * \"Server\": if the machine is intended to be a server, you will be able
to select which of the most common services you wish to see installed on
the machine.

 * \"Graphical Environment\": finally, this is where you will choose your
preferred graphical environment. At least one must be selected if you want
to have a graphical workstation!

Moving the mouse cursor over a group name will display a short explanatory
text about that group. If you deselect all groups when performing a regular
installation (by opposition to an upgrade), a dialog will popup proposing
different options for a minimal installation:

 * \"With X\" Install the fewer packages possible for having a working
graphical desktop;

 * \"With basic documentation\" Installs the base system plus basic
utilities and their documentation. This installation is suitable for
setting up a server.

 * \"Truly minimal install\" Will install the strict minimum necessary to
get a working Linux system, in command line only.

You can check the \"Individual package selection\" box, which is useful if
you are familiar with the packages being offered or if you want to have
total control over what will be installed.

If you started the installation in \"Upgrade\" mode, you can unselect all
groups to avoid installing any new package. This is useful for repairing or
updating an existing system."),

choosePackagesTree => 
__("Finally, depending on your choice of whether or not to select individual
packages, you will be presented a tree containing all packages classified
by groups and subgroups. While browsing the tree, you can select entire
groups, subgroups, or individual packages.

Whenever you select a package on the tree, a description appears on the
right. When your selection is finished, click the \"Install\" button which
will then launch the installation process. Depending on the speed of your
hardware and the number of packages that need to be installed, it may take
a while to complete the process. A time to complete estimate is displayed
on the screen to help you gauge if there is sufficient time to enjoy a cup
of coffee.

!! If a server package has been selected either intentionally or because it
was part of a whole group, you will be asked to confirm that you really
want those servers to be installed. Under Mandrake Linux, any installed
servers are started by default at boot time. Even if they are safe and have
no known issues at the time the distribution was shipped, it may happen
that security holes are discovered after this version of Mandrake Linux was
finalized. If you do not know what a particular service is supposed to do
or why it is being installed, then click \"No\". Clicking \"Yes\" will
install the listed services and they will be started automatically by
default. !!

The \"Automatic dependencies\" option simply disables the warning dialog
which appears whenever the installer automatically selects a package. This
occurs because it has determined that it needs to satisfy a dependency with
another package in order to successfully complete the installation.

The tiny floppy disc icon at the bottom of the list allows to load the
packages list chosen during a previous installation. Clicking on this icon
will ask you to insert a floppy disk previously created at the end of
another installation. See the second tip of last step on how to create such
a floppy."),

configureNetwork => 
__("If you wish to connect your computer to the Internet or to a local network,
please choose the correct option. Please turn on your device before
choosing the correct option to let DrakX detect it automatically.

Mandrake Linux proposes the configuration of an Internet connection at
installation time. Available connections are: traditional modem, ISDN
modem, ADSL connection, cable modem, and finally a simple LAN connection
(Ethernet).

Here, we will not detail each configuration. Simply make sure that you have
all the parameters from your Internet Service Provider or system
administrator.

You can consult the manual chapter about internet connections for details
about the configuration, or simply wait until your system is installed and
use the program described there to configure your connection.

If you wish to configure the network later after installation or if you
have finished configuring your network connection, click \"Cancel\"."),

configureServices => 
__("You may now choose which services you wish to start at boot time.

Here are presented all the services available with the current
installation. Review them carefully and uncheck those which are not always
needed at boot time.

You can get a short explanatory text about a service by selecting a
specific service. However, if you are not sure whether a service is useful
or not, it is safer to leave the default behavior.

!! At this stage, be very careful if you intend to use your machine as a
server: you will probably not want to start any services that you do not
need. Please remember that several services can be dangerous if they are
enabled on a server. In general, select only the services you really need.
!!"),

configureTimezoneGMT => 
__("GNU/Linux manages time in GMT (Greenwich Mean Time) and translates it in
local time according to the time zone you selected. It is however possible
to deactivate this by deselcting \"Hardware clock set to GMT\" so that the
hardware clock is the same as the system clock. This is useful when the
machine is hosting another operating system like Windows.

The \"Automatic time synchronization\" option will automatically regulate
the clock by connecting to a remote time server on the internet. In the
list that is presented, choose a server located near you. Of course you
must have a working internet connection for this feature to function."),

configureX => 
__("X (for X Window System) is the heart of the GNU/Linux graphical interface
on which all the graphics environments (KDE, GNOME, AfterStep,
WindowMaker...) bundled with Mandrake Linux rely. In this section, DrakX
will try to configure X automatically.

It is extremely rare for it to fail, unless the hardware is very old (or
very new). If it succeeds, it will start X automatically with the best
resolution possible depending on the size of the monitor. A window will
then appear and ask you if you can see it.

If you are doing an \"Expert\" install, you will enter the X configuration
wizard. See the corresponding section of the manual for more information
about this wizard.

If you can see the message during the test, and answer \"Yes\", then DrakX
will proceed to the next step. If you cannot see the message, it simply
means that the configuration was wrong and the test will automatically end
after 10 seconds, restoring the screen."),

configureXmain => 
__("The first time you try the X configuration, you may not be very satisfied
with its display (screen is too small, shifted left or right...). Hence,
even if X starts up correctly, DrakX then asks you if the configuration
suits you. It will also propose to change it by displaying a list of valid
modes it could find, asking you to select one.

As a last resort, if you still cannot get X to work, choose \"Change
graphics card\", select \"Unlisted card\", and when prompted on which
server you want, choose \"FBDev\". This is a failsafe option which works
with any modern graphics card. Then choose \"Test again\" to be sure."),

configureXxdm => 
__("Finally, you will be asked whether you want to see the graphical interface
at boot. Note this question will be asked even if you chose not to test the
configuration. Obviously, you want to answer \"No\" if your machine is to
act as a server, or if you were not successful in getting the display
configured."),

createBootdisk => 
__("The Mandrake Linux CD-ROM has a built-in rescue mode. You can access it by
booting from the CD-ROM, press the >>F1<< key at boot and type >>rescue<<
at the prompt. But in case your computer cannot boot from the CD-ROM, you
should come back to this step for help in at least two situations:

 * when installing the boot loader, DrakX will rewrite the boot sector (MBR)
of your main disk (unless you are using another boot manager) so that you
can start up with either Windows or GNU/Linux (assuming you have Windows in
your system). If you need to reinstall Windows, the Microsoft install
process will rewrite the boot sector, and then you will not be able to
start GNU/Linux!

 * if a problem arises and you cannot start up GNU/Linux from the hard disk,
this floppy disk will be the only means of starting up GNU/Linux. It
contains a fair number of system tools for restoring a system, which has
crashed due to a power failure, an unfortunate typing error, a typo in a
password, or any other reason.

When you click on this step, you will be asked to enter a disk inside the
drive. The floppy disk you will insert must be empty or contain data which
you do not need. You will not have to format it since DrakX will rewrite
the whole disk."),

doPartitionDisks => 
__("At this point you need to choose where on your hard drive to install your
Mandrake Linux operating system. If your hard drive is empty or if an
existing operating system is using all the space available, you will need
to partition it. Basically, partitioning a hard drive consists of logically
dividing it to create space to install your new Mandrake Linux system.

Because the effects of the partitioning process are usually irreversible,
partitioning can be intimidating and stressful if you are an inexperienced
user. Fortunately, there is a wizard which simplifies this process. Before
beginning, please consult the manual and take your time.

If you are running the install in Expert mode, you will enter DiskDrake,
the Mandrake Linux partitioning tool, which allows you to fine-tune your
partitions. See the DiskDrake chapter of the manual. From the installation
interface, you can use the wizards as described here by clicking the
\"Wizard\" button of the dialog.

If partitions have already been defined, either from a previous
installation or from another partitioning tool, simply select those to
install your Linux system.

If partitions are not defined, you will need to create them using the
wizard. Depending on your hard drive configuration, several options are
available:

 * \"Use free space\": this option will simply lead to an automatic
partitioning of your blank drive(s). You will not be prompted further.

 * \"Use existing partition\": the wizard has detected one or more existing
Linux partitions on your hard drive. If you want to use them, choose this
option.

 * \"Use the free space on the Windows partition\": if Microsoft Windows is
installed on your hard drive and takes all the space available on it, you
have to create free space for Linux data. To do that, you can delete your
Microsoft Windows partition and data (see \"Erase entire disk\" or \"Expert
mode\" solutions) or resize your Microsoft Windows partition. Resizing can
be performed without the loss of any data. This solution is recommended if
you want to use both Mandrake Linux and Microsoft Windows on same computer.

   Before choosing this option, please understand that after this procedure,
the size of your Microsoft Windows partition will be smaller than at the
present time. You will have less free space under Microsoft Windows to
store your data or to install new software.

 * \"Erase entire disk\": if you want to delete all data and all partitions
present on your hard drive and replace them with your new Mandrake Linux
system, choose this option. Be careful with this solution because you will
not be able to revert your choice after confirmation.

   !! If you choose this option, all data on your disk will be lost. !!

 * \"Remove Windows\": this will simply erase everything on the drive and
begin fresh, partitioning everything from scratch. All data on your disk
will be lost.

   !! If you choose this option, all data on your disk will be lost. !!

 * \"Expert mode\": choose this option if you want to manually partition
your hard drive. Be careful - it is a powerful but dangerous choice. You
can very easily lose all your data. Hence, do not choose this unless you
know what you are doing."),

exitInstall => 
__("There you are. Installation is now complete and your GNU/Linux system is
ready to use. Just click \"OK\" to reboot the system. You can start
GNU/Linux or Windows, whichever you prefer (if you are dual-booting), as
soon as the computer has booted up again.

The \"Advanced\" button (in Expert mode only) shows two more buttons to:

 * \"generate auto-install floppy\": to create an installation floppy disk
which will automatically perform a whole installation without the help of
an operator, similar to the installation you just configured.

   Note that two different options are available after clicking the button:

    * \"Replay\". This is a partially automated install as the partitioning
step (and only this one) remains interactive.

    * \"Automated\". Fully automated install: the hard disk is completely
rewritten, all data is lost.

   This feature is very handy when installing a great number of similar
machines. See the Auto install section at our web site.

 * \"Save packages selection\"(*): saves the packages selection as made
previously. Then, when doing another installation, insert the floppy inside
the driver and run the installation going to the help screen by pressing on
the [F1] key, and by issuing >>linux defcfg=\"floppy\"<<.

(*) You need a FAT-formatted floppy (to create one under GNU/Linux, type
\"mformat a:\")"),

formatPartitions => 
__("Any partitions that have been newly defined must be formatted for use
(formatting means creating a file system).

At this time, you may wish to reformat some already existing partitions to
erase any data they contain. If you wish to do that, please select those
partitions as well.

Please note that it is not necessary to reformat all pre-existing
partitions. You must reformat the partitions containing the operating
system (such as \"/\", \"/usr\" or \"/var\") but you do not have to
reformat partitions containing data that you wish to keep (typically
\"/home\").

Please be careful when selecting partitions. After formatting, all data on
the selected partitions will be deleted and you will not be able to recover
any of them.

Click on \"OK\" when you are ready to format partitions.

Click on \"Cancel\" if you want to choose another partition for your new
Mandrake Linux operating system installation.

Click on \"Advanced\" if you wish to select partitions that will be checked
for bad blocks on the disc."),

installPackages => 
__("Your new Mandrake Linux operating system is currently being installed.
Depending on the number of packages you will be installing and the speed of
your computer, this operation could take from a few minutes to a
significant amount of time.

Please be patient."),

installUpdates => 
__("At the time you are installing Mandrake Linux, it is likely that some
packages have been updated since the initial release. Some bugfixes may
have been fixed, and security issues solved. To allow you to benefit from
this updates you are now proposed to download them from the internet.
Choose \"Yes\" if you have a working intertnet connection, or \"No\" if you
prefer to install updated packages later.

Choosing \"Yes\" displays a list of places from which updates can be
retrieved. Choose the one nearer to you. Then a packages selection tree
appears: review the selection, and press \"Install\" to retrieve and
install the selected package or \"Cancel\" to abort."),

license => 
__("Before continuing you should read carefully the terms of the license. It
covers the whole Mandrake Linux distribution, and if you do not agree with
all the terms in it, click on the \"Refuse\" button which will immediately
terminate the installation. To continue with the installation, click the
\"Accept\" button."),

miscellaneous => 
__("At this point, it is time to choose the security level desired for the
machine. As a rule of thumb, the more exposed the machine is, and the more
the data stored in it is crucial, the higher the security level should be.
However, a higher security level is generally obtained at the expenses of
easiness of use. Refer to the MSEC chapter of the ``Reference Manual'' to
get more information about the meaning of these levels.

If you do not know what to choose, keep the default option."),

partition_with_diskdrake => 
__("At this point, you need to choose what partition(s) will be used for the
installation of your Mandrake Linux system. If partitions have been already
defined, either from a previous installation of GNU/Linux or from another
partitioning tool, you can use existing partitions. Otherwise hard drive
partitions must be defined.

To create partitions, you must first select a hard drive. You can select
the disk for partitioning by clicking on \"hda\" for the first IDE drive,
\"hdb\" for the second, \"sda\" for the first SCSI drive and so on.

To partition the selected hard drive, you can use these options:

 * \"Clear all\": this option deletes all partitions on the selected hard
drive.

 * \"Auto allocate\": this option allows you to automatically create Ext2
and swap partitions in free space of your hard drive.

 * \"More\": gives access to additional features:

    * \"Save partition table\": saves the partition table to a floppy. Useful
for later partition-table recovery if necessary. It is strongly recommended
to perform this step.

    * \"Restore partition table\": allows to restore a previously saved
partition table from floppy disk.

    * \"Rescue partition table\": if your partition table is damaged, you can
try to recover it using this option. Please be careful and remember that it
can fail.

    * \"Reload partition table\": discards all changes and load your initial
partitions table.

    * \"removable media automounting\": unchecking this option will force users
to manually mount and unmount removable medias such as floppies and
CD-ROMs.

 * \"Wizard\": use this option if you wish to use a wizard to partition your
hard drive. This is recommended if you do not have a good knowledge of
partitioning.

 * \"Undo\": use this option to cancel your changes.

 * \"Toggle to normal/expert mode\": allows additional actions on partitions
(Type, options, format) and gives more information.

 * \"Done\": when you have finished partitioning your hard drive, this will
save your changes back to disc.

Note: you can reach any option using the keyboard. Navigate through the
partitions using [Tab] and [Up/Down] arrows.

When a partition is selected, you can use:

 * Ctrl-c to create a new partition (when an empty partition is selected);

 * Ctrl-d to delete a partition;

 * Ctrl-m to set the mount point.

To get information about the different filesystem types available, pease
read the chapter ext2fs from the ``Reference Manual''.

If you are installing on a PPC machine, you will want to create a small HFS
\"bootstrap\" partition of at least 1MB which will be used by the yaboot
boot loader. If you opt to make the partition a bit larger, say 50MB, you
may find it a useful place to store a spare kernel and ramdisk images for
emergency boot situations."),

resizeFATChoose => 
__("More than one Microsoft Windows partition has been detected on your hard
drive. Please choose the one you want to resize in order to install your
new Mandrake Linux operating system.

Each partition is listed as follows: \"Linux name\", \"Windows name\"
\"Capacity\".

\"Linux name\" is structured: \"hard drive type\", \"hard drive number\",
\"partition number\" (for example, \"hda1\").

\"Hard drive type\" is \"hd\" if your hard dive is an IDE hard drive and
\"sd\" if it is a SCSI hard drive.

\"Hard drive number\" is always a letter after \"hd\" or \"sd\". With IDE
hard drives:

 * \"a\" means \"master hard drive on the primary IDE controller\",

 * \"b\" means \"slave hard drive on the primary IDE controller\",

 * \"c\" means \"master hard drive on the secondary IDE controller\",

 * \"d\" means \"slave hard drive on the secondary IDE controller\".

With SCSI hard drives, an \"a\" means \"lowest SCSI ID\", a \"b\" means
\"second lowest SCSI ID\", etc.

\"Windows name\" is the letter of your hard drive under Windows (the first
disk or partition is called \"C:\")."),

resizeFATWait => 
__("Please be patient. This operation can take several minutes."),

selectInstallClass => 
__("DrakX now needs to know if you want to perform a default (\"Recommended\")
installation or if you want to have greater control (\"Expert\"). You also
have the choice of performing a new install or an upgrade of an existing
Mandrake Linux system:

 * \"Install\" Completely wipes out the old system. In fact, depending on
what currently holds your machine, you will be able to keep some old (Linux
or other) partitions unchanged.

 * \"Upgrade\" This installation class allows to simply update the packages
currently installed on your Mandrake Linux system. It keeps the current
partitions of your hard drives as well as users configuration. All other
configuration steps remain available with respect to plain installation.

 * \"Upgrade Packages Only\" This brand new class allows to upgrade an
existing Mandrake Linux system while keeping all system configuration
unchanged. Adding new packages to the current installation will be also
possible.

Depending on your knowledge of GNU/Linux, select one of the following
choices:

 * Recommended: choose this if you have never installed a GNU/Linux
operating system. The installation will be very easy and you will only be
asked a few questions.

 * Expert: if you have a good knowledge of GNU/Linux, you can choose this
installation class. The expert installation will allow you to perform a
highly customized installation. Answering some of the questions can be
difficult if you do not have a good knowledge of GNU/Linux so do not choose
this unless you know what you are doing."),

selectKeyboard => 
__("Normally, DrakX selects the right keyboard for you (depending on the
language you have chosen) and you will not even see this step. However, you
might not have a keyboard that corresponds exactly to your language: for
example, if you are an English speaking Swiss person, you may still want
your keyboard to be a Swiss keyboard. Or if you speak English but are
located in Quebec, you may find yourself in the same situation. In both
cases, you will have to go back to this installation step and select an
appropriate keyboard from the list.

Click on the \"More\" button to be presented with the complete list of
supported keyboards."),

selectLanguage => 
__("Please choose your preferred language for installation and system usage.

Clicking on the \"Advanced\" button will allow you to select other
languages to be installed on your workstation. Selecting other languages
will install the language-specific files for system documentation and
applications. For example, if you will host users from Spain on your
machine, select English as the main language in the tree view and in the
Advanced section click on the grey star corresponding to \"Spanish|Spain\".

Note that multiple languages may be installed. Once you have selected any
additional locales click the \"OK\" button to continue."),

selectMouse => 
__("By default, DrakX assumes you have a two-button mouse and will set it up
for third-button emulation. DrakX will automatically know whether it is a
PS/2, serial or USB mouse.

If you wish to specify a different type of mouse select the appropriate
type from the list provided.

If you choose a mouse other than the default you will be presented with a
mouse test screen. Use the buttons and wheel to verify that the settings
are good. If the mouse is not working correctly press the space bar or
[Return] to \"Cancel\" and choose again."),

selectSerialPort => 
__("Please select the correct port. For example, the \"COM1\" port under
Windows is named \"ttyS0\" under GNU/Linux."),

setRootPassword => 
__("This is the most crucial decision point for the security of your GNU/Linux
system: you have to enter the \"root\" password. \"root\" is the system
administrator and is the only one authorized to make updates, add users,
change the overall system configuration, and so on. In short, \"root\" can
do everything! That is why you must choose a password that is difficult to
guess - DrakX will tell you if it is too easy. As you can see, you can
choose not to enter a password, but we strongly advise you against this if
only for one reason: do not think that because you booted GNU/Linux that
your other operating systems are safe from mistakes. Since \"root\" can
overcome all limitations and unintentionally erase all data on partitions
by carelessly accessing the partitions themselves, it is important for it
to be difficult to become \"root\".

The password should be a mixture of alphanumeric characters and at least 8
characters long. Never write down the \"root\" password - it makes it too
easy to compromise a system.

However, please do not make the password too long or complicated because
you must be able to remember it without too much effort.

The password will not be displayed on screen as you type it in. Hence, you
will have to type the password twice to reduce the chance of a typing
error. If you do happen to make the same typing error twice, this
\"incorrect\" password will have to be used the first time you connect.

In expert mode, you will be asked if you will be connecting to an
authentication server, like NIS or LDAP.

If your network uses LDAP (or NIS) protocol for authentication, select
\"LDAP\" (or \"NIS\") as authentication. If you do not know, ask your
network administrator.

If your computer is not connected to any administrated network, you will
want to choose \"Local files\" for authentication."),

setupBootloader => 
__("LILO and grub are boot loaders for GNU/Linux. This stage, normally, is
totally automated. In fact, DrakX analyzes the disk boot sector and acts
accordingly, depending on what it finds here:

 * if a Windows boot sector is found, it will replace it with a grub/LILO
boot sector. Hence, you will be able to load either GNU/Linux or another
OS;

 * if a grub or LILO boot sector is found, it will replace it with a new
one;

If in doubt, DrakX will display a dialog with various options.

 * \"Boot loader to use\": you have three choices:

    * \"GRUB\": if you prefer grub (text menu).

    * \"LILO with graphical menu\": if you prefer LILO with its graphical
interface.

    * \"LILO with text menu\": if you prefer LILO with its text menu interface.

 * \"Boot device\": in most cases, you will not change the default
(\"/dev/hda\"), but if you prefer, the boot loader can be installed on the
second hard drive (\"/dev/hdb\"), or even on a floppy disk (\"/dev/fd0\").

 * \"Delay before booting the default image\": when rebooting the computer,
this is the delay granted to the user to choose - in the boot loader menu,
another boot entry than the default one.

!! Beware that if you choose not to install a boot loader (by selecting
\"Cancel\" here), you must ensure that you have a way to boot your Mandrake
Linux system! Also be sure you know what you do before changing any of the
options. !!

Clicking the \"Advanced\" button in this dialog will offer many advanced
options, which are reserved to the expert user.

After you have configured the general bootloader parameters, you are
presented the list of boot options that will be available at boot time.

If there is another operating system installed on your machine, it will be
automatically added to the boot menu. Here, you can choose to fine-tune the
existing options. Select an entry and click \"Modify\" to modify or remove
it; \"Add\" creates a new entry; and \"Done\" goes on to the next
installation step."),

setupBootloaderAddEntry => 
__("LILO (the LInux LOader) and grub are boot loaders: they are able to boot
either GNU/Linux or any other operating system present on your computer.
Normally, these other operating systems are correctly detected and
installed. If this is not the case, you can add an entry by hand in this
screen. Be careful to choose the correct parameters.

You may also not want to give access to these other operating systems to
anyone. In which case, you can delete the corresponding entries. But then,
you will need a boot disk in order to boot those other operating systems!"),

setupBootloaderBeginner => 
__("You must indicate where you wish to place the information required to boot
to GNU/Linux.

Unless you know exactly what you are doing, choose \"First sector of drive
(MBR)\"."),

setupDefaultSpooler => 
__("Here we select a printing system for your computer to use. Other OSes may
offer you one, but Mandrake offers three.

 * \"pdq\" - which means ``print, don't queue'', is the choice if you have a
direct connection to your printer and you want to be able to panic out of
printer jams, and you do not have any networked printers. It will handle
only very simple network cases and is somewhat slow for networks. Pick
\"pdq\" if this is your maiden voyage to GNU/Linux. You can change your
choices after install by running PrinterDrake from the Mandrake Control
Center and clicking the expert button.

 * \"CUPS\" - ``Common Unix Printing System'' is excellent at printing to
your local printer and also halfway round the planet. It is simple and can
act like a server or a client for the ancient \"lpd\" printing system, so
it is compatible with the systems that went before. It can do many tricks,
but the basic setup is almost as easy as \"pdq\". If you need this to
emulate an \"lpd\" server, you must turn on the \"cups-lpd\" daemon. It has
graphical front-ends for printing or choosing printer options.

 * \"lprNG\" - ``line printer daemon New Generation''. This system can do
approximately the same things the others can do, but it will print to
printers mounted on a Novell Network, because it supports IPX protocol, and
it can print directly to shell commands. If you have need of Novell or
printing to commands without using a separate pipe construct, use lprNG.
Otherwise, CUPS is preferable as it is simpler and better at working over
networks."),

setupSCSI => 
__("DrakX is now detecting any IDE devices present in your computer. It will
also scan for one or more PCI SCSI card(s) on your system. If a SCSI card
is found, DrakX will automatically install the appropriate driver.

Because hardware detection will sometimes not detect a piece of hardware,
DrakX will ask you to confirm if a PCI SCSI card is present. Click \"Yes\"
if you know that there is a SCSI card installed in your machine. You will
be presented a list of SCSI cards to choose from. Click \"No\" if you have
no SCSI hardware. If you are unsure you can check the list of hardware
detected in your machine by selecting \"See hardware info\" and clicking
\"OK\". Examine the list of hardware and then click on the \"OK\" button to
return to the SCSI interface question.

If you have to manually specify your adapter, DrakX will ask if you want to
specify options for it. You should allow DrakX to probe the hardware for
the card-specific options that the hardware needs to initialize. This
usually works well.

If DrakX is not able to probe for the options that need to be passed, you
will need to manually provide options to the driver. Please review the
``User Guide'' (chapter 3, section \"Collecting Information on Your
Hardware\") for hints on retrieving the parameters required from hardware
documentation, from the manufacturer's web site (if you have Internet
access) or from Microsoft Windows (if you used this hardware with Windows
on your system)."),

setupYabootAddEntry => 
__("You can add additional entries for yaboot, either for other operating
systems, alternate kernels, or for an emergency boot image.

For other OS's, the entry consists only of a label and the root partition.

For Linux, there are a few possible options:

 * Label: this is simply the name you will have to type at the yaboot prompt
to select this boot option.

 * Image: this would be the name of the kernel to boot. Typically, vmlinux
or a variation of vmlinux with an extension.

 * Root: the \"root\" device or \"/\" for your Linux installation.

 * Append: on Apple hardware, the kernel append option is used quite often
to assist in initializing video hardware, or to enable keyboard mouse
button emulation for the often lacking 2nd and 3rd mouse buttons on a stock
Apple mouse. The following are some examples:

         video=aty128fb:vmode:17,cmode:32,mclk:71 adb_buttons=103,111 hda=autotune

         video=atyfb:vmode:12,cmode:24 adb_buttons=103,111

 * Initrd: this option can be used either to load initial modules, before
the boot device is available, or to load a ramdisk image for an emergency
boot situation.

 * Initrd-size: the default ramdisk size is generally 4,096 bytes. If you
need to allocate a large ramdisk, this option can be used.

 * Read-write: normally the \"root\" partition is initially brought up in
read-only, to allow a file system check before the system becomes \"live\".
Here, you can override this option.

 * NoVideo: should the Apple video hardware prove to be exceptionally
problematic, you can select this option to boot in \"novideo\" mode, with
native frame buffer support.

 * Default: selects this entry as being the default Linux selection,
selectable by just pressing ENTER at the yaboot prompt. This entry will
also be highlighted with a \"*\", if you press [Tab] to see the boot
selections."),

setupYabootGeneral => 
__("Yaboot is a boot loader for NewWorld MacIntosh hardware. It is able to boot
either GNU/Linux, MacOS or MacOSX if present on your computer. Normally,
these other operating systems are correctly detected and installed. If this
is not the case, you can add an entry by hand in this screen. Be careful as
to choose the correct parameters.

Yaboot's main options are:

 * Init Message: a simple text message that is displayed before the boot
prompt.

 * Boot Device: indicate where you want to place the information required to
boot to GNU/Linux. Generally, you setup a bootstrap partition earlier to
hold this information.

 * Open Firmware Delay: unlike LILO, there are two delays available with
yaboot. The first delay is measured in seconds and at this point, you can
choose between CD, OF boot, MacOS or Linux.

 * Kernel Boot Timeout: this timeout is similar to the LILO boot delay.
After selecting Linux, you will have this delay in 0.1 second before your
default kernel description is selected.

 * Enable CD Boot?: checking this option allows you to choose \"C\" for CD
at the first boot prompt.

 * Enable OF Boot?: checking this option allows you to choose \"N\" for Open
Firmware at the first boot prompt.

 * Default OS: you can select which OS will boot by default when the Open
Firmware Delay expires."),

summary => 
__("Here are presented various parameters concerning your machine. Depending on
your installed hardware, you may - or not, see the following entries:

 * \"Mouse\": check the current mouse configuration and click on the button
to change it if necessary.

 * \"Keyboard\": check the current keyboard map configuration and click on
the button to change that if necessary.

 * \"Timezone\": DrakX, by default, guesses your time zone from the language
you have chosen. But here again, as for the choice of a keyboard, you may
not be in the country for which the chosen language should correspond.
Hence, you may need to click on the \"Timezone\" button in order to
configure the clock according to the time zone you are in.

 * \"Printer\": clicking on the \"No Printer\" button will open the printer
configuration wizard.

 * \"Sound card\": if a sound card is detected on your system, it is
displayed here. No modification possible at installation time.

 * \"TV card\": if a TV card is detected on your system, it is displayed
here. No modification possible at installation time.

 * \"ISDN card\": if an ISDN card is detected on your system, it is
displayed here. You can click on the button to change the parameters
associated to it."),

takeOverHdChoose => 
__("Choose the hard drive you want to erase to install your new Mandrake Linux
partition. Be careful, all data present on it will be lost and will not be
recoverable!"),

takeOverHdConfirm => 
__("Click on \"OK\" if you want to delete all data and partitions present on
this hard drive. Be careful, after clicking on \"OK\", you will not be able
to recover any data and partitions present on this hard drive, including
any Windows data.

Click on \"Cancel\" to cancel this operation without losing any data and
partitions present on this hard drive."),
);
