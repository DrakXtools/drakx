package help;

use common qw(:common);

%steps = (
selectLanguage =>
 __("Choose preferred language for install and system usage."),

selectKeyboard =>
 __("Choose on the list of keyboards, the one corresponding to yours"),

selectPath =>
 __("Choose \"Installation\" if there are no previous versions of Linux
installed, or if you wish use to multiple distributions or versions.

Choose \"Update\" if you wish to update a previous version of Mandrake
Linux: 5.1 (Venice), 5.2 (Leeloo), 5.3 (Festen) or 6.0 (Venus)."),

selectInstallClass =>
 __("Select:
  - Beginner: If you have not installed Linux before, or wish to install
the distribution elected \"Product of the year\" for 1999, click here.
  - Developer: If you are familiar with Linux and will be using the
computer primarily for software development, you will find happiness
here.
  - Server: If you wish to install a general purpose server, or the
Linux distribution elected \"Distribution/Server\" for 1999, select
this.
  - Expert: If you know GNU/Linux and want to perform a highly
customized installation, this Install Class is for you."),

setupSCSI =>
 __("The system did not detect a SCSI card. If you have one (or several)
click on \"Yes\" and choose the module(s) to be tested. Otherwise,
select \"No\".

If you don't know if your computer has SCSI interfaces, consult the
original documentation delivered with the computer, or if you use
Microsoft Windows 95/98, inspect the information available via the \"Control
panel\", \"System's icon, \"Device Manager\" tab."),

partitionDisks =>
 __("At this point, hard drive partitions must be defined. (Unless you
are overwriting a previous install of Linux and have already defined
your hard drives partitions as desired.) This operation consists of
logically dividing the computer's hard drive capacity into separate
areas for use. Two common partition are: \"root\" which is the point at
which the filesystem's directory structure starts, and \"boot\", which
contains those files necessary to start the operating system when the
computer is first turned on. Because the effects of this process are
usually irreversible, partitioning can be intimidating and stressful to
the inexperienced. DiskDrake simplifies the process so that it need not
be. Consult the documentation and take your time before proceeding."),

formatPartitions =>
 __("Any partitions that have been newly defined must be formatted for
use. At this time, you may wish to re-format some pre-existing
partitions to erase the data they contain. Note: it is not necessary to
re-format pre-existing partitions, particularly if they contain files or
data you wish to keep. Typically retained are: /home and /usr/local."),

choosePackages =>
 __("You may now select the packages you wish to install.

Please note that some packages require the installation of others. These
are referred to as package dependencies. The packages you select, and
the packages they require will automatically be added to the
installation configuration. It is impossible to install a package
without installing all of its dependencies.

Information on each category and specific package is available in the
area titled \"Info\". This is located above the buttons: [confirmation]
[selection] [unselection]."),

doInstallStep =>
 __("The packages selected are now being installed. This operation
should only take a few minutes."),

configureMouse =>
 __("Help"),

configureNetwork =>
 __("Help"),

configureTimezone =>
 __("Help"),

configureServices =>
 __("Help"),

configurePrinter =>
 __("Help"),

setRootPassword =>
 __("An administrator password for your Linux system must now be
assigned. The password must be entered twice to verify that both
password entries are identical.

Choose this password carefully. Only persons with access to an
administrator account can maintain and administer the system.
Alternatively, unauthorized use of an administrator account can be
extremely dangerous to the integrity of the system, the data upon it,
and other systems with which it is interfaced. The password should be a
mixture of alphanumeric characters and a least 8 characters long. It
should never be written down. Do not make the password too long or
complicated that it will be difficult to remember.

When you login as Administrator, at \"login\" type \"root\" and at
\"password\", type the password that was created here."),

addUser =>
 __("You can now authorize one or more people to use your Linux
system. Each user account will have their own customizable environment.

It is very important that you create a regular user account, even if
there will only be one principle user of the system. The administrative
\"root\" account should not be used for day to day operation of the
computer.  It is a security risk.  The use of a regular user account
protects you and the system from yourself. The root account should only
be used for administrative and maintenance tasks that can not be
accomplished from a regular user account."),

createBootdisk =>
 __("Help"),

setupBootloader =>
 __("You need to indicate where you wish
to place the information required to boot to Linux.

Unless you know exactly what you are doing, choose \"First sector of
drive\"."),

configureX =>
 __("It is now time to configure the video card and monitor
configuration for the X Window Graphic User Interface (GUI). First
select your monitor. Next, you may test the configuration and change
your selections if necessary."),
exitInstall =>
 __("Help"),
);

#- ################################################################################
%steps_long = (
selectLanguage =>
 __("Choose preferred language for install and system usage."),

selectKeyboard =>
 __("Choose on the list of keyboards, the one corresponding to yours"),

selectPath =>
 __("Choose \"Installation\" if there are no previous versions of Linux
installed, or if you wish use to multiple distributions or versions.

Choose \"Update\" if you wish to update a previous version of Mandrake
Linux: 5.1 (Venice), 5.2 (Leeloo), 5.3 (Festen) or 6.0 (Venus)."),

selectInstallClass =>
 __("Select:
  - Beginner: If you have not installed Linux before, or wish to install
the distribution elected \"Product of the year\" for 1999, click here.
  - Developer: If you are familiar with Linux and will be using the
computer primarily for software development, you will find happiness
here.
  - Server: If you wish to install a general purpose server, or the
Linux distribution elected \"Distribution/Server\" for 1999, select
this.
  - Expert: If you know GNU/Linux and want to perform a highly
customized installation, this Install Class is for you."),

setupSCSI =>
 __("The system did not detect a SCSI card. If you have one (or several)
click on \"Yes\" and choose the module(s) to be tested. Otherwise,
select \"No\".

If you don't know if your computer has SCSI interfaces, consult the
original documentation delivered with the computer, or if you use
Microsoft Windows 95/98, inspect the information available via the \"Control
panel\", \"System's icon, \"Device Manager\" tab."),

partitionDisks =>
 __("At this point, hard drive partitions must be defined. (Unless you
are overwriting a previous install of Linux and have already defined
your hard drives partitions as desired.) This operation consists of
logically dividing the computer's hard drive capacity into separate
areas for use. Two common partition are: \"root\" which is the point at
which the filesystem's directory structure starts, and \"boot\", which
contains those files necessary to start the operating system when the
computer is first turned on. Because the effects of this process are
usually irreversible, partitioning can be intimidating and stressful to
the inexperienced. DiskDrake simplifies the process so that it need not
be. Consult the documentation and take your time before proceeding."),

formatPartitions =>
 __("Any partitions that have been newly defined must be formatted for
use. At this time, you may wish to re-format some pre-existing
partitions to erase the data they contain. Note: it is not necessary to
re-format pre-existing partitions, particularly if they contain files or
data you wish to keep. Typically retained are: /home and /usr/local."),

choosePackages =>
 __("You may now select the packages you wish to install.

Please note that some packages require the installation of others. These
are referred to as package dependencies. The packages you select, and
the packages they require will automatically be added to the
installation configuration. It is impossible to install a package
without installing all of its dependencies.

Information on each category and specific package is available in the
area titled \"Info\". This is located above the buttons: [confirmation]
[selection] [unselection]."),

doInstallStep =>
 __("The packages selected are now being installed. This operation
should only take a few minutes."),

configureMouse =>
 __("Help"),

configureNetwork =>
 __("Help"),

configureTimezone =>
 __("Help"),

configureServices =>
 __("Help"),

configurePrinter =>
 __("Help"),

setRootPassword =>
 __("An administrator password for your Linux system must now be
assigned. The password must be entered twice to verify that both
password entries are identical.

Choose this password carefully. Only persons with access to an
administrator account can maintain and administer the system.
Alternatively, unauthorized use of an administrator account can be
extremely dangerous to the integrity of the system, the data upon it,
and other systems with which it is interfaced. The password should be a
mixture of alphanumeric characters and a least 8 characters long. It
should never be written down. Do not make the password too long or
complicated that it will be difficult to remember.

When you login as Administrator, at \"login\" type \"root\" and at
\"password\", type the password that was created here."),

addUser =>
 __("You can now authorize one or more people to use your Linux
system. Each user account will have their own customizable environment.

It is very important that you create a regular user account, even if
there will only be one principle user of the system. The administrative
\"root\" account should not be used for day to day operation of the
computer.  It is a security risk.  The use of a regular user account
protects you and the system from yourself. The root account should only
be used for administrative and maintenance tasks that can not be
accomplished from a regular user account."),

createBootdisk =>
 __("Help"),

setupBootloader =>
 __("You need to indicate where you wish
to place the information required to boot to Linux.

Unless you know exactly what you are doing, choose \"First sector of
drive\"."),

configureX =>
 __("It is now time to configure the video card and monitor
configuration for the X Window Graphic User Interface (GUI). First
select your monitor. Next, you may test the configuration and change
your selections if necessary."),
exitInstall =>
 __("Help"),
);
