package help;
use common;

1;

# IMPORTANT: Don't edit this File - It is automatically generated 
#            from the manuals !!! 
#            Write a mail to <documentation@mandrakesoft.com> if
#            you want it changed.
sub acceptLicense() {
    N("Before continuing, you should carefully read the terms of the license. It
covers the entire Mandrakelinux distribution. If you agree with all the
terms it contains, check the \"%s\" box. If not, clicking on the \"%s\"
button will reboot your computer.", N("Accept"), N("Quit"));
}
sub addUser() {
    N("GNU/Linux is a multi-user system which means each user can have his or her
own preferences, own files and so on. But unlike \"root\", who is the
system administrator, the users you add at this point won't be authorized
to change anything except their own files and their own configurations,
protecting the system from unintentional or malicious changes which could
impact on the system as a whole. You'll have to create at least one regular
user for yourself -- this is the account which you should use for routine,
day-to-day usage. Although it's very easy to log in as \"root\" to do
anything and everything, it may also be very dangerous! A very simple
mistake could mean that your system won't work any more. If you make a
serious mistake as a regular user, the worst that can happen is that you'll
lose some information, but you won't affect the entire system.

The first field asks you for a real name. Of course, this is not mandatory
-- you can actually enter whatever you like. DrakX will use the first word
you type in this field and copy it to the \"%s\" one, which is the name
this user will enter to log onto the system. If you like, you may override
the default and change the user name. The next step is to enter a password.
From a security point of view, a non-privileged (regular) user password is
not as crucial as the \"root\" password, but that's no reason to neglect it
by making it blank or too simple: after all, your files could be the ones
at risk.

Once you click on \"%s\", you can add other users. Add a user for each one
of your friends, your father, your sister, etc. Click \"%s\" when you're
finished adding users.

Clicking the \"%s\" button allows you to change the default \"shell\" for
that user (bash by default).

When you're finished adding users, you'll be asked to choose a user who
will be automatically logged into the system when the computer boots up. If
you're interested in that feature (and don't care much about local
security), choose the desired user and window manager, then click on
\"%s\". If you're not interested in this feature, uncheck the \"%s\" box.", N("User name"), N("Accept user"), N("Next"), N("Advanced"), N("Next"), N("Do you want to use this feature?"));
}
sub ask_mntpoint_s() {
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
sub chooseCd() {
    N("The Mandrakelinux installation is distributed on several CD-ROMs. If a
selected package is located on another CD-ROM, DrakX will eject the current
CD and ask you to insert the required one. If you do not have the requested
CD at hand, just click on \"%s\", the corresponding packages will not be
installed.", N("Cancel"));
}
sub choosePackages() {
    N("It's now time to specify which programs you wish to install on your system.
There are thousands of packages available for Mandrakelinux, and to make it
simpler to manage, they have been placed into groups of similar
applications.

Mandrakelinux sorts package groups in four categories. You can mix and
match applications from the various categories, so a ``Workstation''
installation can still have applications from the ``Server'' category
installed.

 * \"%s\": if you plan to use your machine as a workstation, select one or
more of the groups in the workstation category.

 * \"%s\": if you plan on using your machine for programming, select the
appropriate groups from that category. The special \"LSB\" group will
configure your system so that it complies as much as possible with the
Linux Standard Base specifications.

   Selecting the \"LSB\" group will also install the \"2.4\" kernel series,
instead of the default \"2.6\" one. This is to ensure 100%%-LSB compliance
of the system. However, if you do not select the \"LSB\" group you will
still have a system which is nearly 100%% LSB-compliant.

 * \"%s\": if your machine is intended to be a server, select which of the
more common services you wish to install on your machine.

 * \"%s\": this is where you will choose your preferred graphical
environment. At least one must be selected if you want to have a graphical
interface available.

Moving the mouse cursor over a group name will display a short explanatory
text about that group.

You can check the \"%s\" box, which is useful if you're familiar with the
packages being offered or if you want to have total control over what will
be installed.

If you start the installation in \"%s\" mode, you can deselect all groups
and prevent the installation of any new packages. This is useful for
repairing or updating an existing system.

If you deselect all groups when performing a regular installation (as
opposed to an upgrade), a dialog will pop up suggesting different options
for a minimal installation:

 * \"%s\": install the minimum number of packages possible to have a
working graphical desktop.

 * \"%s\": installs the base system plus basic utilities and their
documentation. This installation is suitable for setting up a server.

 * \"%s\": will install the absolute minimum number of packages necessary
to get a working Linux system. With this installation you will only have a
command-line interface. The total size of this installation is about 65
megabytes.", N("Workstation"), N("Development"), N("Server"), N("Graphical Environment"), N("Individual package selection"), N("Upgrade"), N("With X"), N("With basic documentation"), N("Truly minimal install"));
}
sub choosePackagesTree() {
    N("If you choose to install packages individually, the installer will present
a tree containing all packages classified by groups and subgroups. While
browsing the tree, you can select entire groups, subgroups, or individual
packages.

Whenever you select a package on the tree, a description will appear on the
right to let you know the purpose of that package.

!! If a server package has been selected, either because you specifically
chose the individual package or because it was part of a group of packages,
you'll be asked to confirm that you really want those servers to be
installed. By default Mandrakelinux will automatically start any installed
services at boot time. Even if they are safe and have no known issues at
the time the distribution was shipped, it is entirely possible that
security holes were discovered after this version of Mandrakelinux was
finalized. If you don't know what a particular service is supposed to do or
why it's being installed, then click \"%s\". Clicking \"%s\" will install
the listed services and they will be started automatically at boot time. !!

The \"%s\" option is used to disable the warning dialog which appears
whenever the installer automatically selects a package to resolve a
dependency issue. Some packages depend on others and the installation of
one particular package may require the installation of another package. The
installer can determine which packages are required to satisfy a dependency
to successfully complete the installation.

The tiny floppy disk icon at the bottom of the list allows you to load a
package list created during a previous installation. This is useful if you
have a number of machines that you wish to configure identically. Clicking
on this icon will ask you to insert the floppy disk created at the end of
another installation. See the second tip of the last step on how to create
such a floppy.", N("No"), N("Yes"), N("Automatic dependencies"));
}
sub configurePrinter() {
    N("\"%s\": clicking on the \"%s\" button will open the printer configuration
wizard. Consult the corresponding chapter of the ``Starter Guide'' for more
information on how to set up a new printer. The interface presented in our
manual is similar to the one used during installation.", N("Printer"), N("Configure"));
}
sub configureServices() {
    N("This dialog is used to select which services you wish to start at boot
time.

DrakX will list all services available on the current installation. Review
each one of them carefully and uncheck those which aren't needed at boot
time.

A short explanatory text will be displayed about a service when it is
selected. However, if you're not sure whether a service is useful or not,
it is safer to leave the default behavior.

!! At this stage, be very careful if you intend to use your machine as a
server: you probably don't want to start any services which you don't need.
Please remember that some services can be dangerous if they're enabled on a
server. In general, select only those services you really need. !!");
}
sub configureTimezoneGMT() {
    N("GNU/Linux manages time in GMT (Greenwich Mean Time) and translates it to
local time according to the time zone you selected. If the clock on your
motherboard is set to local time, you may deactivate this by unselecting
\"%s\", which will let GNU/Linux know that the system clock and the
hardware clock are in the same time zone. This is useful when the machine
also hosts another operating system.

The \"%s\" option will automatically regulate the system clock by
connecting to a remote time server on the Internet. For this feature to
work, you must have a working Internet connection. We recommend that you
choose a time server located near you. This option actually installs a time
server which can be used by other machines on your local network as well.", N("Hardware clock set to GMT"), N("Automatic time synchronization"));
}
sub configureX_card_list() {
    N("Graphic Card

   The installer will normally automatically detect and configure the
graphic card installed on your machine. If this is not correct, you can
choose from this list the card you actually have installed.

   In the situation where different servers are available for your card,
with or without 3D acceleration, you're asked to choose the server which
best suits your needs.");
}
sub configureX_chooser() {
    N("X (for X Window System) is the heart of the GNU/Linux graphical interface
on which all the graphical environments (KDE, GNOME, AfterStep,
WindowMaker, etc.) bundled with Mandrakelinux rely upon.

You'll see a list of different parameters to change to get an optimal
graphical display.

Graphic Card

   The installer will normally automatically detect and configure the
graphic card installed on your machine. If this is not correct, you can
choose from this list the card you actually have installed.

   In the situation where different servers are available for your card,
with or without 3D acceleration, you're asked to choose the server which
best suits your needs.



Monitor

   Normally the installer will automatically detect and configure the
monitor connected to your machine. If it is not correct, you can choose
from this list the monitor which is connected to your computer.



Resolution

   Here you can choose the resolutions and color depths available for your
graphics hardware. Choose the one which best suits your needs (you will be
able to make changes after the installation). A sample of the chosen
configuration is shown in the monitor picture.



Test

   Depending on your hardware, this entry might not appear.

   The system will try to open a graphical screen at the desired
resolution. If you see the test message during the test and answer \"%s\",
then DrakX will proceed to the next step. If you do not see it, then it
means that some part of the auto-detected configuration was incorrect and
the test will automatically end after 12 seconds and return you to the
menu. Change settings until you get a correct graphical display.



Options

   This steps allows you to choose whether you want your machine to
automatically switch to a graphical interface at boot. Obviously, you may
want to check \"%s\" if your machine is to act as a server, or if you were
not successful in getting the display configured.", N("Yes"), N("No"));
}
sub configureX_monitor() {
    N("Monitor

   Normally the installer will automatically detect and configure the
monitor connected to your machine. If it is not correct, you can choose
from this list the monitor which is connected to your computer.");
}
sub configureX_resolution() {
    N("Resolution

   Here you can choose the resolutions and color depths available for your
graphics hardware. Choose the one which best suits your needs (you will be
able to make changes after the installation). A sample of the chosen
configuration is shown in the monitor picture.");
}
sub configureX_xfree_and_glx() {
    N("In the situation where different servers are available for your card, with
or without 3D acceleration, you're asked to choose the server which best
suits your needs.");
}
sub configureXxdm() {
    N("Options

   This steps allows you to choose whether you want your machine to
automatically switch to a graphical interface at boot. Obviously, you may
want to check \"%s\" if your machine is to act as a server, or if you were
not successful in getting the display configured.", N("No"));
}
sub doPartitionDisks() {
    N("You now need to decide where you want to install the Mandrakelinux
operating system on your hard drive. If your hard drive is empty or if an
existing operating system is using all the available space you will have to
partition the drive. Basically, partitioning a hard drive means to
logically divide it to create the space needed to install your new
Mandrakelinux system.

Because the process of partitioning a hard drive is usually irreversible
and can lead to data losses, partitioning can be intimidating and stressful
for the inexperienced user. Fortunately, DrakX includes a wizard which
simplifies this process. Before continuing with this step, read through the
rest of this section and above all, take your time.

Depending on the configuration of your hard drive, several options are
available:

 * \"%s\". This option will perform an automatic partitioning of your blank
drive(s). If you use this option there will be no further prompts.

 * \"%s\". The wizard has detected one or more existing Linux partitions on
your hard drive. If you want to use them, choose this option. You will then
be asked to choose the mount points associated with each of the partitions.
The legacy mount points are selected by default, and for the most part it's
a good idea to keep them.

 * \"%s\". If Microsoft Windows is installed on your hard drive and takes
all the space available on it, you will have to create free space for
GNU/Linux. To do so, you can delete your Microsoft Windows partition and
data (see ``Erase entire disk'' solution) or resize your Microsoft Windows
FAT or NTFS partition. Resizing can be performed without the loss of any
data, provided you've previously defragmented the Windows partition.
Backing up your data is strongly recommended. Using this option is
recommended if you want to use both Mandrakelinux and Microsoft Windows on
the same computer.

   Before choosing this option, please understand that after this
procedure, the size of your Microsoft Windows partition will be smaller
than when you started. You'll have less free space under Microsoft Windows
to store your data or to install new software.

 * \"%s\". If you want to delete all data and all partitions present on
your hard drive and replace them with your new Mandrakelinux system, choose
this option. Be careful, because you won't be able to undo this operation
after you confirm.

   !! If you choose this option, all data on your disk will be deleted. !!

 * \"%s\". This option appears when the hard drive is entirely taken by
Microsoft Windows. Choosing this option will simply erase everything on the
drive and begin fresh, partitioning everything from scratch.

   !! If you choose this option, all data on your disk will be lost. !!

 * \"%s\". Choose this option if you want to manually partition your hard
drive. Be careful -- it is a powerful but dangerous choice and you can very
easily lose all your data. That's why this option is really only
recommended if you have done something like this before and have some
experience. For more instructions on how to use the DiskDrake utility,
refer to the ``Managing Your Partitions'' section in the ``Starter Guide''.", N("Use free space"), N("Use existing partition"), N("Use the free space on the Windows partition"), N("Erase entire disk"), N("Remove Windows"), N("Custom disk partitioning"));
}
sub exitInstall() {
    N("There you are. Installation is now complete and your GNU/Linux system is
ready to be used. Just click on \"%s\" to reboot the system. Don't forget
to remove the installation media (CD-ROM or floppy). The first thing you
should see after your computer has finished doing its hardware tests is the
boot-loader menu, giving you the choice of which operating system to start.

The \"%s\" button shows two more buttons to:

 * \"%s\": enables you to create an installation floppy disk which will
automatically perform a whole installation without the help of an operator,
similar to the installation you've just configured.

   Note that two different options are available after clicking on that
button:

    * \"%s\". This is a partially automated installation. The partitioning
step is the only interactive procedure.

    * \"%s\". Fully automated installation: the hard disk is completely
rewritten, all data is lost.

   This feature is very handy when installing on a number of similar
machines. See the Auto install section on our web site for more
information.

 * \"%s\"(*): saves a list of the packages selected in this installation.
To use this selection with another installation, insert the floppy and
start the installation. At the prompt, press the [F1] key, type >>linux
defcfg=\"floppy\"<< and press the [Enter] key.

(*) You need a FAT-formatted floppy. To create one under GNU/Linux, type
\"mformat a:\", or \"fdformat /dev/fd0\" followed by \"mkfs.vfat
/dev/fd0\".", N("Reboot"), N("Advanced"), N("Generate auto-install floppy"), N("Replay"), N("Automated"), N("Save packages selection"));
}
sub formatPartitions() {
    N("If you chose to reuse some legacy GNU/Linux partitions, you may wish to
reformat some of them and erase any data they contain. To do so, please
select those partitions as well.

Please note that it's not necessary to reformat all pre-existing
partitions. You must reformat the partitions containing the operating
system (such as \"/\", \"/usr\" or \"/var\") but you don't have to reformat
partitions containing data that you wish to keep (typically \"/home\").

Please be careful when selecting partitions. After the formatting is
completed, all data on the selected partitions will be deleted and you
won't be able to recover it.

Click on \"%s\" when you're ready to format the partitions.

Click on \"%s\" if you want to choose another partition for your new
Mandrakelinux operating system installation.

Click on \"%s\" if you wish to select partitions which will be checked for
bad blocks on the disk.", N("Next"), N("Previous"), N("Advanced"));
}
sub installUpdates() {
    N("By the time you install Mandrakelinux, it's likely that some packages will
have been updated since the initial release. Bugs may have been fixed,
security issues resolved. To allow you to benefit from these updates,
you're now able to download them from the Internet. Check \"%s\" if you
have a working Internet connection, or \"%s\" if you prefer to install
updated packages later.

Choosing \"%s\" will display a list of web locations from which updates can
be retrieved. You should choose one near to you. A package-selection tree
will appear: review the selection, and press \"%s\" to retrieve and install
the selected package(s), or \"%s\" to abort.", N("Yes"), N("No"), N("Yes"), N("Install"), N("Cancel"));
}
sub miscellaneous() {
    N("At this point, DrakX will allow you to choose the security level you desire
for your machine. As a rule of thumb, the security level should be set
higher if the machine is to contain crucial data, or if it's to be directly
exposed to the Internet. The trade-off that a higher security level is
generally obtained at the expense of ease of use.

If you don't know what to choose, keep the default option. You'll be able
to change it later with the draksec tool, which is part of Mandrakelinux
Control Center.

Fill the \"%s\" field with the e-mail address of the person responsible for
security. Security messages will be sent to that address.", N("Security Administrator"));
}
sub partition_with_diskdrake() {
    N("At this point, you need to choose which partition(s) will be used for the
installation of your Mandrakelinux system. If partitions have already been
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

 * \"%s\": un-checking this option will force users to manually mount and
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
emergency boot situations.", N("Clear all"), N("Auto allocate"), N("More"), N("Save partition table"), N("Restore partition table"), N("Rescue partition table"), N("Reload partition table"), N("Removable media auto-mounting"), N("Wizard"), N("Undo"), N("Toggle between normal/expert mode"), N("Done"));
}
sub resizeFATChoose() {
    N("More than one Microsoft partition has been detected on your hard drive.
Please choose the one which you want to resize in order to install your new
Mandrakelinux operating system.

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
sub selectCountry() {
    N("\"%s\": check the current country selection. If you're not in this country,
click on the \"%s\" button and choose another. If your country isn't in the
list shown, click on the \"%s\" button to get the complete country list.", N("Country / Region"), N("Configure"), N("More"));
}
sub selectInstallClass() {
    N("This step is activated only if an existing GNU/Linux partition has been
found on your machine.

DrakX now needs to know if you want to perform a new installation or an
upgrade of an existing Mandrakelinux system:

 * \"%s\". For the most part, this completely wipes out the old system.
However, depending on your partitioning scheme, you can prevent some of
your existing data (notably \"home\" directories) from being over-written.
If you wish to change how your hard drives are partitioned, or to change
the file system, you should use this option.

 * \"%s\". This installation class allows you to update the packages
currently installed on your Mandrakelinux system. Your current partitioning
scheme and user data won't be altered. Most of the other configuration
steps remain available and are similar to a standard installation.

Using the ``Upgrade'' option should work fine on Mandrakelinux systems
running version \"8.1\" or later. Performing an upgrade on versions prior
to Mandrakelinux version \"8.1\" is not recommended.", N("Install"), N("Upgrade"));
}
sub selectKeyboard() {
    N("Depending on the language you chose (), DrakX will automatically select a
particular type of keyboard configuration. Check that the selection suits
you or choose another keyboard layout.

Also, you may not have a keyboard which corresponds exactly to your
language: for example, if you are an English-speaking Swiss native, you may
have a Swiss keyboard. Or if you speak English and are located in Quebec,
you may find yourself in the same situation where your native language and
country-set keyboard don't match. In either case, this installation step
will allow you to select an appropriate keyboard from a list.

Click on the \"%s\" button to be shown a list of supported keyboards.

If you choose a keyboard layout based on a non-Latin alphabet, the next
dialog will allow you to choose the key binding which will switch the
keyboard between the Latin and non-Latin layouts.", N("More"));
}
sub selectLanguage() {
    N("The first step is to choose your preferred language.

Your choice of preferred language will affect the installer, the
documentation, and the system in general. First select the region you're
located in, then the language you speak.

Clicking on the \"%s\" button will allow you to select other languages to
be installed on your workstation, thereby installing the language-specific
files for system documentation and applications. For example, if Spanish
users are to use your machine, select English as the default language in
the tree view and \"%s\" in the Advanced section.

About UTF-8 (unicode) support: Unicode is a new character encoding meant to
cover all existing languages. However full support for it in GNU/Linux is
still under development. For that reason, Mandrakelinux's use of UTF-8 will
depend on the user's choices:

 * If you choose a language with a strong legacy encoding (latin1
languages, Russian, Japanese, Chinese, Korean, Thai, Greek, Turkish, most
iso-8859-2 languages), the legacy encoding will be used by default;

 * Other languages will use unicode by default;

 * If two or more languages are required, and those languages are not using
the same encoding, then unicode will be used for the whole system;

 * Finally, unicode can also be forced for use throughout the system at a
user's request by selecting the \"%s\" option independently of which
languages were been chosen.

Note that you're not limited to choosing a single additional language. You
may choose several, or even install them all by selecting the \"%s\" box.
Selecting support for a language means translations, fonts, spell checkers,
etc. will also be installed for that language.

To switch between the various languages installed on your system, you can
launch the \"localedrake\" command as \"root\" to change the language used
by the entire system. Running the command as a regular user will only
change the language settings for that particular user.", N("Advanced"), N("Espanol"), N("Use Unicode by default"), N("All languages"));
}
sub selectMouse() {
    N("Usually, DrakX has no problems detecting the number of buttons on your
mouse. If it does, it assumes you have a two-button mouse and will
configure it for third-button emulation. The third-button mouse button of a
two-button mouse can be obtained by simultaneously clicking the left and
right mouse buttons. DrakX will automatically know whether your mouse uses
a PS/2, serial or USB interface.

If you have a 3-button mouse without a wheel, you can choose a \"%s\"
mouse. DrakX will then configure your mouse so that you can simulate the
wheel with it: to do so, press the middle button and move your mouse
pointer up and down.

If for some reason you wish to specify a different type of mouse, select it
from the list provided.

You can select the \"%s\" entry to chose a ``generic'' mouse type which
will work with nearly all mice.

If you choose a mouse other than the default one, a test screen will be
displayed. Use the buttons and wheel to verify that the settings are
correct and that the mouse is working correctly. If the mouse is not
working well, press the space bar or [Return] key to cancel the test and
you will be returned to the mouse list.

Occasionally wheel mice are not detected automatically, so you will need to
select your mouse from a list. Be sure to select the one corresponding to
the port that your mouse is attached to. After selecting a mouse and
pressing the \"%s\" button, a mouse image will be displayed on-screen.
Scroll the mouse wheel to ensure that it is activating correctly. As you
scroll your mouse wheel, you will see the on-screen scroll wheel moving.
Test the buttons and check that the mouse pointer moves on-screen as you
move your mouse about.", N("with Wheel emulation"), N("Universal | Any PS/2 & USB mice"), N("Next"));
}
sub selectSerialPort() {
    N("Please select the correct port. For example, the \"COM1\" port under
Windows is named \"ttyS0\" under GNU/Linux.");
}
sub setRootPassword() {
    N("This is the most crucial decision point for the security of your GNU/Linux
system: you must enter the \"root\" password. \"Root\" is the system
administrator and is the only user authorized to make updates, add users,
change the overall system configuration, and so on. In short, \"root\" can
do everything! That's why you must choose a password which is difficult to
guess: DrakX will tell you if the password you chose is too simple. As you
can see, you're not forced to enter a password, but we strongly advise
against this. GNU/Linux is just as prone to operator error as any other
operating system. Since \"root\" can overcome all limitations and
unintentionally erase all data on partitions by carelessly accessing the
partitions themselves, it is important that it be difficult to become
\"root\".

The password should be a mixture of alphanumeric characters and at least 8
characters long. Never write down the \"root\" password -- it makes it far
too easy to compromise your system.

One caveat: don't make the password too long or too complicated because you
must be able to remember it!

The password won't be displayed on screen as you type it. To reduce the
chance of a blind typing error you'll need to enter the password twice. If
you do happen to make the same typing error twice, you'll have to use this
``incorrect'' password the first time you'll try to connect as \"root\".

If you want an authentication server to control access to your computer,
click on the \"%s\" button.

If your network uses either LDAP, NIS, or PDC Windows Domain authentication
services, select the appropriate one for \"%s\". If you don't know which
one to use, you should ask your network administrator.

If you happen to have problems with remembering passwords, or if your
computer will never be connected to the Internet and you absolutely trust
everybody who uses your computer, you can choose to have \"%s\".", N("Advanced"), N("authentication"), N("No password"));
}
sub setupBootloaderBeginner() {
    N("A boot loader is a little program which is started by the computer at boot
time. It's responsible for starting up the whole system. Normally, the boot
loader installation is totally automated. DrakX will analyze the disk boot
sector and act according to what it finds there:

 * if a Windows boot sector is found, it will replace it with a GRUB/LILO
boot sector. This way you'll be able to load either GNU/Linux or any other
OS installed on your machine.

 * if a GRUB or LILO boot sector is found, it'll replace it with a new one.

If DrakX can't determine where to place the boot sector, it'll ask you
where it should place it. Generally, the \"%s\" is the safest place.
Choosing \"%s\" won't install any boot loader. Use this option only if you
know what you're doing.", N("First sector of drive (MBR)"), N("Skip"));
}
sub setupDefaultSpooler() {
    N("Now, it's time to select a printing system for your computer. Other
operating systems may offer you one, but Mandrakelinux offers two. Each of
the printing systems is best suited to particular types of configuration.

 * \"%s\" -- which is an acronym for ``print, don't queue'', is the choice
if you have a direct connection to your printer, you want to be able to
panic out of printer jams, and you don't have networked printers. (\"%s\"
will handle only very simple network cases and is somewhat slow when used
within networks.) It's recommended that you use \"pdq\" if this is your
first experience with GNU/Linux.

 * \"%s\" stands for `` Common Unix Printing System'' and is an excellent
choice for printing to your local printer or to one halfway around the
planet. It's simple to configure and can act as a server or a client for
the ancient \"lpd\" printing system, so it's compatible with older
operating systems which may still need print services. While quite
powerful, the basic setup is almost as easy as \"pdq\". If you need to
emulate a \"lpd\" server, make sure you turn on the \"cups-lpd\" daemon.
\"%s\" includes graphical front-ends for printing or choosing printer
options and for managing the printer.

If you make a choice now, and later find that you don't like your printing
system you may change it by running PrinterDrake from the Mandrakelinux
Control Center and clicking on the \"%s\" button.", N("pdq"), N("pdq"), N("CUPS"), N("CUPS"), N("Expert"));
}
sub setupSCSI() {
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
sub sound_config() {
    N("\"%s\": if a sound card is detected on your system, it'll be displayed
here. If you notice the sound card isn't the one actually present on your
system, you can click on the button and choose a different driver.", N("Sound card"));
}
sub summary() {
    N("As a review, DrakX will present a summary of information it has gathered
about your system. Depending on the hardware installed on your machine, you
may have some or all of the following entries. Each entry is made up of the
hardware item to be configured, followed by a quick summary of the current
configuration. Click on the corresponding \"%s\" button to make the change.

 * \"%s\": check the current keyboard map configuration and change it if
necessary.

 * \"%s\": check the current country selection. If you're not in this
country, click on the \"%s\" button and choose another. If your country
isn't in the list shown, click on the \"%s\" button to get the complete
country list.

 * \"%s\": by default, DrakX deduces your time zone based on the country
you have chosen. You can click on the \"%s\" button here if this is not
correct.

 * \"%s\": verify the current mouse configuration and click on the button
to change it if necessary.

 * \"%s\": clicking on the \"%s\" button will open the printer
configuration wizard. Consult the corresponding chapter of the ``Starter
Guide'' for more information on how to set up a new printer. The interface
presented in our manual is similar to the one used during installation.

 * \"%s\": if a sound card is detected on your system, it'll be displayed
here. If you notice the sound card isn't the one actually present on your
system, you can click on the button and choose a different driver.

 * \"%s\": if you have a TV card, this is where information about its
configuration will be displayed. If you have a TV card and it isn't
detected, click on \"%s\" to try to configure it manually.

 * \"%s\": you can click on \"%s\" to change the parameters associated with
the card if you feel the configuration is wrong.

 * \"%s\": by default, DrakX configures your graphical interface in
\"800x600\" or \"1024x768\" resolution. If that doesn't suit you, click on
\"%s\" to reconfigure your graphical interface.

 * \"%s\": if you wish to configure your Internet or local network access,
you can do so now. Refer to the printed documentation or use the
Mandrakelinux Control Center after the installation has finished to benefit
from full in-line help.

 * \"%s\": allows to configure HTTP and FTP proxy addresses if the machine
you're installing on is to be located behind a proxy server.

 * \"%s\": this entry allows you to redefine the security level as set in a
previous step ().

 * \"%s\": if you plan to connect your machine to the Internet, it's a good
idea to protect yourself from intrusions by setting up a firewall. Consult
the corresponding section of the ``Starter Guide'' for details about
firewall settings.

 * \"%s\": if you wish to change your bootloader configuration, click this
button. This should be reserved to advanced users. Refer to the printed
documentation or the in-line help about bootloader configuration in the
Mandrakelinux Control Center.

 * \"%s\": through this entry you can fine tune which services will be run
on your machine. If you plan to use this machine as a server it's a good
idea to review this setup.", N("Configure"), N("Keyboard"), N("Country / Region"), N("Configure"), N("More"), N("Timezone"), N("Configure"), N("Mouse"), N("Printer"), N("Configure"), N("Sound card"), N("TV card"), N("Configure"), N("ISDN card"), N("Configure"), N("Graphical Interface"), N("Configure"), N("Network"), N("Proxies"), N("Security Level"), N("Firewall"), N("Bootloader"), N("Services"));
}
sub takeOverHdChoose() {
    N("Choose the hard drive you want to erase in order to install your new
Mandrakelinux partition. Be careful, all data on this drive will be lost
and will not be recoverable!");
}
sub takeOverHdConfirm() {
    N("Click on \"%s\" if you want to delete all data and partitions present on
this hard drive. Be careful, after clicking on \"%s\", you will not be able
to recover any data and partitions present on this hard drive, including
any Windows data.

Click on \"%s\" to quit this operation without losing data and partitions
present on this hard drive.", N("Next ->"), N("Next ->"), N("<- Previous"));
}
