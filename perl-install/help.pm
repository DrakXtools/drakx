package help;
use common;
%steps = (
empty => '',

acceptLicense => 
__("Before going further, you should read carefully the terms of the license. It
covers the whole Mandrake Linux distribution, and if you do not agree with all
the terms in it, click on the Refuse button. That'll immediately terminate the
installation. To follow on with the installation, click the Accept button."),

addUser => 
__("GNU/Linux is a multiuser system, and this means that each user can have his own
preferences, his own files and so on. You can read the User Guide to learn more.
But unlike Root, which is the administrator, the users which you will add here
will not be entitled to change anything except their own files and their own
configuration. You will have to create at least one regular user for yourself.
That account is where you should log in for routine use. Although it is very
practical to log in as Root everyday, it may also be very dangerous! The
slightest mistake could mean that your system would not work any more. If you
make a serious mistake as a regular user, you may only lose some information,
but not the entire system.

First you have to enter your real name. This is not mandatory, of course as you
can actually enter whatever you want. drakX will then take the first word you
have entered in the box and will bring it over to the User name. This is the
name that this particular user will use to log into the system. You can change
it. You then have to enter a password here. A non-privileged (regular) user's
password is not as crucial as that of Root from a security point of view, but
that is no reason to neglect it after all, they are your files at risk.

If you click on Accept user, you can then add as many as you want. Add a user
for each of your friends: your father or your sister, for example. When you have
added all the users you want, select Done.

Clicking the Advanced button allows you to change the default Shell for that
user (bash by default)."),

choosePackages => 
__("It is now time to specify which programs you wish to install on your system.
There are thousands of packages available for Mandrake Linux, and you are not
supposed to know them all by heart.

If you are performing a standard installation from CDROM you will first be asked
to specify the CDs you currently have. Check the boxes corresponding to the CDs
you've got around and click OK.

Packages are sorted in groups corresponding to a particular use of your machine.
The groups themselves are sorted in four sections:

 * Workstation: If your machine will be used as a workstation, select one or more
of the corresponding groups.

 * Graphical Environment: Select here your preferred graphical environment.
Select one at least if you want to have a graphical workstation!

 * Development: if the machine will be used for programming choose the desired
group(s).

 * Server: Finally, if the machine is intended to be a server, you are able here
to select the most common services that you wish to see installed on the
machine.

Moving the mouse cursor over a group name will display a short explanatory text
about this group.

Clicking the Advanced button, will allow you to select the Individual package
selection option. This is useful if you know well the packages offered or if you
want to have total control on what will be installed.

If you have started the installation in ``Update'' mode, you can unselect all
groups to avoid installing any new package and just repair or update the
existing system.

Finally, depending whether you choose to select individual packages or not, you
will be presented a tree containing all packages classified by groups and
subgroups. While browsing the tree, you can select entire groups, subgroups, or
simply packages.

Whenever you select a package on the tree, a description appears on the right.
When you have finished with your selections, click the Install button. The
installation itself then begins. If you have chosen to install a lot of
packages, you can go and have a cup of coffee.

!! If it happens that a server package has been selected either intentionnally
or because it was part of a whole group; you will be asked to confirm that you
really want those servers to be installed. Under Mandrake Linux, installed
servers are started by default at boot time. Even if they are safe at the time
the distribution was shipped, it may happen that security holes be discovered
afterwards. In particular if you don't know what all that is about, simply click
No here. Clickin Yes will install the listed services and they will be available
by default. !!

The Automatic dependencies option simply disable the warning dialog which
appears whenever the installer automatically selects a package because it is a
dependency of another package you just selected."),

configureNetwork => 
__("If you wish to connect your computer to the Internet or to a local network
please choose the correct option. Please turn on your device before choosing the
correct option to let DrakX detect it automaticall.

Mandrake Linux offers you to configure your Internet connection at install time.
Available connections are: traditional modem, ISDN modem, ADSL connection, cable
modem, and finally a simple LAN connection (Ethernet).

We won't enter here into the details of each configuration. Simply make sure
that you have all the parameters from your Internet Service Provider or system
administrator.

You can consult the chapter of the manual about Internet connection for details
about the configuration, or simply wait until your system is installed and use
the program described there to configure your connection.

If you do not have any connection to the Internet or a local network, choose
\"Disable networking\".

If you wish to configure the network later after installation or if you have
finished to configure your network connection, choose \"Done\"."),

configureServices => 
__("You may now choose which services you want to start at boot time.

Here are presented all the services available with the current installation.
Review them carefully and uncheck those that are not always needed at boot time.

You can get a short explanatory text on a service by placing the mouse cursor on
the service name. If you are not sure whether a service is useful or not, it is
safer to leave the default behavior though.

Be very careful in this step if you intend to use your machine as a server: you
will probably want not to start any services that you don't need. Please
remember that several services can be dangerous if they are enable on a server.
In general, select only the services that you really need."),

configureX => 
__("X (for X Window System) is the heart of the GNU/Linux graphical interface on
which all the graphics environments (KDE, Gnome, AfterStep, WindowMaker...)
bundled with Mandrake Linux rely. In this section, drakX will try to configure X
automatically.

It is extremely rare for it to fail. The only reason for it doing so is if the
hardware is very old (or very new). If it succeeds, it will start X
automatically with the best resolution possible depending on the size of the
monitor. A window will then appear and ask you if you can see it.

If you are doing an Expert install, you will enter the X configuration wizard.
See the corresponding section of the manual for more information about this
wizard.

If you can see the message and answer Yes, then drakX will proceed to next step.
If you cannot see the message, it simply means that the configuration was wrong
and the test will automatically end after 10 seconds, restoring the screen.

It can happen that the first try isn't the best display (screen is too small,
shifted left or right...). This is why, even if X starts up correctly, drakX
will then ask you if the configuration suits you and will propose to change it
by displaying a list of valid modes it could find, asking you to select one.

As a last resort, if you still cannot get X to work, choose Change graphics
card, select Unlisted card, and when prompted on which server you want, choose
FBDev. This is a failsafe option which works with any modern graphics card. Then
choose Test again to be sure.

Finally, you will be asked on whether you want to see the graphical interface at
boot. Note that you will be asked this even if you chose not to test the
configuration. Obviously, you want to answer No if your machine will act as a
server or if you were not successful in getting the display configured."),

createBootdisk => 
__("The Mandrake Linux CDROM has a built-in rescue mode. You can access it by
booting from the CDROM, press the >>F1<< key at boot and type >>rescue<< at the
prompt. But in case your computer cannot boot from the CDROM, you should come
back to this step for help in at least two situations:

 * when installing the boot loader, drakX will rewrite the boot sector (MBR) of
your main disk (unless you are using another boot manager) so that you can start
up with either Windows or GNU/Linux (assuming you have Windows in your system).
If you need to reinstall Windows, the Microsoft install process will rewrite the
boot sector, and then you will not be able to start GNU/Linux!

 * if a problem arises and you cannot start up GNU/Linux from the hard disk, this
floppy disk will be the only means of starting up GNU/Linux. It contains a fair
number of system tools for restoring a system which has crashed due to a power
failure, an unfortunate typing error, a typo in a password, or any other reason.

When you click on this step, you will be asked to enter a disk inside the drive.
The floppy disk that you will insert must be empty or must only contain data
which you do not need. You will not have to format it; drakX will rewrite the
whole disk."),

doPartitionDisks => 
__("At this point, you need to choose where to install your Mandrake Linux operating
system on your hard drive. If it is empty or if an existing operating system
uses all the space available on it, you need to partition it. Basically,
partitioning a hard drive consists of logically dividing it to create space to
install your new Mandrake Linux system.

Because the effects of the partitioning process are usually irreversible,
partitioning can be intimidating and stressful if you are an inexperienced user.
Hopefully, there is a wizard which simplifies this process. Before beginning,
please consult the manual and take your time.

If you are running the install in Expert mode, you will enter the Mandrake Linux
partitioning tool: DiskDrake;. It allows you to fine-tune your partitions. See
the chapter DiskDrake of the manual; the usage is the same. You can use from the
installation interface the wizards as described here by clicking the button
Wizard from the interface.

If partitions have been already defined (from a previous installation or from
another partitioning tool), you just need choose those to use to install your
Linux system.

If partitions haven't been already defined, you need to create them. To do that,
use the wizard available above. Depending of your hard drive configuration,
several options are available:

 * Use free space: it will simply lead to an automatic partitioning of your blank
drive(s); you won't need to worry any more about it.

 * Use existing partition: the wizard has detected one or more existing Linux
partitions on your hard drive. If you want to keep them, choose this option.

 * Erase entire disk: if you want delete all data and all partitions present on
your hard drive and replace them by your new Mandrake Linux system, you can
choose this option. Be careful with this solution, you will not be able to
revert your choice after confirmation.

 * Use the free space on the Windows partition: if Microsoft Windows is installed
on your hard drive and takes all space available on it, you have to create free
space for Linux data. To do that you can delete your Microsoft Windows partition
and data (see \"Erase entire disk\" or \"Expert mode\" solutions) or resize your
Microsoft Windows partition. Resizing can be performed without loss of any data.
This solution is recommended if you want use both Mandrake Linux and Microsoft
Windows on same computer.

   Before choosing this solution, please understand that the size of your Microsoft
Windows partition will be smaller than at present time. It means that you will
have less free space under Microsoft Windows to store your data or install new
software.

 * Remove Windows: it will simply erase everything on the drive and begin fresh,
partitioning from scratch. All data on your disk will be lost.

   !! If you choose this option, All data on your disk will be lost. !!

 * Expert mode: if you want to partition manually your hard drive, you can choose
this option. Be careful before choosing this solution. It is powerful but it is
very dangerous. You can lose all your data very easily. So, don't choose this
solution unless you know what you are doing."),

exitInstall => 
__("There you are. Installation is now complete and your GNU/Linux system is ready
to use. Just click OK to reboot the system. You can start GNU/Linux or Windows,
whichever you prefer (if you are dual-booting), as soon as the computer has
booted up again.

The Advanced button shows two more buttons to:

 * Generate auto install floppy: to create an install floppy disk that will
automatically perform a whole installation without the help of an operator,
similar to the installation you just configured.

   Note that two different options are available after clicking the button:

    * Replay: This is a partially automated install as the partitioning step (and
only this one) remains interactive.

    * Automated: Fully automated install: the hard disk is completely rewritten, all
data is lost.

   This feature is very handy when installing a great number of similar machines.
See the Auto install section at our WebSite.

 * Save packages selection(*): saves the packages selection as made previously.
Then when doing another install, insert the floppy inside the driver and run the
install going to the help screen F1, and issuing >>linux defcfg=\"floppy\"<<.

(*) You need a FAT formatted floppy (To create one under GNU/Linux type
\"mformat a:\")"),

formatPartitions => 
__("Any partitions that have been newly defined must be formatted for use
(formatting meaning creating a filesystem).

At this time, you may wish to reformat some already existing partitions to erase
the data they contain. If you wish do that, please also select the partitions
you want to format.

Please note that it is not necessary to reformat all pre-existing partitions.
You must reformat the partitions containing the operating system (such as \"/\",
\"/usr\" or \"/var\") but you do not have to reformat partitions containing data
that you wish to keep (typically /home).

Please be careful selecting partitions, after formatting, all data on the
selected partitions will be deleted and you will not be able to recover any of
them.

Click on OK when you are ready to format partitions.

Click on Cancel if you want to choose other partitions to install your new
Mandrake Linux operating system.

Click on Advanced to select partitions on which you want to check for bad
blocks."),

installPackages => 
__("Your new Mandrake Linux operating system is currently being installed. This
operation should take a few minutes (it depends on size you choose to install
and the speed of your computer).

Please be patient."),

miscellaneous => 
__("At this point, it is now time to choose the security level desired for that
machine. As a rule of thumb, the more exposed is the machine, and the more the
data stored in it is crucial the higher the security level should be. However a
higher security level is generally obtained at the expenses of easiness of use.
Refer to the chapter MSEC of the Reference Manual; to get more information about
the meaning of those levels.

If you don't know what to choose, keep the default option."),

multiCD => 
__("The Mandrake Linux spreads among several CDROMs. It may be that drakX has
selected packages on another CDROM than the installation CDROM, and when it
needs that you put another one into the drive, it will eject the current CDROM
and ask you for another one."),

selectInstallClass => 
__("drakX now ask you what installation class you want. Here, you will also choose
whether you want to perform an installation or an upgrade of an existing
Mandrake Linux system. Choose what suits your situation. You can perform an
installation over an existing system, wiping out the old system. You can also do
an upgrade to repair an existing system.

Please choose \"Install\" if there are no previous version of Mandrake Linux
installed or if you wish to use several operating systems.

Please choose \"Update\" if you wish to update an already installed version of
Mandrake Linux.

Depend of your knowledge in GNU/Linux, you can choose one of the following
levels to install or update your Mandrake Linux operating system:

 * Recommended: if you have never installed a GNU/Linux operating system choose
this. Installation will be be very easy and you will be asked only on few
questions.

 * Customized: if you are familiar enough with GNU/Linux, you may choose the
primary usage (workstation, server, development) of your system. You will need
to answer to more questions than in \"Recommended\" installation class, so you
need to know how GNU/Linux works to choose this installation class.

 * Expert: if you have a good knowledge in GNU/Linux, you can choose this
installation class. As in \"Customized\" installation class, you will be able to
choose the primary usage (workstation, server, development). Be very careful
before choose this installation class. You will be able to perform a higly
customized installation. Answer to some questions can be very difficult if you
haven't a good knowledge in GNU/Linux. So, don't choose this installation class
unless you know what you are doing."),

selectKeyboard => 
__("Normally, drakX will have selected the right keyboard for you (depending on the
language you have chosen) and you won't even see this step. However, you might
not have a keyboard which corresponds exactly to your language: for example, if
you are an English speaking Swiss person, you may still want your keyboard to be
a Swiss keyboard. Or if you speak English but are located in Quebec, you may
find yourself in the same situation. In both cases, you will have to go back to
this installation step and select an appropriate keyboard from the list.

All you need to do is select your preferred keyboard layout from the list which
appears in front of you.

If you have a keyboard from another language than the one used by default, click
on the Advanced button. You will be presented the complete list of supported
keyboards."),

selectLanguage => 
__("Please choose your preferred language for installation and system usage.

There is an Advanced button allowing you to select other languages, that will be
installed in the machine so that you can use them later if you need them. If for
example you will host people from Spain on your machine, select English as the
main language in the tree view, and under the advanced section, check the box
corresponding to Spanish|Spain.

As soon as you have selected the language and confirmed with clicking the OK
button, you will automatically go on to the next step."),

selectMouse => 
__("drakX just skips this test unless you purposely click on the corresponding step
on the left. By default, drakX sees your mouse as a two-button mouse and
emulates the third button, and knows whether it's PS/2, serial or USB.

Perhaps this is not what you want. In that case, you just have to select the
right type for your mouse in the list which appears.

You can now test your mouse. Use buttons and wheel to verify if settings are
good. If not, you can click on \"Cancel\" to choose another driver."),

setRootPassword => 
__("This is the most crucial decision point for the security of your GNU/Linux
system: you are going to have to enter the Root password. Root is the system
administrator and is the only one authorized to make updates, add users, change
the overall system configuration, and so on. In short, root can do everything!
That is why you have to choose a password which is difficult to guess; drakX
will tell you if it is too easy. As shown, you can choose not to enter a
password, but we strongly advise you to enter one, if only for one reason: do
not think that because you booted GNU/Linux, your other operating systems are
safe from mistakes. That's not true since Root can overcome all limitations and
unintentionally erase all data on partitions by carelessly accessing the
partitions themselves!

The password should be a mixture of alphanumeric characters and at least 8
characters long. It should never be written down.

Do not make the password too long or complicated, though: you must be able to
remember it without too much effort.

You will have to type the password twice a typing error in the first attempt
could be a problem if you repeat it since the ``incorrect'' password is now
required when you connect up to the system.

Depending on your local network configuration, you may or may not use NIS. If
you don't know, ask your system administrator. If you use NIS, check the option
Use NIS. When you press OK, you will then have to fill in the necessary
information."),

setupBootloader => 
__("LILO and GRUB are boot loaders for GNU/Linux. This stage is normally totally
automated. In fact, drakX will analyze the disk boot sector and will act
accordingly depending on what it finds here:

 * if it finds a Windows boot sector, it will replace it with a GRUB/LILO boot
sector so that you can start GNU/Linux or Windows;

 * if it finds a GRUB or LILO boot sector, it will replace it with a new one;

If in doubt, drakX will display a dialog with various options.

 * Bootloader to use: you get here three choices:

    * LILO with graphical menu: if you prefer LILO with its graphical interface.

    * Grub: if you prefer GRUB (text menu).

    * LILO with text menu: if you prefer LILO with its text menu interface.

 * Boot device: In most cases, you will not change the default (/dev/hda), but if
you prefer, the bootloader can be installed on the second hard drive (/dev/hdb),
or even on a floppy disk (/dev/fd0).

 * Delay before booting default image: When rebooting the computer, this is the
delay granted to the user to choose in the boot loader menu, another boot entry
than the default one.

!! Beware that if you choose not to install a bootloader (by selecting Cancel
here), you must ensure that you have a way to boot your Mandrake Linux system!
Also be sure about what you are doing if you change any of the options here. !!

Clicking the Advanced button in this dialog will offer many advanced options
reserved to the expert user.

Mandrake Linux installs its own bootloader, which will let you boot either
GNU/Linux or any other operating systems which you have on your system.

If there is another operating system installed on your machine, it'll be
automatically added to the boot menu. Here you can choose to fine-tune the
existing options. Double-clicking on an existing entry allows you to change its
parameters or remove it; Add creates a new entry; and Done goes onto next
installation step."),

setupSCSI => 
__("drakX then goes on to detecting all hard disks present on your computer. It will
also scan for one or more PCI SCSI card(s) on your system, if you have any. If
such a device is found, drakX will automatically install the right driver.

Should it fail, you are anyway asked whether you have a SCSI card or not. Answer
Yes to choose your card in a list or No if you have no SCSI hardware. If you are
not sure you can also check the list of hardware in your machine by selecting
See hardware info and clicking OK.

If you have to manually specify your adapter, DrakX will ask if you want to
specify options for it. You should allow DrakX to probe the hardware for the
options. This usually works well.

If not, you will need to provide options to the driver. Please review the User
Guide (chapter 3, section \"Collective informations on your hardware\") for
hints on retrieving this information from hardware documentation, from the
manufacturer's Web site (if you have Internet access) or from Microsoft Windows
(if you have it on your system)."),

summary => 
__("Here are presented various parameters related to your machine. Depending on your
installed hardware you may or not, see the following entries:

 * Mouse: mouse Check the current mouse configuration and click on the button to
change it if necessary.

 * Keyboard: keyboard Check the current keyboard map configuration and click on
the button to change that if necessary.

 * Timezone: timezone DrakX, by default, guesses your timezone from the language
you have chosen. But here again, as for the keyboard choice, you may not be in
the country which the chosen language suggests, so you may need to click on the
Timezone button so that you can configure the clock according to the time zone
you are in.

 * Printer: Clicking on the No Printer button, will open the printer
configuration wizard..

 * Sound card: If a sound card has been detected on your system, it is displayed
here. No modification possible at installation time.

 * TV card: If a TV card has been detected on your system, it is displayed here.
No modification possible at installation time.

 * ISDN card: If an ISDN card has been detected on your system, it is displayed
here. You can click on the button to change the associated parameters."),
);
