package help;
use common;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.

our %steps = (

acceptLicense => 
N_("Before continuing, you should carefully read the terms of the license. It
covers the entire Mandrake Linux distribution. If you do agree with all the
terms in it, check the \"Accept\" box. If not, simply turn off your
computer."),

addUser => 
N_("GNU/Linux is a multi-user system, meaning each user can have their own
preferences, their own files and so on. You can read the ``Starter Guide''
to learn more about multi-user systems. But unlike \"root\", which is the
system administrator, the users you add at this point will not be
authorized to change anything except their own files and their own
configuration, protecting the system from unintentional or malicious
changes that impact the system as a whole. You will have to create at least
one regular user for yourself -- this is the account which you should use
for routine, day-to-day use. Although it is very easy to log in as \"root\"
to do anything and everything, it may also be very dangerous! A mistake
could mean that your system would not work any more. If you make a serious
mistake as a regular user, the worst that will happen is that you will lose
some information, but not affect the entire system.

The first field asks you for a real name. Of course, this is not mandatory
-- you can actually enter whatever you like. DrakX will use the first word
you typed in and copy it to the \"User name\" field, which is the name this
user will enter to log onto the system. If you like, you may override the
default and change the username. The next step is to enter a password. From
a security point of view, a non-privileged (regular) user password is not
as crucial as the \"root\" password, but that is no reason to neglect it by
making it blank or too simple: after all, your files could be the ones at
risk.

Once you click on \"Accept user\", you can add other users. Add a user for
each one of your friends: your father or your sister, for example. Click
\"Next ->\" when you have finished adding users.

Clicking the \"Advanced\" button allows you to change the default \"shell\"
for that user (bash by default).

When you are finished adding all users, you will be asked to choose a user
that can automatically log into the system when the computer boots up. If
you are interested in that feature (and do not care much about local
security), choose the desired user and window manager, then click \"Next
->\". If you are not interested in this feature, uncheck the \"Do you want
to use this feature?\" box."),

ask_mntpoint_s => 
N_("Here are Listed the existing Linux partitions detected on your hard drive.
You can keep the choices made by the wizard, since they are good for most
common installations. If you make any changes, you must at least define a
root partition (\"/\"). Do not choose too small a partition or you will not
be able to install enough software. If you want to store your data on a
separate partition, you will also need to create a \"/home\" partition
(only possible if you have more than one Linux partition available).

Each partition is listed as follows: \"Name\", \"Capacity\".

\"Name\" is structured: \"hard drive type\", \"hard drive number\",
\"partition number\" (for example, \"hda1\").

\"Hard drive type\" is \"hd\" if your hard drive is an IDE hard drive and
\"sd\" if it is a SCSI hard drive.

\"Hard drive number\" is always a letter after \"hd\" or \"sd\". For IDE
hard drives:

 * \"a\" means \"master hard drive on the primary IDE controller\";

 * \"b\" means \"slave hard drive on the primary IDE controller\";

 * \"c\" means \"master hard drive on the secondary IDE controller\";

 * \"d\" means \"slave hard drive on the secondary IDE controller\".

With SCSI hard drives, an \"a\" means \"lowest SCSI ID\", a \"b\" means
\"second lowest SCSI ID\", etc."),

chooseCd => 
N_("The Mandrake Linux installation is distributed on several CD-ROMs. DrakX
knows if a selected package is located on another CD-ROM so it will eject
the current CD and ask you to insert the correct CD as required."),

choosePackages => 
N_("It is now time to specify which programs you wish to install on your
system. There are thousands of packages available for Mandrake Linux, and
to make it simpler to manage the packages have been placed into groups of
similar applications.

Packages are sorted into groups corresponding to a particular use of your
machine. Mandrake Linux has four predefined installations available. You
can think of these installation classes as containers for various packages.
You can mix and match applications from the various containers, so a
``Workstation'' installation can still have applications from the
``Development'' container installed.

 * \"Workstation\": if you plan to use your machine as a workstation,
select one or more of the applications that are in the workstation
container.

 * \"Development\": if plan on using your machine for programming, choose
the appropriate packages from the container.

 * \"Server\": if your machine is intended to be a server, select which of
the more common services you wish to install on your machine.

 * \"Graphical Environment\": this is where you will choose your preferred
graphical environment. At least one must be selected if you want to have a
graphical interface available.

Moving the mouse cursor over a group name will display a short explanatory
text about that group. If you unselect all groups when performing a regular
installation (as opposed to an upgrade), a dialog will pop up proposing
different options for a minimal installation:

 * \"With X\": install the minimum number of packages possible to have a
working graphical desktop.

 * \"With basic documentation\": installs the base system plus basic
utilities and their documentation. This installation is suitable for
setting up a server.

 * \"Truly minimal install\": will install the absolute minimum number of
packages necessary to get a working Linux system. With this installation
you will only have a command line interface. The total size of this
installation is 65 megabytes.

You can check the \"Individual package selection\" box, which is useful if
you are familiar with the packages being offered or if you want to have
total control over what will be installed.

If you started the installation in \"Upgrade\" mode, you can unselect all
groups to avoid installing any new package. This is useful for repairing or
updating an existing system."),

choosePackagesTree => 
N_("If you told the installer that you wanted to individually select packages,
it will present a tree containing all packages classified by groups and
subgroups. While browsing the tree, you can select entire groups,
subgroups, or individual packages.

Whenever you select a package on the tree, a description appears on the
right to let you know the purpose of the package.

!! If a server package has been selected, either because you specifically
chose the individual package or because it was part of a group of packages,
you will be asked to confirm that you really want those servers to be
installed. By default Mandrake Linux will automatically start any installed
services at boot time. Even if they are safe and have no known issues at
the time the distribution was shipped, it is entirely possible that that
security holes are discovered after this version of Mandrake Linux was
finalized. If you do not know what a particular service is supposed to do
or why it is being installed, then click \"No\". Clicking \"Yes \" will
install the listed services and they will be started automatically by
default during boot. !!

The \"Automatic dependencies\" option is used to disable the warning dialog
which appears whenever the installer automatically selects a package to
resolve a dependency issue. Some packages have relationships between each
other such that installation of a package requires that some other program
is already installed. The installer can determine which packages are
required to satisfy a dependency to successfully complete the installation.

The tiny floppy disk icon at the bottom of the list allows you to load a
package list created during a previous installation. This is useful if you
have a number of machines that you wish to configure identically. Clicking
on this icon will ask you to insert a floppy disk previously created at the
end of another installation. See the second tip of last step on how to
create such a floppy."),

configureNetwork => 
N_("You will now set up your Internet/network connection. If you wish to
connect your computer to the Internet or to a local network, click \"Next
->\". Mandrake Linux will attempt to autodetect network devices and modems.
If this detection fails, uncheck the \"Use auto detection\" box. You may
also choose not to configure the network, or to do it later, in which case
clicking the \"Cancel\" button will take you to the next step.

When configuring your network, the available connections options are:
traditional modem, ISDN modem, ADSL connection, cable modem, and finally a
simple LAN connection (Ethernet).

We will not detail each configuration option - just make sure that you have
all the parameters, such as IP address, default gateway, DNS servers, etc.
from your Internet Service Provider or system administrator.

You can consult the ``Starter Guide'' chapter about Internet connections
for details about the configuration, or simply wait until your system is
installed and use the program described there to configure your connection."),

configurePrinter => 
N_("\"Printer\": clicking on the \"No Printer\" button will open the printer
configuration wizard. Consult the corresponding chapter of the ``Starter
Guide'' for more information on how to setup a new printer. The interface
presented there is similar to the one used during installation."),

configureServices => 
N_("This step is used to choose which services you wish to start at boot time.

DrakX will list all the services available on the current installation.
Review each one carefully and uncheck those which are not always needed at
boot time.

A short explanatory text will be displayed about a service when it is
selected. However, if you are not sure whether a service is useful or not,
it is safer to leave the default behavior.

!! At this stage, be very careful if you intend to use your machine as a
server: you will probably not want to start any services that you do not
need. Please remember that several services can be dangerous if they are
enabled on a server. In general, select only the services you really need.
!!"),

configureTimezoneGMT => 
N_("GNU/Linux manages time in GMT (Greenwich Mean Time) and translates it to
local time according to the time zone you selected. If the clock on your
motherboard is set to local time, you may deactivate this by unselecting
\"Hardware clock set to GMT \", which will let GNU/Linux know that the
system clock and the hardware clock are in the same timezone. This is
useful when the machine also hosts another operating system like Windows.

The \"Automatic time synchronization \" option will automatically regulate
the clock by connecting to a remote time server on the Internet. For this
feature to work, you must have a working Internet connection. It is best to
choose a time server located near you. This option actually installs a time
server that can used by other machines on your local network."),

configureX_card_list => 
N_("Graphic Card

   The installer can normally automatically detect and configure the
graphic card installed on your machine. If it is not the case, you can
choose in this list the card you actually own.

   In the case that different servers are available for your card, with or
without 3D acceleration, you are then proposed to choose the server that
best suits your needs."),

configureX_chooser => 
N_("X (for X Window System) is the heart of the GNU/Linux graphical interface
on which all the graphical environments (KDE, GNOME, AfterStep,
WindowMaker, etc.) bundled with Mandrake Linux rely upon.

You will be presented the list of different parameters to change to get an
optimal graphical display: Graphic Card

   The installer can normally automatically detect and configure the
graphic card installed on your machine. If it is not the case, you can
choose in this list the card you actually own.

   In the case that different servers are available for your card, with or
without 3D acceleration, you are then proposed to choose the server that
best suits your needs.



Monitor

   The installer can normally automatically detect and configure the
monitor connected to your machine. If it is not the case, you can choose in
this list the monitor you actually own.



Resolution

   You can choose here resolutions and color depth between those available
for your hardware. Choose the one that best suit your needs (you will be
able to change that after installation though). Asample of the chosen
configuration is shown in the monitor.



Test

   the system will try to open a graphical screen at the desired
resolution. If you can see the message during the test and answer \"Yes\",
then DrakX will proceed to the next step. If you cannot see the message, it
means that some part of the autodetected configuration was incorrect and
the test will automatically end after 12 seconds, bringing you back to the
menu. Change settings until you get a correct graphical display.



Options

   You can here choose whether you want to have your machine automatically
switch to a graphical interface at boot. Obviously, you want to check
\"No\" if your machine is to act as a server, or if you were not successful
in getting the display configured."),

configureX_monitor => 
N_("Monitor

   The installer can normally automatically detect and configure the
monitor connected to your machine. If it is not the case, you can choose in
this list the monitor you actually own."),

configureX_resolution => 
N_("Resolution

   You can choose here resolutions and color depth between those available
for your hardware. Choose the one that best suit your needs (you will be
able to change that after installation though). Asample of the chosen
configuration is shown in the monitor."),

configureX_xfree_and_glx => 
N_("In the case that different servers are available for your card, with or
without 3D acceleration, you are then proposed to choose the server that
best suits your needs."),

configureXxdm => 
N_("Finally, you will be asked whether you want to see the graphical interface
at boot. Note this question will be asked even if you chose not to test the
configuration. Obviously, you want to answer \"No\" if your machine is to
act as a server, or if you were not successful in getting the display
configured."),

createBootdisk => 
N_("Checking \"Create a boot disk\" allows you to have a rescue bot media
handy.

The Mandrake Linux CD-ROM has a built-in rescue mode. You can access it by
booting the CD-ROM, pressing the >> F1<< key at boot and typing >>rescue<<
at the prompt. If your computer cannot boot from the CD-ROM, there are at
least two situations where having a boot floppy is critical:

 * when installing the bootloader, DrakX will rewrite the boot sector (MBR)
of your main disk (unless you are using another boot manager), to allow you
to start up with either Windows or GNU/Linux (assuming you have Windows on
your system). If at some point you need to reinstall Windows, the Microsoft
install process will rewrite the boot sector and remove your ability to
start GNU/Linux!

 * if a problem arises and you cannot start GNU/Linux from the hard disk,
this floppy will be the only means of starting up GNU/Linux. It contains a
fair number of system tools for restoring a system that has crashed due to
a power failure, an unfortunate typing error, a forgotten root password, or
any other reason.

If you say \"Yes\", you will be asked to insert a disk in the drive. The
floppy disk must be blank or have non-critical data on it - DrakX will
format the floppy and will rewrite the whole disk."),

doPartitionDisks => 
N_("At this point, you need to decide where you want to install the Mandrake
Linux operating system on your hard drive. If your hard drive is empty or
if an existing operating system is using all the available space you will
have to partition the drive. Basically, partitioning a hard drive consists
of logically dividing it to create the space needed to install your new
Mandrake Linux system.

Because the process of partitioning a hard drive is usually irreversible
and can lead to lost data if there is an existing operating system already
installed on the drive, partitioning can be intimidating and stressful if
you are an inexperienced user. Fortunately, DrakX includes a wizard which
simplifies this process. Before continuing with this step, read through the
rest of this section and above all, take your time.

Depending on your hard drive configuration, several options are available:

 * \"Use free space\": this option will perform an automatic partitioning
of your blank drive(s). If you use this option there will be no further
prompts.

 * \"Use existing partition\": the wizard has detected one or more existing
Linux partitions on your hard drive. If you want to use them, choose this
option. You will then be asked to choose the mount points associated with
each of the partitions. The legacy mount points are selected by default,
and for the most part it's a good idea to keep them.

 * \"Use the free space on the Windows partition\": if Microsoft Windows is
installed on your hard drive and takes all the space available on it, you
have to create free space for Linux data. To do so, you can delete your
Microsoft Windows partition and data (see `` Erase entire disk'' solution)
or resize your Microsoft Windows FAT partition. Resizing can be performed
without the loss of any data, provided you previously defragment the
Windows partition and that it uses the FAT format. Backing up your data is
strongly recommended.. Using this option is recommended if you want to use
both Mandrake Linux and Microsoft Windows on the same computer.

   Before choosing this option, please understand that after this
procedure, the size of your Microsoft Windows partition will be smaller
then when you started. You will have less free space under Microsoft
Windows to store your data or to install new software.

 * \"Erase entire disk\": if you want to delete all data and all partitions
present on your hard drive and replace them with your new Mandrake Linux
system, choose this option. Be careful, because you will not be able to
undo your choice after you confirm.

   !! If you choose this option, all data on your disk will be deleted. !!

 * \"Remove Windows\": this will simply erase everything on the drive and
begin fresh, partitioning everything from scratch. All data on your disk
will be lost.

   !! If you choose this option, all data on your disk will be lost. !!

 * \"Custom disk partitionning\": choose this option if you want to
manually partition your hard drive. Be careful -- it is a powerful but
dangerous choice and you can very easily lose all your data. That's why
this option is really only recommended if you have done something like this
before and have some experience. For more instructions on how to use the
DiskDrake utility, refer to the ``Managing Your Partitions '' section in
the ``Starter Guide''."),

exitInstall => 
N_("There you are. Installation is now complete and your GNU/Linux system is
ready to use. Just click \"Next ->\" to reboot the system. The first thing
you should see after your computer has finished doing its hardware tests is
the bootloader menu, giving you the choice of which operating system to
start.

The \"Advanced\" button (in Expert mode only) shows two more buttons to:

 * \"generate auto-install floppy\": to create an installation floppy disk
that will automatically perform a whole installation without the help of an
operator, similar to the installation you just configured.

   Note that two different options are available after clicking the button:

    * \"Replay\". This is a partially automated installation. The
partitioning step is the only interactive procedure.

    * \"Automated\". Fully automated installation: the hard disk is
completely rewritten, all data is lost.

   This feature is very handy when installing a number of similar machines.
See the Auto install section on our web site for more information.

 * \"Save packages selection\"(*): saves a list of the package selected in
this installation. To use this selection with another installation, insert
the floppy and start the installation. At the prompt, press the [F1] key
and type >>linux defcfg=\"floppy\" <<.

(*) You need a FAT-formatted floppy (to create one under GNU/Linux, type
\"mformat a:\")"),

formatPartitions => 
N_("Any partitions that have been newly defined must be formatted for use
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
it.

Click on \"Next ->\" when you are ready to format partitions.

Click on \"<- Previous\" if you want to choose another partition for your
new Mandrake Linux operating system installation.

Click on \"Advanced\" if you wish to select partitions that will be checked
for bad blocks on the disk."),

installUpdates => 
N_("At the time you are installing Mandrake Linux, it is likely that some
packages have been updated since the initial release. Bugs may have been
fixed, security issues resolved. To allow you to benefit from these
updates, you are now able to download them from the Internet. Choose
\"Yes\" if you have a working Internet connection, or \"No\" if you prefer
to install updated packages later.

Choosing \"Yes\" displays a list of places from which updates can be
retrieved. Choose the one nearest you. A package-selection tree will
appear: review the selection, and press \"Install\" to retrieve and install
the selected package( s), or \"Cancel\" to abort."),

miscellaneous => 
N_("At this point, DrakX will allow you to choose the security level desired
for the machine. As a rule of thumb, the security level should be set
higher if the machine will contain crucial data, or if it will be a machine
directly exposed to the Internet. The trade-off of a higher security level
is generally obtained at the expense of ease of use. Refer to the \"msec\"
chapter of the ``Command Line Manual'' to get more information about the
meaning of these levels.

If you do not know what to choose, keep the default option."),

partition_with_diskdrake => 
N_("At this point, you need to choose which partition(s) will be used for the
installation of your Mandrake Linux system. If partitions have already been
defined, either from a previous installation of GNU/Linux or from another
partitioning tool, you can use existing partitions. Otherwise, hard drive
partitions must be defined.

To create partitions, you must first select a hard drive. You can select
the disk for partitioning by clicking on ``hda'' for the first IDE drive,
``hdb'' for the second, ``sda'' for the first SCSI drive and so on.

To partition the selected hard drive, you can use these options:

 * \"Clear all\": this option deletes all partitions on the selected hard
drive

 * \"Auto allocate\": this option enables you to automatically create ext3
and swap partitions in free space of your hard drive

\"More\": gives access to additional features:

 * \"Save partition table\": saves the partition table to a floppy. Useful
for later partition-table recovery, if necessary. It is strongly
recommended that you perform this step.

 * \"Restore partition table\": allows you to restore a previously saved
partition table from a floppy disk.

 * \"Rescue partition table\": if your partition table is damaged, you can
try to recover it using this option. Please be careful and remember that it
doesn't always work.

 * \"Reload partition table\": discards all changes and reloads the
partition table that was originally on the hard drive.

 * \"Removable media automounting\": unchecking this option will force
users to manually mount and unmount removable medias such as floppies and
CD-ROMs.

 * \"Wizard\": use this option if you wish to use a wizard to partition
your hard drive. This is recommended if you do not have a good
understanding of partitioning.

 * \"Undo\": use this option to cancel your changes.

 * \"Toggle to normal/expert mode\": allows additional actions on
partitions (type, options, format) and gives more information about the
hard drive.

 * \"Done\": when you are finished partitioning your hard drive, this will
save your changes back to disk.

When defining the size of a partition, you can finely set the partition
size by using the Arrow keys of your keyboard.

Note: you can reach any option using the keyboard. Navigate through the
partitions using [Tab] and the [Up/Down] arrows.

When a partition is selected, you can use:

 * Ctrl-c to create a new partition (when an empty partition is selected)

 * Ctrl-d to delete a partition

 * Ctrl-m to set the mount point

To get information about the different file system types available, please
read the ext2FS chapter from the ``Reference Manual''.

If you are installing on a PPC machine, you will want to create a small HFS
``bootstrap'' partition of at least 1MB which will be used by the yaboot
bootloader. If you opt to make the partition a bit larger, say 50MB, you
may find it a useful place to store a spare kernel and ramdisk images for
emergency boot situations."),

resizeFATChoose => 
N_("More than one Microsoft partition has been detected on your hard drive.
Please choose the one you want to resize in order to install your new
Mandrake Linux operating system.

Each partition is listed as follows: \"Linux name\", \"Windows name\"
\"Capacity\".

\"Linux name\" is structured: \"hard drive type\", \"hard drive number\",
\"partition number\" (for example, \"hda1\").

\"Hard drive type\" is \"hd\" if your hard dive is an IDE hard drive and
\"sd\" if it is a SCSI hard drive.

\"Hard drive number\" is always a letter after \"hd\" or \"sd\". With IDE
hard drives:

 * \"a\" means \"master hard drive on the primary IDE controller\";

 * \"b\" means \"slave hard drive on the primary IDE controller\";

 * \"c\" means \"master hard drive on the secondary IDE controller\";

 * \"d\" means \"slave hard drive on the secondary IDE controller\".

With SCSI hard drives, an \"a\" means \"lowest SCSI ID\", a \"b\" means
\"second lowest SCSI ID\", etc.

\"Windows name\" is the letter of your hard drive under Windows (the first
disk or partition is called \"C:\")."),

selectCountry => 
N_("\"Country\": check the current country selection. If you are not in this
country, click on the button and choose another one."),

selectInstallClass => 
N_("This step is activated only if an old GNU/Linux partition has been found on
your machine.

DrakX now needs to know if you want to perform a new install or an upgrade
of an existing Mandrake Linux system:

 * \"Install\": For the most part, this completely wipes out the old
system. If you wish to change how your hard drives are partitioned, or
change the file system, you should use this option. However, depending on
your partitioning scheme, you can prevent some of your existing data from
being over- written.

 * \"Upgrade\": this installation class allows you to update the packages
currently installed on your Mandrake Linux system. Your current
partitioning scheme and user data is not altered. Most of other
configuration steps remain available, similar to a standard installation.

Using the ``Upgrade'' option should work fine on Mandrake Linux systems
running version \"8.1\" or later. Performing an Upgrade on versions prior
to Mandrake Linux version \"8.1\" is not recommended."),

selectKeyboard => 
N_("Depending on the default language you chose in Section , DrakX will
automatically select a particular type of keyboard configuration. However,
you might not have a keyboard that corresponds exactly to your language:
for example, if you are an English speaking Swiss person, you may have a
Swiss keyboard. Or if you speak English but are located in Quebec, you may
find yourself in the same situation where your native language and keyboard
do not match. In either case, this installation step will allow you to
select an appropriate keyboard from a list.

Click on the \"More \" button to be presented with the complete list of
supported keyboards.

If you choose a keyboard layout based on a non-Latin alphabet, the next
dialog will allow you to choose the key binding that will switch the
keyboard between the Latin and non-Latin layouts."),

selectLanguage => 
N_("Your choice of preferred language will affect the language of the
documentation, the installer and the system in general. Select first the
region you are located in, and then the language you speak.

Clicking on the \"Advanced\" button will allow you to select other
languages to be installed on your workstation, thereby installing the
language-specific files for system documentation and applications. For
example, if you will host users from Spain on your machine, select English
as the default language in the tree view and \"Espanol\" in the Advanced
section.

Note that you're not limited to choosing a single additional language. Once
you have selected additional locales, click the \"Next ->\" button to
continue.

To switch between the various languages installed on the system, you can
launch the \"/usr/sbin/localedrake\" command as \"root\" to change the
language used by the entire system. Running the command as a regular user
will only change the language settings for that particular user."),

selectMouse => 
N_("Usually, DrakX has no problems detecting the number of buttons on your
mouse. If it does, it assumes you have a two-button mouse and will
configure it for third-button emulation. The third-button mouse button of a
two-button mouse can be ``pressed'' by simultaneously clicking the left and
right mouse buttons. DrakX will automatically know whether your mouse uses
a PS/2, serial or USB interface.

If for some reason you wish to specify a different type of mouse, select it
from the provided list.

If you choose a mouse other than the default, a test screen will be
displayed. Use the buttons and wheel to verify that the settings are
correct and that the mouse is working correctly. If the mouse is not
working well, press the space bar or [Return] key to cancel the test and to
go back to the list of choices.

Wheel mice are occasionally not detected automatically, so you will need to
select your mouse from a list. Be sure to select the one corresponding to
the port that your mouse is attached to. After selecting a mouse and
pressing the \"Next ->\" button, a mouse image is displayed on-screen.
Scroll the mouse wheel to ensure that it is activated correctly. Once you
see the on-screen scroll wheel moving as you scroll your mouse wheel, test
the buttons and check that the mouse pointer moves on-screen as you move
your mouse."),

selectSerialPort => 
N_("Please select the correct port. For example, the \"COM1\" port under
Windows is named \"ttyS0\" under GNU/Linux."),

setRootPassword => 
N_("This is the most crucial decision point for the security of your GNU/Linux
system: you have to enter the \"root\" password. \"Root\" is the system
administrator and is the only one authorized to make updates, add users,
change the overall system configuration, and so on. In short, \"root\" can
do everything! That is why you must choose a password that is difficult to
guess - DrakX will tell you if the password that you chose too easy. As you
can see, you are not forced to enter a password, but we strongly advise you
against. GNU/Linux is as prone to operator error as any other operating
system. Since \"root\" can overcome all limitations and unintentionally
erase all data on partitions by carelessly accessing the partitions
themselves, it is important that it be difficult to become \"root\".

The password should be a mixture of alphanumeric characters and at least 8
characters long. Never write down the \"root\" password -- it makes it too
easy to compromise a system.

One caveat -- do not make the password too long or complicated because you
must be able to remember it!

The password will not be displayed on screen as you type it in. To reduce
the chance of a blind typing error you will need to enter the password
twice. If you do happen to make the same typing error twice, this
``incorrect'' password will have to be used the first time you connect.

If you wish access to this computer to be controlled by an authentication
server, clisk the \"Advanced\" button.

If your network uses either LDAP, NIS, or PDC Windows Domain authentication
services, select the appropriate one as \"authentication\". If you do not
know which to use, ask your network administrator.

If you happen to have problems with reminding passwords, you can choose to
have \"No password\", if your computer won't be connected to the Internet,
and if you trust anybody having access to it."),

setupBootloader => 
N_("This dialog allows to finely tune your bootloader:

 * \"Bootloader to use\": there are three choices for your bootloader:

    * \"GRUB\": if you prefer grub (text menu).

    * \"LILO with text menu\": if you prefer LILO with its text menu
interface.

    * \"LILO with graphical menu\": if you prefer LILO with its graphical
interface.

 * \"Boot device\": in most cases, you will not change the default
(\"/dev/hda\"), but if you prefer, the bootloader can be installed on the
second hard drive (\"/dev/hdb\"), or even on a floppy disk (\"/dev/fd0\");

 * \"Delay before booting the default image\": after a boot or a reboot of
the computer, this is the delay given to the user at the console to select
a boot entry other than the default.

!! Beware that if you choose not to install a bootloader (by selecting
\"Skip\"), you must ensure that you have a way to boot your Mandrake Linux
system! Be sure you know what you do before changing any of the options. !!

Clicking the \"Advanced\" button in this dialog will offer advanced options
that are reserved for the expert user."),

setupBootloaderAddEntry => 
N_("After you have configured the general bootloader parameters, the list of
boot options that will be available at boot time will be displayed.

If there are other operating systems installed on your machine they will
automatically be added to the boot menu. You can fine-tune the existing
options by clicking \"Add\" to create a new entry; selecting an entry and
clicking \"Modify\" or \"Remove\" to modify or remove it. \"OK\" validates
your changes.

You may also not want to give access to these other operating systems to
anyone who goes to the console and reboots the machine. You can delete the
corresponding entries for the operating systems to remove them from the
bootloader menu, but you will need a boot disk in order to boot those other
operating systems!"),

setupBootloaderBeginner => 
N_("LILO and grub are GNU/Linux bootloaders. Normally, this stage is totally
automated. DrakX will analyze the disk boot sector and act according to
what it finds there:

 * if a Windows boot sector is found, it will replace it with a grub/LILO
boot sector. This way you will be able to load either GNU/Linux or another
OS.

 * if a grub or LILO boot sector is found, it will replace it with a new
one.

If it cannot make a determination, DrakX will ask you where to place the
bootloader.

\"Boot device\": in most cases, you will not change the default (\"First
sector of drive (MBR)\"), but if you prefer, the bootloader can be
installed on the second hard drive (\"/dev/hdb\"), or even on a floppy disk
(\"On Floppy\").

Checking \"Create a boot disk\" allows you to have a rescue bot media
handy.

The Mandrake Linux CD-ROM has a built-in rescue mode. You can access it by
booting the CD-ROM, pressing the >> F1<< key at boot and typing >>rescue<<
at the prompt. If your computer cannot boot from the CD-ROM, there are at
least two situations where having a boot floppy is critical:

 * when installing the bootloader, DrakX will rewrite the boot sector (MBR)
of your main disk (unless you are using another boot manager), to allow you
to start up with either Windows or GNU/Linux (assuming you have Windows on
your system). If at some point you need to reinstall Windows, the Microsoft
install process will rewrite the boot sector and remove your ability to
start GNU/Linux!

 * if a problem arises and you cannot start GNU/Linux from the hard disk,
this floppy will be the only means of starting up GNU/Linux. It contains a
fair number of system tools for restoring a system that has crashed due to
a power failure, an unfortunate typing error, a forgotten root password, or
any other reason.

If you say \"Yes\", you will be asked to insert a disk in the drive. The
floppy disk must be blank or have non-critical data on it - DrakX will
format the floppy and will rewrite the whole disk."),

setupDefaultSpooler => 
N_("Now, it's time to select a printing system for your computer. Other OSs may
offer you one, but Mandrake Linux offers two. Each of the printing systems
is best for a particular type of configuration.

 * \"pdq\" -- which is an acronym for ``print, don't queue'', is the choice
if you have a direct connection to your printer, you want to be able to
panic out of printer jams, and you do not have networked printers. (\"pdq
\" will handle only very simple network cases and is somewhat slow when
used with networks.) It's recommended that you use \"pdq \" if this is your
first experience with GNU/Linux.

 * \"CUPS\" - `` Common Unix Printing System'', is an excellent choice for
printing to your local printer or to one halfway around the planet. It is
simple to configure and can act as a server or a client for the ancient
\"lpd \" printing system, so it compatible with older operating systems
that may still need print services. While quite powerful, the basic setup
is almost as easy as \"pdq\". If you need to emulate a \"lpd\" server, make
sure to turn on the \"cups-lpd \" daemon. \"CUPS\" includes graphical
front-ends for printing or choosing printer options and for managing the
printer.

If you make a choice now, and later find that you don't like your printing
system you may change it by running PrinterDrake from the Mandrake Control
Center and clicking the expert button."),

setupSCSI => 
N_("DrakX will first detect any IDE devices present in your computer. It will
also scan for one or more PCI SCSI cards on your system. If a SCSI card is
found, DrakX will automatically install the appropriate driver.

Because hardware detection is not foolproof, DrakX will ask you if you have
a PCI SCSI installed. Clicking \" Yes\" will display a list of SCSI cards
to choose from. Click \"No\" if you know that you have no SCSI hardware in
your machine. If you're not sure, you can check the list of hardware
detected in your machine by selecting \"See hardware info \" and clicking
the \"Next ->\". Examine the list of hardware and then click on the \"Next
->\" button to return to the SCSI interface question.

If you had to manually specify your PCI SCSI adapter, DrakX will ask if you
want to configure options for it. You should allow DrakX to probe the
hardware for the card-specific options which are needed to initialize the
adapter. Most of the time, DrakX will get through this step without any
issues.

If DrakX is not able to probe for the options to automatically determine
which parameters need to be passed to the hardware, you'll need to manually
configure the driver."),

setupYabootAddEntry => 
N_("You can add additional entries in yaboot for other operating systems,
alternate kernels, or for an emergency boot image.

For other OSs, the entry consists only of a label and the \"root\"
partition.

For Linux, there are a few possible options:

 * Label: this is the name you will have to type at the yaboot prompt to
select this boot option.

 * Image: this would be the name of the kernel to boot. Typically, vmlinux
or a variation of vmlinux with an extension.

 * Root: the \"root\" device or ``/'' for your Linux installation.

 * Append: on Apple hardware, the kernel append option is often used to
assist in initializing video hardware, or to enable keyboard mouse button
emulation for the missing 2nd and 3rd mouse buttons on a stock Apple mouse.
The following are some examples:

         video=aty128fb:vmode:17,cmode:32,mclk:71 adb_buttons=103,111
hda=autotune

         video=atyfb:vmode:12,cmode:24 adb_buttons=103,111

 * Initrd: this option can be used either to load initial modules before
the boot device is available, or to load a ramdisk image for an emergency
boot situation.

 * Initrd-size: the default ramdisk size is generally 4096 Kbytes. If you
need to allocate a large ramdisk, this option can be used to specify a
ramdisk larger than the default.

 * Read-write: normally the \"root\" partition is initially mounted as
read-only, to allow a file system check before the system becomes ``live''.
You can override the default with this option.

 * NoVideo: should the Apple video hardware prove to be exceptionally
problematic, you can select this option to boot in ``novideo'' mode, with
native frame buffer support.

 * Default: selects this entry as being the default Linux selection,
selectable by pressing ENTER at the yaboot prompt. This entry will also be
highlighted with a ``*'' if you press [Tab] to see the boot selections."),

setupYabootGeneral => 
N_("Yaboot is a bootloader for NewWorld Macintosh hardware and can be used to
boot GNU/Linux, MacOS or MacOSX. Normally, MacOS and MacOSX are correctly
detected and installed in the bootloader menu. If this is not the case, you
can add an entry by hand in this screen. Be careful to choose the correct
parameters.

Yaboot's main options are:

 * Init Message: a simple text message displayed before the boot prompt.

 * Boot Device: indicates where you want to place the information required
to boot to GNU/Linux. Generally, you set up a bootstrap partition earlier
to hold this information.

 * Open Firmware Delay: unlike LILO, there are two delays available with
yaboot. The first delay is measured in seconds and at this point, you can
choose between CD, OF boot, MacOS or Linux;

 * Kernel Boot Timeout: this timeout is similar to the LILO boot delay.
After selecting Linux, you will have this delay in 0.1 second before your
default kernel description is selected;

 * Enable CD Boot?: checking this option allows you to choose ``C'' for CD
at the first boot prompt.

 * Enable OF Boot?: checking this option allows you to choose ``N'' for
Open Firmware at the first boot prompt.

 * Default OS: you can select which OS will boot by default when the Open
Firmware Delay expires."),

sound_config => 
N_("\"Sound card\": if a sound card is detected on your system, it is displayed
here. If you notice the sound card displayed is not the one that is
actually present on your system, you can click on the button and choose
another driver."),

summary => 
N_("As a review, DrakX will present a summary of various information it has
about your system. Depending on your installed hardware, you may have some
or all of the following entries:

 * \"Mouse\": check the current mouse configuration and click on the button
to change it if necessary.

 * \"Keyboard\": check the current keyboard map configuration and click on
the button to change that if necessary.

 * \"Country\": check the current country selection. If you are not in this
country, click on the button and choose another one.

 * \"Timezone\": By default, DrakX deduces your time zone based on the
primary language you have chosen. But here, just as in your choice of a
keyboard, you may not be in the country with which the chosen language
should correspond. You may need to click on the \"Timezone\" button to
configure the clock for the correct timezone.

 * \"Printer\": clicking on the \"No Printer\" button will open the printer
configuration wizard. Consult the corresponding chapter of the ``Starter
Guide'' for more information on how to setup a new printer. The interface
presented there is similar to the one used during installation.

 * \"Bootloader\": if you wish to change your bootloader configuration,
click that button. This should be reserved to advanced users.

 * \"Graphical Interface\": by default, DrakX configures your graphical
interface in \"800x600\" resolution. If that does not suits you, click on
the button to reconfigure your graphical interface.

 * \"Network\": If you want to configure your Internet or local network
access now, you can by clicking on this button.

 * \"Sound card\": if a sound card is detected on your system, it is
displayed here. If you notice the sound card displayed is not the one that
is actually present on your system, you can click on the button and choose
another driver.

 * \"TV card\": if a TV card is detected on your system, it is displayed
here. If you have a TV card and it is not detected, click on the button to
try to configure it manually.

 * \"ISDN card\": if an ISDN card is detected on your system, it will be
displayed here. You can click on the button to change the parameters
associated with the card."),

takeOverHdChoose => 
N_("Choose the hard drive you want to erase in order to install your new
Mandrake Linux partition. Be careful, all data present on it will be lost
and will not be recoverable!"),

takeOverHdConfirm => 
N_("Click on \"Next ->\" if you want to delete all data and partitions present
on this hard drive. Be careful, after clicking on \"Next ->\", you will not
be able to recover any data and partitions present on this hard drive,
including any Windows data.

Click on \"<- Previous\" to stop this operation without losing any data and
partitions present on this hard drive."),
);
