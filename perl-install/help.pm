package help;
use common;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.
sub acceptLicense {
    N("Before continuing, you should carefully read the terms of the license. It
covers the entire Mandrake Linux distribution. If you do agree with all the
terms in it, check the \"%s\" box. If not, simply turn off your computer.", N("Accept"));
}
sub addUser {
    N("GNU/Linux is a multi-user system, meaning each user may have their own
preferences, their own files and so on. You can read the ``Starter Guide''
to learn more about multi-user systems. But unlike \"root\", who is the
system administrator, the users you add at this point will not be
authorized to change anything except their own files and their own
configurations, protecting the system from unintentional or malicious
changes that impact on the system as a whole. You will have to create at
least one regular user for yourself -- this is the account which you should
use for routine, day-to-day use. Although it is very easy to log in as
\"root\" to do anything and everything, it may also be very dangerous! A
very simple mistake could mean that your system will not work any more. If
you make a serious mistake as a regular user, the worst that will happen is
that you will lose some information, but not affect the entire system.

The first field asks you for a real name. Of course, this is not mandatory
-- you can actually enter whatever you like. DrakX will use the first word
you typed in this field and copy it to the \"%s\" field, which is the name
this user will enter to log onto the system. If you like, you may override
the default and change the username. The next step is to enter a password.
From a security point of view, a non-privileged (regular) user password is
not as crucial as the \"root\" password, but that is no reason to neglect
it by making it blank or too simple: after all, your files could be the
ones at risk.

Once you click on \"%s\", you can add other users. Add a user for each one
of your friends: your father or your sister, for example. Click \"%s\" when
you have finished adding users.

Clicking the \"%s\" button allows you to change the default \"shell\" for
that user (bash by default).

When you have finished adding users, you will be asked to choose a user
that can automatically log into the system when the computer boots up. If
you are interested in that feature (and do not care much about local
security), choose the desired user and window manager, then click \"%s\".
If you are not interested in this feature, uncheck the \"%s\" box.", N("User name"), N("Accept user"), N("Next ->"), N("Advanced"), N("Next ->"), N("Do you want to use this feature?"));
}
sub ask_mntpoint_s {
    N("Listed here are the existing Linux partitions detected on your hard drive.
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
\"second lowest SCSI ID\", etc.");
}
sub chooseCd {
    N("The Mandrake Linux installation is distributed on several CD-ROMs. DrakX
knows if a selected package is located on another CD-ROM so it will eject
the current CD and ask you to insert the correct CD as required.");
}
sub choosePackages {
    N("It is now time to specify which programs you wish to install on your
system. There are thousands of packages available for Mandrake Linux, and
to make it simpler to manage the packages have been placed into groups of
similar applications.

Packages are sorted into groups corresponding to a particular use of your
machine. Mandrake Linux has four predefined installations available. You
can think of these installation classes as containers for various packages.
You can mix and match applications from the various groups, so a
``Workstation'' installation can still have applications from the
``Development'' group installed.

 * \"%s\": if you plan to use your machine as a workstation, select one or
more of the applications that are in the workstation group.

 * \"%s\": if plan on using your machine for programming, choose the
appropriate packages from that group.

 * \"%s\": if your machine is intended to be a server, select which of the
more common services you wish to install on your machine.

 * \"%s\": this is where you will choose your preferred graphical
environment. At least one must be selected if you want to have a graphical
interface available.

Moving the mouse cursor over a group name will display a short explanatory
text about that group. If you unselect all groups when performing a regular
installation (as opposed to an upgrade), a dialog will pop up proposing
different options for a minimal installation:

 * \"%s\": install the minimum number of packages possible to have a
working graphical desktop.

 * \"%s\": installs the base system plus basic utilities and their
documentation. This installation is suitable for setting up a server.

 * \"%s\": will install the absolute minimum number of packages necessary
to get a working Linux system. With this installation you will only have a
command line interface. The total size of this installation is about 65
megabytes.

You can check the \"%s\" box, which is useful if you are familiar with the
packages being offered or if you want to have total control over what will
be installed.

If you started the installation in \"%s\" mode, you can unselect all groups
to avoid installing any new package. This is useful for repairing or
updating an existing system.", N("Workstation"), N("Development"), N("Server"), N("Graphical Environment"), N("With X"), N("With basic documentation"), N("Truly minimal install"), N("Individual package selection"), N("Upgrade"));
}
sub choosePackagesTree {
    N("If you told the installer that you wanted to individually select packages,
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
security holes were discovered after this version of Mandrake Linux was
finalized. If you do not know what a particular service is supposed to do
or why it is being installed, then click \"%s\". Clicking \"%s\" will
install the listed services and they will be started automatically by
default during boot. !!

The \"%s\" option is used to disable the warning dialog which appears
whenever the installer automatically selects a package to resolve a
dependency issue. Some packages have relationships between each other such
that installation of a package requires that some other program is also
rerquired to be installed. The installer can determine which packages are
required to satisfy a dependency to successfully complete the installation.

The tiny floppy disk icon at the bottom of the list allows you to load a
package list created during a previous installation. This is useful if you
have a number of machines that you wish to configure identically. Clicking
on this icon will ask you to insert a floppy disk previously created at the
end of another installation. See the second tip of last step on how to
create such a floppy.", N("No"), N("Yes"), N("Automatic dependencies"));
}
sub configureNetwork {
    N("You will now set up your Internet/network connection. If you wish to
connect your computer to the Internet or to a local network, click \"%s\".
Mandrake Linux will attempt to autodetect network devices and modems. If
this detection fails, uncheck the \"%s\" box. You may also choose not to
configure the network, or to do it later, in which case clicking the \"%s\"
button will take you to the next step.

When configuring your network, the available connections options are:
traditional modem, ISDN modem, ADSL connection, cable modem, and finally a
simple LAN connection (Ethernet).

We will not detail each configuration option - just make sure that you have
all the parameters, such as IP address, default gateway, DNS servers, etc.
from your Internet Service Provider or system administrator.

You can consult the ``Starter Guide'' chapter about Internet connections
for details about the configuration, or simply wait until your system is
installed and use the program described there to configure your connection.", N("Next ->"), N("Use auto detection"), N("Cancel"));
}
sub configurePrinter {
    N("\"%s\": clicking on the \"%s\" button will open the printer configuration
wizard. Consult the corresponding chapter of the ``Starter Guide'' for more
information on how to setup a new printer. The interface presented there is
similar to the one used during installation.", N("Printer"), N("Configure"));
}
sub configureServices {
    N("This dialog is used to choose which services you wish to start at boot
time.

DrakX will list all the services available on the current installation.
Review each one carefully and uncheck those which are not needed at boot
time.

A short explanatory text will be displayed about a service when it is
selected. However, if you are not sure whether a service is useful or not,
it is safer to leave the default behavior.

!! At this stage, be very careful if you intend to use your machine as a
server: you will probably not want to start any services that you do not
need. Please remember that several services can be dangerous if they are
enabled on a server. In general, select only the services you really need.
!!");
}
sub configureTimezoneGMT {
    N("GNU/Linux manages time in GMT (Greenwich Mean Time) and translates it to
local time according to the time zone you selected. If the clock on your
motherboard is set to local time, you may deactivate this by unselecting
\"%s\", which will let GNU/Linux know that the system clock and the
hardware clock are in the same timezone. This is useful when the machine
also hosts another operating system like Windows.

The \"%s\" option will automatically regulate the clock by connecting to a
remote time server on the Internet. For this feature to work, you must have
a working Internet connection. It is best to choose a time server located
near you. This option actually installs a time server that can used by
other machines on your local network as well.", N("Hardware clock set to GMT"), N("Automatic time synchronization"));
}
sub configureX_card_list {
    N("Graphic Card

   The installer will normally automatically detect and configure the
graphic card installed on your machine. If it is not the case, you can
choose from this list the card you actually have installed.

   In the case that different servers are available for your card, with or
without 3D acceleration, you are then asked to choose the server that best
suits your needs.");
}
sub configureX_chooser {
    N("X (for X Window System) is the heart of the GNU/Linux graphical interface
on which all the graphical environments (KDE, GNOME, AfterStep,
WindowMaker, etc.) bundled with Mandrake Linux rely upon.

You will be presented with a list of different parameters to change to get
an optimal graphical display: Graphic Card

   The installer will normally automatically detect and configure the
graphic card installed on your machine. If it is not the case, you can
choose from this list the card you actually have installed.

   In the case that different servers are available for your card, with or
without 3D acceleration, you are then asked to choose the server that best
suits your needs.



Monitor

   The installer will normally automatically detect and configure the
monitor connected to your machine. If it is correct, you can choose from
this list the monitor you actually have connected to your computer.



Resolution

   Here you can choose the resolutions and color depths available for your
hardware. Choose the one that best suits your needs (you will be able to
change that after installation though). A sample of the chosen
configuration is shown in the monitor.



Test

   the system will try to open a graphical screen at the desired
resolution. If you can see the message during the test and answer \"%s\",
then DrakX will proceed to the next step. If you cannot see the message, it
means that some part of the autodetected configuration was incorrect and
the test will automatically end after 12 seconds, bringing you back to the
menu. Change settings until you get a correct graphical display.



Options

   Here you can choose whether you want to have your machine automatically
switch to a graphical interface at boot. Obviously, you want to check
\"%s\" if your machine is to act as a server, or if you were not successful
in getting the display configured.", N("Yes"), N("No"));
}
sub configureX_monitor {
    N("Monitor

   The installer will normally automatically detect and configure the
monitor connected to your machine. If it is correct, you can choose from
this list the monitor you actually have connected to your computer.");
}
sub configureX_resolution {
    N("Resolution

   Here you can choose the resolutions and color depths available for your
hardware. Choose the one that best suits your needs (you will be able to
change that after installation though). A sample of the chosen
configuration is shown in the monitor.");
}
sub configureX_xfree_and_glx {
    N("In the case that different servers are available for your card, with or
without 3D acceleration, you are then asked to choose the server that best
suits your needs.");
}
sub configureXxdm {
    N("Options

   Here you can choose whether you want to have your machine automatically
switch to a graphical interface at boot. Obviously, you want to check
\"%s\" if your machine is to act as a server, or if you were not successful
in getting the display configured.", N("No"));
}
sub doPartitionDisks {
    N("At this point, you need to decide where you want to install the Mandrake
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

 * \"%s\": this option will perform an automatic partitioning of your blank
drive(s). If you use this option there will be no further prompts.

 * \"%s\": the wizard has detected one or more existing Linux partitions on
your hard drive. If you want to use them, choose this option. You will then
be asked to choose the mount points associated with each of the partitions.
The legacy mount points are selected by default, and for the most part it's
a good idea to keep them.

 * \"%s\": if Microsoft Windows is installed on your hard drive and takes
all the space available on it, you will have to create free space for
Linux. To do so, you can delete your Microsoft Windows partition and data
(see ``Erase entire disk'' solution) or resize your Microsoft Windows FAT
partition. Resizing can be performed without the loss of any data, provided
you have previously defragmented the Windows partition and that it uses the
FAT format. Backing up your data is strongly recommended.. Using this
option is recommended if you want to use both Mandrake Linux and Microsoft
Windows on the same computer.

   Before choosing this option, please understand that after this
procedure, the size of your Microsoft Windows partition will be smaller
then when you started. You will have less free space under Microsoft
Windows to store your data or to install new software.

 * \"%s\": if you want to delete all data and all partitions present on
your hard drive and replace them with your new Mandrake Linux system,
choose this option. Be careful, because you will not be able to undo your
choice after you confirm.

   !! If you choose this option, all data on your disk will be deleted. !!

 * \"%s\": this will simply erase everything on the drive and begin fresh,
partitioning everything from scratch. All data on your disk will be lost.

   !! If you choose this option, all data on your disk will be lost. !!

 * \"%s\": choose this option if you want to manually partition your hard
drive. Be careful -- it is a powerful but dangerous choice and you can very
easily lose all your data. That's why this option is really only
recommended if you have done something like this before and have some
experience. For more instructions on how to use the DiskDrake utility,
refer to the ``Managing Your Partitions '' section in the ``Starter
Guide''.", N("Use free space"), N("Use existing partition"), N("Use the free space on the Windows partition"), N("Erase entire disk"), N("Remove Windows"), N("Custom disk partitioning"));
}
sub exitInstall {
    N("There you are. Installation is now complete and your GNU/Linux system is
ready to use. Just click \"%s\" to reboot the system. The first thing you
should see after your computer has finished doing its hardware tests is the
bootloader menu, giving you the choice of which operating system to start.

The \"%s\" button shows two more buttons to:

 * \"%s\": to create an installation floppy disk that will automatically
perform a whole installation without the help of an operator, similar to
the installation you just configured.

   Note that two different options are available after clicking the button:

    * \"%s\". This is a partially automated installation. The partitioning
step is the only interactive procedure.

    * \"%s\". Fully automated installation: the hard disk is completely
rewritten, all data is lost.

   This feature is very handy when installing a number of similar machines.
See the Auto install section on our web site for more information.

 * \"%s\"(*): saves a list of the packages selected in this installation.
To use this selection with another installation, insert the floppy and
start the installation. At the prompt, press the [F1] key and type >>linux
defcfg=\"floppy\" <<.

(*) You need a FAT-formatted floppy (to create one under GNU/Linux, type
\"mformat a:\")", N("Reboot"), N("Advanced"), N("generate auto-install floppy"), N("Replay"), N("Automated"), N("Save packages selection"));
}
sub formatPartitions {
    N("Any partitions that have been newly defined must be formatted for use
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

Click on \"%s\" when you are ready to format partitions.

Click on \"%s\" if you want to choose another partition for your new
Mandrake Linux operating system installation.

Click on \"%s\" if you wish to select partitions that will be checked for
bad blocks on the disk.", N("Next ->"), N("<- Previous"), N("Advanced"));
}
sub installUpdates {
    N("At the time you are installing Mandrake Linux, it is likely that some
packages have been updated since the initial release. Bugs may have been
fixed, security issues resolved. To allow you to benefit from these
updates, you are now able to download them from the Internet. Check \"%s\"
if you have a working Internet connection, or \"%s\" if you prefer to
install updated packages later.

Choosing \"%s\" will display a list of places from which updates can be
retrieved. You should choose one nearer to you. A package-selection tree
will appear: review the selection, and press \"%s\" to retrieve and install
the selected package(s), or \"%s\" to abort.", N("Yes"), N("No"), N("Yes"), N("Install"), N("Cancel"));
}
sub miscellaneous {
    N("At this point, DrakX will allow you to choose the security level desired
for the machine. As a rule of thumb, the security level should be set
higher if the machine will contain crucial data, or if it will be a machine
directly exposed to the Internet. The trade-off of a higher security level
is generally obtained at the expense of ease of use.

If you do not know what to choose, stay with the default option.");
}
sub partition_with_diskdrake {
    N("At this point, you need to choose which partition(s) will be used for the
installation of your Mandrake Linux system. If partitions have already been
defined, either from a previous installation of GNU/Linux or by another
partitioning tool, you can use existing partitions. Otherwise, hard drive
partitions must be defined.

To create partitions, you must first select a hard drive. You can select
the disk for partitioning by clicking on ``hda'' for the first IDE drive,
``hdb'' for the second, ``sda'' for the first SCSI drive and so on.

To partition the selected hard drive, you can use these options:

 * \"%s\": this option deletes all partitions on the selected hard drive

 * \"%s\": this option enables you to automatically create ext3 and swap
partitions in the free space of your hard drive

\"%s\": gives access to additional features:

 * \"%s\": saves the partition table to a floppy. Useful for later
partition-table recovery if necessary. It is strongly recommended that you
perform this step.

 * \"%s\": allows you to restore a previously saved partition table from a
floppy disk.

 * \"%s\": if your partition table is damaged, you can try to recover it
using this option. Please be careful and remember that it doesn't always
work.

 * \"%s\": discards all changes and reloads the partition table that was
originally on the hard drive.

 * \"%s\": unchecking this option will force users to manually mount and
unmount removable media such as floppies and CD-ROMs.

 * \"%s\": use this option if you wish to use a wizard to partition your
hard drive. This is recommended if you do not have a good understanding of
partitioning.

 * \"%s\": use this option to cancel your changes.

 * \"%s\": allows additional actions on partitions (type, options, format)
and gives more information about the hard drive.

 * \"%s\": when you are finished partitioning your hard drive, this will
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
emergency boot situations.", N("Clear all"), N("Auto allocate"), N("More"), N("Save partition table"), N("Restore partition table"), N("Rescue partition table"), N("Reload partition table"), N("Removable media automounting"), N("Wizard"), N("Undo"), N("Toggle between normal/expert mode"), N("Done"));
}
sub resizeFATChoose {
    N("More than one Microsoft partition has been detected on your hard drive.
Please choose which one you want to resize in order to install your new
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
disk or partition is called \"C:\").");
}
sub selectCountry {
    N("\"%s\": check the current country selection. If you are not in this
country, click on the \"%s\" button and choose another one. If your country
is not in the first list shown, click the \"%s\" button to get the complete
country list.", N("Country"), N("Configure"), N("More"));
}
sub selectInstallClass {
    N("This step is activated only if an old GNU/Linux partition has been found on
your machine.

DrakX now needs to know if you want to perform a new install or an upgrade
of an existing Mandrake Linux system:

 * \"%s\": For the most part, this completely wipes out the old system. If
you wish to change how your hard drives are partitioned, or change the file
system, you should use this option. However, depending on your partitioning
scheme, you can prevent some of your existing data from being over-written.

 * \"%s\": this installation class allows you to update the packages
currently installed on your Mandrake Linux system. Your current
partitioning scheme and user data is not altered. Most of other
configuration steps remain available, similar to a standard installation.

Using the ``Upgrade'' option should work fine on Mandrake Linux systems
running version \"8.1\" or later. Performing an Upgrade on versions prior
to Mandrake Linux version \"8.1\" is not recommended.", N("Install"), N("Upgrade"));
}
sub selectKeyboard {
    N("Depending on the default language you chose in Section , DrakX will
automatically select a particular type of keyboard configuration. However,
you may not have a keyboard that corresponds exactly to your language: for
example, if you are an English speaking Swiss person, you may have a Swiss
keyboard. Or if you speak English but are located in Quebec, you may find
yourself in the same situation where your native language and keyboard do
not match. In either case, this installation step will allow you to select
an appropriate keyboard from a list.

Click on the \"%s\" button to be presented with the complete list of
supported keyboards.

If you choose a keyboard layout based on a non-Latin alphabet, the next
dialog will allow you to choose the key binding that will switch the
keyboard between the Latin and non-Latin layouts.", N("More"));
}
sub selectLanguage {
    N("Your choice of preferred language will affect the language of the
documentation, the installer and the system in general. Select first the
region you are located in, and then the language you speak.

Clicking on the \"%s\" button will allow you to select other languages to
be installed on your workstation, thereby installing the language-specific
files for system documentation and applications. For example, if you will
host users from Spain on your machine, select English as the default
language in the tree view and \"%s\" in the Advanced section.

Note that you're not limited to choosing a single additional language. You
may choose several ones, or even install them all by selecting the \"%s\"
box. Selecting support for a language means translations, fonts, spell
checkers, etc. for that language will be installed. Additionally, the
\"%s\" checkbox allows you to force the system to use unicode (UTF-8). Note
however that this is an experimental feature. If you select different
languages requiring different encoding the unicode support will be
installed anyway.

To switch between the various languages installed on the system, you can
launch the \"/usr/sbin/localedrake\" command as \"root\" to change the
language used by the entire system. Running the command as a regular user
will only change the language settings for that particular user.", N("Advanced"), N("Espanol"), N("All languages"), N("Use Unicode by default"));
}
sub selectMouse {
    N("Usually, DrakX has no problems detecting the number of buttons on your
mouse. If it does, it assumes you have a two-button mouse and will
configure it for third-button emulation. The third-button mouse button of a
two-button mouse can be ``pressed'' by simultaneously clicking the left and
right mouse buttons. DrakX will automatically know whether your mouse uses
a PS/2, serial or USB interface.

If for some reason you wish to specify a different type of mouse, select it
from the list provided.

If you choose a mouse other than the default, a test screen will be
displayed. Use the buttons and wheel to verify that the settings are
correct and that the mouse is working correctly. If the mouse is not
working well, press the space bar or [Return] key to cancel the test and to
go back to the list of choices.

Wheel mice are occasionally not detected automatically, so you will need to
select your mouse from a list. Be sure to select the one corresponding to
the port that your mouse is attached to. After selecting a mouse and
pressing the \"%s\" button, a mouse image is displayed on-screen. Scroll
the mouse wheel to ensure that it is activated correctly. Once you see the
on-screen scroll wheel moving as you scroll your mouse wheel, test the
buttons and check that the mouse pointer moves on-screen as you move your
mouse.", N("Next ->"));
}
sub selectSerialPort {
    N("Please select the correct port. For example, the \"COM1\" port under
Windows is named \"ttyS0\" under GNU/Linux.");
}
sub setRootPassword {
    N("This is the most crucial decision point for the security of your GNU/Linux
system: you have to enter the \"root\" password. \"Root\" is the system
administrator and is the only user authorized to make updates, add users,
change the overall system configuration, and so on. In short, \"root\" can
do everything! That is why you must choose a password that is difficult to
guess - DrakX will tell you if the password that you chose too easy. As you
can see, you are not forced to enter a password, but we strongly advise you
against this. GNU/Linux is just as prone to operator error as any other
operating system. Since \"root\" can overcome all limitations and
unintentionally erase all data on partitions by carelessly accessing the
partitions themselves, it is important that it be difficult to become
\"root\".

The password should be a mixture of alphanumeric characters and at least 8
characters long. Never write down the \"root\" password -- it makes it far
too easy to compromise a system.

One caveat -- do not make the password too long or complicated because you
must be able to remember it!

The password will not be displayed on screen as you type it in. To reduce
the chance of a blind typing error you will need to enter the password
twice. If you do happen to make the same typing error twice, this
``incorrect'' password will be the one you will have use the first time you
connect.

If you wish access to this computer to be controlled by an authentication
server, click the \"%s\" button.

If your network uses either LDAP, NIS, or PDC Windows Domain authentication
services, select the appropriate one for \"%s\". If you do not know which
one to use, you should ask your network administrator.

If you happen to have problems with remembering passwords, if your computer
will never be connected to the internet or that you absolutely trust
everybody who uses your computer, you can choose to have \"%s\".", N("Advanced"), N("authentication"), N("No password"));
}
sub setupBootloader {
    N("This dialog allows you to fine tune your bootloader:

 * \"%s\": there are three choices for your bootloader:

    * \"%s\": if you prefer grub (text menu).

    * \"%s\": if you prefer LILO with its text menu interface.

    * \"%s\": if you prefer LILO with its graphical interface.

 * \"%s\": in most cases, you will not change the default (\"%s\"), but if
you prefer, the bootloader can be installed on the second hard drive
(\"%s\"), or even on a floppy disk (\"%s\");

 * \"%s\": after a boot or a reboot of the computer, this is the delay
given to the user at the console to select a boot entry other than the
default.

!! Beware that if you choose not to install a bootloader (by selecting
\"%s\"), you must ensure that you have a way to boot your Mandrake Linux
system! Be sure you know what you are doing before changing any of the
options. !!

Clicking the \"%s\" button in this dialog will offer advanced options which
are normally reserved for the expert user.", N("Bootloader to use"), N("GRUB"), N("LILO with text menu"), N("LILO with graphical menu"), N("Boot device"), N("/dev/hda"), N("/dev/hdb"), N("/dev/fd0"), N("Delay before booting the default image"), N("Skip"), N("Advanced"));
}
sub setupBootloaderAddEntry {
    N("After you have configured the general bootloader parameters, the list of
boot options that will be available at boot time will be displayed.

If there are other operating systems installed on your machine they will
automatically be added to the boot menu. You can fine-tune the existing
options by clicking \"%s\" to create a new entry; selecting an entry and
clicking \"%s\" or \"%s\" to modify or remove it. \"%s\" validates your
changes.

You may also not want to give access to these other operating systems to
anyone who goes to the console and reboots the machine. You can delete the
corresponding entries for the operating systems to remove them from the
bootloader menu, but you will need a boot disk in order to boot those other
operating systems!", N("Add"), N("Modify"), N("Remove"), N("OK"));
}
sub setupBootloaderBeginner {
    N("LILO and grub are GNU/Linux bootloaders. Normally, this stage is totally
automated. DrakX will analyze the disk boot sector and act according to
what it finds there:

 * if a Windows boot sector is found, it will replace it with a grub/LILO
boot sector. This way you will be able to load either GNU/Linux or another
OS.

 * if a grub or LILO boot sector is found, it will replace it with a new
one.

If it cannot make a determination, DrakX will ask you where to place the
bootloader.");
}
sub setupDefaultSpooler {
    N("Now, it's time to select a printing system for your computer. Other OSs may
offer you one, but Mandrake Linux offers two. Each of the printing system
is best suited to particular types of configuration.

 * \"%s\" -- which is an acronym for ``print, don't queue'', is the choice
if you have a direct connection to your printer, you want to be able to
panic out of printer jams, and you do not have networked printers. (\"%s\"
will handle only very simple network cases and is somewhat slow when used
with networks.) It's recommended that you use \"pdq\" if this is your first
experience with GNU/Linux.

 * \"%s\" - `` Common Unix Printing System'', is an excellent choice for
printing to your local printer or to one halfway around the planet. It is
simple to configure and can act as a server or a client for the ancient
\"lpd \" printing system, so it compatible with older operating systems
which may still need print services. While quite powerful, the basic setup
is almost as easy as \"pdq\". If you need to emulate a \"lpd\" server, make
sure you turn on the \"cups-lpd \" daemon. \"%s\" includes graphical
front-ends for printing or choosing printer options and for managing the
printer.

If you make a choice now, and later find that you don't like your printing
system you may change it by running PrinterDrake from the Mandrake Control
Center and clicking the expert button.", N("pdq"), N("pdq"), N("CUPS"), N("CUPS"));
}
sub setupSCSI {
    N("DrakX will first detect any IDE devices present in your computer. It will
also scan for one or more PCI SCSI cards on your system. If a SCSI card is
found, DrakX will automatically install the appropriate driver.

Because hardware detection is not foolproof, DrakX may fail in detecting
your hard drives. If so, you'll have to specify your hardware by hand.

If you had to manually specify your PCI SCSI adapter, DrakX will ask if you
want to configure options for it. You should allow DrakX to probe the
hardware for the card-specific options which are needed to initialize the
adapter. Most of the time, DrakX will get through this step without any
issues.

If DrakX is not able to probe for the options to automatically determine
which parameters need to be passed to the hardware, you'll need to manually
configure the driver.");
}
sub setupYabootAddEntry {
    N("You can add additional entries in yaboot for other operating systems,
alternate kernels, or for an emergency boot image.

For other OSs, the entry consists only of a label and the \"root\"
partition.

For Linux, there are a few possible options:

 * Label: this is the name you will have to type at the yaboot prompt to
select this boot option.

 * Image: this is the name of the kernel to boot. Typically, vmlinux or a
variation of vmlinux with an extension.

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
highlighted with a ``*'' if you press [Tab] to see the boot selections.");
}
sub setupYabootGeneral {
    N("Yaboot is a bootloader for NewWorld Macintosh hardware and can be used to
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
After selecting Linux, you will have this delay in 0.1 second increments
before your default kernel description is selected;

 * Enable CD Boot?: checking this option allows you to choose ``C'' for CD
at the first boot prompt.

 * Enable OF Boot?: checking this option allows you to choose ``N'' for
Open Firmware at the first boot prompt.

 * Default OS: you can select which OS will boot by default when the Open
Firmware Delay expires.");
}
sub sound_config {
    N("\"%s\": if a sound card is detected on your system, it is displayed here.
If you notice the sound card displayed is not the one that is actually
present on your system, you can click on the button and choose another
driver.", N("Sound card"));
}
sub summary {
    N("As a review, DrakX will present a summary of information it has about your
system. Depending on your installed hardware, you may have some or all of
the following entries. Each entry is made up of the configuration item to
be configured, followed by a quick summary of the current configuration.
Click on the corresponding \"%s\" button to change that.

 * \"%s\": check the current keyboard map configuration and change that if
necessary.

 * \"%s\": check the current country selection. If you are not in this
country, click on the \"%s\" button and choose another one. If your country
is not in the first list shown, click the \"%s\" button to get the complete
country list.

 * \"%s\": By default, DrakX deduces your time zone based on the country
you have chosen. You can click on the \"%s\" button here if this is not
correct.

 * \"%s\": check the current mouse configuration and click on the button to
change it if necessary.

 * \"%s\": clicking on the \"%s\" button will open the printer
configuration wizard. Consult the corresponding chapter of the ``Starter
Guide'' for more information on how to setup a new printer. The interface
presented there is similar to the one used during installation.

 * \"%s\": if a sound card is detected on your system, it is displayed
here. If you notice the sound card displayed is not the one that is
actually present on your system, you can click on the button and choose
another driver.

 * \"%s\": by default, DrakX configures your graphical interface in
\"800x600\" or \"1024x768\" resolution. If that does not suit you, click on
\"%s\" to reconfigure your graphical interface.

 * \"%s\": if a TV card is detected on your system, it is displayed here.
If you have a TV card and it is not detected, click on \"%s\" to try to
configure it manually.

 * \"%s\": if an ISDN card is detected on your system, it will be displayed
here. You can click on \"%s\" to change the parameters associated with the
card.

 * \"%s\": If you want to configure your Internet or local network access
now.

 * \"%s\": this entry allows you to redefine the security level as set in a
previous step ().

 * \"%s\": if you plan to connect your machine to the Internet, it's a good
idea to protect yourself from intrusions by setting up a firewall. Consult
the corresponding section of the ``Starter Guide'' for details about
firewall settings.

 * \"%s\": if you wish to change your bootloader configuration, click that
button. This should be reserved to advanced users.

 * \"%s\": here you'll be able to fine control which services will be run
on your machine. If you plan to use this machine as a server it's a good
idea to review this setup.", N("Configure"), N("Keyboard"), N("Country"), N("Configure"), N("More"), N("Timezone"), N("Configure"), N("Mouse"), N("Printer"), N("Configure"), N("Sound card"), N("Graphical Interface"), N("Configure"), N("TV card"), N("Configure"), N("ISDN card"), N("Configure"), N("Network"), N("Security Level"), N("Firewall"), N("Bootloader"), N("Services"));
}
sub takeOverHdChoose {
    N("Choose the hard drive you want to erase in order to install your new
Mandrake Linux partition. Be careful, all data present on this partition
will be lost and will not be recoverable!");
}
sub takeOverHdConfirm {
    N("Click on \"%s\" if you want to delete all data and partitions present on
this hard drive. Be careful, after clicking on \"%s\", you will not be able
to recover any data and partitions present on this hard drive, including
any Windows data.

Click on \"%s\" to stop this operation without losing any data and
partitions present on this hard drive.", N("Next ->"), N("Next ->"), N("<- Previous"));
}
