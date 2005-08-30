# EDIT IN CVS NOT IN SOURCE PACKAGE (NO PATCH ALLOWED).

Summary: The drakxtools (XFdrake, diskdrake, keyboarddrake, mousedrake...)
Name:    drakxtools
Version: 10.3
Release: 0.50mdk
Url: http://www.mandrivalinux.com/en/drakx.php3
Source0: %name-%version.tar.bz2
License: GPL
Group: System/Configuration/Other
Requires: %{name}-newt = %version-%release, perl-Gtk2 >= 1.072-1mdk, perl-Glib >= 1.072-1mdk, xtest, font-tools, usermode >= 1.63-5mdk, perl-MDK-Common >= 1.1.23, mandrake-doc-common >= 9.2-5mdk, perl-Net-DBus
Requires: foomatic-db-engine
Requires: drakconf-icons
Conflicts: drakconf < 10.3-0.6mdk
Conflicts: rpmdrake < 2.1-29mdk
Conflicts: mandrake_doc-drakxtools-en < 9.2, mandrake_doc-drakxtools-es < 9.2, mandrake_doc-drakxtools-fr < 9.2
Conflicts: bootloader-utils < 1.8-4mdk, bootsplash < 2.1.7-1mdk
BuildRequires: gettext, gtk+2-devel, ldetect-devel >= 0.5.3-1mdk, ncurses-devel, newt-devel, perl-devel >= 1:5.8.0-20mdk, libext2fs-devel, perl-MDK-Common-devel >= 1.1.8-3mdk
BuildRequires: rpm-devel
BuildRoot: %_tmppath/%name-buildroot
Provides: draksec
Obsoletes: draksec
%define _requires_exceptions perl(Net::FTP)\\|perl(Time::localtime)\\|perl(URPM)

%package newt
Summary: The drakxtools (XFdrake, diskdrake, keyboarddrake, mousedrake...)
Group: System/Configuration/Other
Requires: perl-base >= 2:5.8.6-1mdk, urpmi >= 4.6.13, usermode-consoleonly >= 1.44-4mdk, msec >= 0.38-5mdk
Requires: module-init-tools
Requires: %{name}-backend = %version-%release
Requires: monitor-edid >= 1.5
Requires: netprofile
Obsoletes: diskdrake kbdconfig mouseconfig printtool setuptool drakfloppy
Provides: diskdrake, kbdconfig mouseconfig printtool setuptool, drakfloppy = %version-%release
Provides: perl(Newt::Newt)
Provides: perl(network::isdn_consts)

%package backend
Summary: Drakxtools libraries and background tools 
Group: System/Configuration/Other
Requires: ldetect-lst >= 0.1.71
Requires: dmidecode
Conflicts: drakxtools-newt < 10-51mdk


%package http
Summary: The drakxtools via http
Group: System/Configuration/Other
Requires: %{name}-newt = %version-%release, perl-Net_SSLeay >= 1.22-1mdk, perl-Authen-PAM >= 0.14-1mdk, perl-CGI >= 2.91-1mdk
Requires(pre): rpm-helper
Requires(post): rpm-helper

%package -n drakx-finish-install
Summary: First boot configuration
Group: System/Configuration/Other
Requires: %{name} = %version-%release

%package -n harddrake
Summary: Main Hardware Configuration/Information Tool
Group: System/Configuration/Hardware
Requires: %{name}-newt = %version-%release
Requires: hwdb-clients
Obsoletes: kudzu, kudzu-devel, libdetect0, libdetect0-devel, libdetect-lst, libdetect-lst-devel, detect, detect-lst
Provides: kudzu, kudzu-devel, libdetect0, libdetect0-devel, libdetect-lst, libdetect-lst-devel, detect, detect-lst
Requires(pre): rpm-helper
Requires(post): rpm-helper

%package -n harddrake-ui
Summary: Main Hardware Configuration/Information Tool
Group: System/Configuration/Hardware
Requires: %name = %version-%release
Requires: sane-backends

%description
Contains many Mandriva Linux applications simplifying users and
administrators life on a Mandriva Linux machine. Nearly all of
them work both under XFree (graphical environment) and in console
(text environment), allowing easy distant work.

drakbug: interactive bug report tool

drakbug_report: help find bugs in DrakX

drakclock: date & time configurator

drakfloppy: boot disk creator

drakfont: import fonts in the system

draklog: show extracted information from the system logs

draknet_monitor: connection monitoring

drakperm: msec GUI (permissions configurator)

drakprinter: detect and configure your printer

draksec: security options managment / msec frontend

draksplash: bootsplash themes creation

drakTermServ: terminal server configurator

listsupportedprinters: list printers

net_applet: applet to check network connection

%description backend
See package %name

%description newt
Contains many Mandriva Linux applications simplifying users and
administrators life on a Mandriva Linux machine. Nearly all of
them work both under XFree (graphical environment) and in console
(text environment), allowing easy distant work.

adduserdrake: help you adding a user

diskdrake: DiskDrake makes hard disk partitioning easier. It is
graphical, simple and powerful. Different skill levels are available
(newbie, advanced user, expert). It's written entirely in Perl and
Perl/Gtk. It uses resize_fat which is a perl rewrite of the work of
Andrew Clausen (libresize).

drakauth: configure authentification (LDAP/NIS/...)

drakautoinst: help you configure an automatic installation replay

drakbackup: backup and restore your system

drakboot: configures your boot configuration (Lilo/GRUB,
Bootsplash, X, autologin)

drakconnect: LAN/Internet connection configuration. It handles
ethernet, ISDN, DSL, cable, modem.

drakfirewall: simple firewall configurator

drakgw: internet connection sharing

drakkeyboard: configure your keyboard (both console and X)

draklocale: language configurator, available both for root
(system wide) and users (user only)

drakmouse: autodetect and configure your mouse

drakproxy: proxies configuration

drakscanner: scanner configurator

draksound: sound card configuration

drakx11: menu-driven program which walks you through setting up
your X server; it autodetects both monitor and video card if
possible

drakxservices: SysV services and daemons configurator

drakxtv: auto configure tv card for xawtv grabber

lsnetdrake: display available nfs and smb shares

lspcidrake: display your pci information, *and* the corresponding
kernel module

%description http
This add the capability to be runned behind a web server to the drakx tools.
See package %name


%description -n drakx-finish-install
For OEM-like duplications, it allows at first boot:
- network configuration
- creating users
- setting root password
- choosing authentication


%description -n harddrake
The harddrake service is a hardware probing tool run at system boot
time to determine what hardware has been added or removed from the
system.
It then offer to run needed config tool to update the OS
configuration.


%description -n harddrake-ui
This is the main configuration tool for hardware that calls all the
other configuration tools.
It offers a nice GUI that show the hardware configuration splitted by
hardware classes.


%prep
%setup -q

%build
%make CFLAGS="$RPM_OPT_FLAGS"

%install
rm -rf $RPM_BUILD_ROOT

%make PREFIX=$RPM_BUILD_ROOT install
mkdir -p $RPM_BUILD_ROOT/{%_initrddir,%_sysconfdir/{X11/xinit.d,sysconfig/harddrake2}}
touch $RPM_BUILD_ROOT/etc/sysconfig/harddrake2/previous_hw

dirs1="usr/lib/libDrakX usr/share/libDrakX"
(cd $RPM_BUILD_ROOT ; find $dirs1 usr/bin usr/sbin ! -type d -printf "/%%p\n")|egrep -v 'bin/.*harddrake' > %{name}.list
(cd $RPM_BUILD_ROOT ; find $dirs1 -type d -printf "%%%%dir /%%p\n") >> %{name}.list

perl -ni -e '/dbus_object\.pm|network\/(ifw|monitor)\.pm|clock|drak(backup|bug|clock|floppy|font|hosts|ids|log|net_monitor|nfs|perm|printer|sec|splash|TermServ)|gtk|icons|logdrake|net_applet|net_monitor|pixmaps|printer|roam|xf86misc|\.png$/ ? print STDERR $_ : print' %{name}.list 2> %{name}-gtk.list
perl -ni -e '/http/ ? print STDERR $_ : print' %{name}.list 2> %{name}-http.list
perl -ni -e 'm!lib/libDrakX|bootloader-config|fileshare|lsnetdrake|drakupdate_fstab|rpcinfo|serial_probe! && !/newt/i ? print STDERR $_ : print' %{name}.list 2> %{name}-backend.list
perl -ni -e '/finish-install/ ? print STDERR $_ : print' %{name}.list 2> finish-install.list

#mdk menu entry
mkdir -p $RPM_BUILD_ROOT/%_menudir

cat > $RPM_BUILD_ROOT%_menudir/drakxtools-newt <<EOF
?package(drakxtools-newt): \
	needs="X11" \
	section="System/Configuration/Other" \
	title="LocaleDrake (System)" \
	longtitle="System wide language configurator" \
	command="/usr/bin/drakconf --start-with=Localization" \
	icon="localedrake.png"

?package(drakxtools-newt): \
	needs="X11" \
	section="System/Configuration/Other" \
	title="LocaleDrake (User)" \
	longtitle="Language configurator" \
	command="/usr/bin/localedrake" \
	icon="localedrake.png"

EOF
 
cat > $RPM_BUILD_ROOT%_menudir/harddrake-ui <<EOF
?package(harddrake-ui):\
	needs="X11"\
	section="Configuration/Hardware"\
	title="HardDrake"\
	longtitle="Hardware Central Configuration/information tool"\
	command="/usr/sbin/harddrake2"\
	icon="harddrake.png"
EOF

cat > $RPM_BUILD_ROOT%_menudir/net_applet <<EOF
?package(drakxtools):\
        needs="X11"\
        section="System/Monitoring"\
        title="NetApplet"\
        longtitle="Network monitoring applet"\
        command="/usr/bin/net_applet --force"\
        icon="/usr/share/libDrakX/pixmaps/connected.png"
EOF

cat > $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/harddrake2 <<EOF
#!/bin/sh
exec /usr/share/harddrake/service_harddrake X11
EOF

cat > $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/net_applet <<EOF
#!/bin/sh
DESKTOP=\$1
case \$DESKTOP in
   KDE|GNOME|IceWM|Fluxbox|XFce4) exec /usr/bin/net_applet;;
esac
EOF

mv $RPM_BUILD_ROOT%_sbindir/service_harddrake_confirm $RPM_BUILD_ROOT%_datadir/harddrake/confirm

chmod +x $RPM_BUILD_ROOT{%_datadir/harddrake/{conf*,service_harddrake},%_sysconfdir/X11/xinit.d/{harddrake2,net_applet}}
# temporary fix until we reenable this feature
rm -f $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/harddrake2

%find_lang libDrakX
cat libDrakX.lang >> %name.list

%clean
rm -rf $RPM_BUILD_ROOT

%post
%update_menus
[[ ! -e %_sbindir/kbdconfig ]] && %__ln_s -f keyboarddrake %_sbindir/kbdconfig
[[ ! -e %_sbindir/mouseconfig ]] && %__ln_s -f mousedrake %_sbindir/mouseconfig
[[ ! -e %_bindir/printtool ]] && %__ln_s -f ../sbin/printerdrake %_bindir/printtool
:

%postun
%clean_menus
for i in %_sbindir/kbdconfig %_sbindir/mouseconfig %_bindir/printtool;do
    [[ -L $i ]] && %__rm -f $i
done
:

%post http
%_post_service drakxtools_http

%preun http
%_preun_service drakxtools_http

%post newt
%update_menus

%postun newt
%clean_menus

%post -n harddrake-ui
%update_menus

%postun -n harddrake-ui
%clean_menus

%post -n harddrake
%_post_service harddrake

%preun -n harddrake
%_preun_service harddrake

%postun -n harddrake
file /etc/sysconfig/harddrake2/previous_hw | fgrep -q perl && %_datadir/harddrake/convert || :

%files backend -f %{name}-backend.list
%defattr(-,root,root)
%config(noreplace) /etc/security/fileshare.conf
%attr(4755,root,root) %_sbindir/fileshareset

%files newt -f %name.list
%defattr(-,root,root)
%_menudir/drakxtools-newt
%doc diskdrake/diskdrake.html
%_iconsdir/localedrake.png
%_iconsdir/large/localedrake.png
%_iconsdir/mini/localedrake.png
%_mandir/*/*

%files -f %{name}-gtk.list
%defattr(-,root,root)
/usr/X11R6/bin/*
%_sysconfdir/X11/xinit.d/net_applet
%_menudir/net_applet

%files -n harddrake
%defattr(-,root,root)
%config(noreplace) %_initrddir/harddrake
%dir /etc/sysconfig/harddrake2/
%config(noreplace) /etc/sysconfig/harddrake2/previous_hw
%dir %_datadir/harddrake/
%_datadir/harddrake/*
#%_sysconfdir/X11/xinit.d/harddrake2

%files -n harddrake-ui
%defattr(-,root,root)
%dir /etc/sysconfig/harddrake2/
%_sbindir/harddrake2
%_datadir/pixmaps/harddrake2
%_menudir/harddrake-ui
%_iconsdir/large/harddrake.png
%_iconsdir/mini/harddrake.png
%_iconsdir/harddrake.png

%files -n drakx-finish-install
%defattr(-,root,root)
%config(noreplace) %_sysconfdir/sysconfig/finish-install
%_sysconfdir/X11/xsetup.d/finish-install.xsetup
%_sbindir/finish-install

%files http -f %{name}-http.list
%defattr(-,root,root)
%dir %_sysconfdir/drakxtools_http
%config(noreplace) %_sysconfdir/pam.d/miniserv
%_sysconfdir/init.d/drakxtools_http
%config(noreplace) %_sysconfdir/drakxtools_http/conf
%config(noreplace) %_sysconfdir/drakxtools_http/authorised_progs
%config(noreplace) %_sysconfdir/logrotate.d/drakxtools-http

%changelog
* Tue Aug 30 2005 Olivier Blin <oblin@mandriva.com> 10.3-0.50mdk
- drakroam: rewrite it to use wpa_supplicant and mandi
- net_applet:
  o use new wireless icons
  o display wireless link icon in tray icon if connected
    through wireless
  o check wireless every 20 seconds only
  o detect use vlan/alias interfaces (thanks to Michael Scherer)
  o rephrase IFW interactive/automatic checkbox label in
    the settings menu
- generic wireless:
  o configure wpa_supplicant correctly for shared or passwordless
    connections
  o wpa_supplicant may list some networks twice, handle it
- drakconnect:
  o restart associated ethernet device for dsl connections needing it
  o rephrase "DSL connection type" message, the preselected type
    has better to be kept
  o don't blacklist ifplugd for pcmcia interfaces
  o use lower case 'i' for iwconfig/iwpriv/iwspy (#18031)
- draksplash: restrict mouse motion to image
- drakfont: allow to import Windows Fonts (#15531)
- printerdrake (Till):
  o when setting up new queue with HPLIP old HPOJ, delete config
  o restart CUPS after installing HPLIP for a network printer
  o autosetupprintqueues: use correct language
  o disable margins with Gutenprint
  o removed "Do not print testy page" in test page step of add printer
    wizard (bug #15861)
  o fix message window in the case that no local printer was found
    when running the add printer wizard in beginner's mode (bug #16757)
- drakhosts/draksambashare/draknfs (Antoine Ginies): use new icons
- draknfs (Antoine Ginies):
  o in case of all_squash use anongid=65534 and anongid=65534
  o create dir if it does not exist
  o fix typo (#17978)
- draksambashare (Antoine Ginies):
  o add popup menu to easily modify/remove share
  o add printer support, notebook support, and user tab
- interactive layer (Pixel): fix "Cancel" in ask_okcancel
- bootlader-config (Pixel):
  o vga_fb expects the vga mode, not a boolean
  o propose to create a default bootloader configuration when no
    bootloader is found
  o conectiva 10's grub detection
  o install grub stage files in install_grub(), not write_grub()
    (#17830, thanks to herton)
- XFdrake (Pixel): handle nvidia's libglx.so being now in extensions/nvidia
- drakTermServ (Stew): reverse xdm-config logic for XDMCP
- drakfirewall (Thierry): use banner and icon
- harddrake (Thierry):
  o add more icons
  o sync with latest saa7134 driver
  o ldetect runs gzip now, reduce time spent by using a cache
  o find driver of host controller from sysfs in all cases (not just usb-storage)
- diskdrake: (Thierry)
  o document 'encrypted' option (#13562, Per Oyvind Karlsen)
  o Grub really is named GRUB (it makes the pull-down more consistent)

* Wed Aug 24 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.49mdk
- interactive layer: do not crash when given an empty list (blino, #17718)
- diskdrake, XFdrake: misc bug fixes (pixel)
- drakbackup: enable tape hardware compression (stew, #17565)
- draknetconnect (blino):
  o fix network restart condition for 6to4
  o use wext driver for ipw cards in wpa_supplicant
- drakids (blino):
  o add log tab
  o allow to clear logs
- drakTermServ (stew, Diogo):
  o don't use "X -ac" for thin clients
  o clear main window on tab change
  o offer to install i586 kernel for old clients
  o progress display while creating all kernel images
  o move dhcpd config to more logical area
- net_applet (blino):
  o allow to whitelist attackers in popup
  o show attacks of unknown type
  o stop icon blinking when drakids is run or clear logs, or when an
    Interactive Firewall alert isn't processed
  o present drakids window on click on menu if drakids is already run
- printerdrake (till):
  o fixed problem of current printer/driver not chosen in the printer
    editing menu (in expert mode and with manufacturer-supplied PPD)
  o support for one pre-built PPD:
    * for non-PostScript drivers (eg: PCL-XL PPDs from Ricoh)
    * being linked from multiple printer database entries

* Mon Aug 22 2005 Olivier Blin <oblin@mandriva.com> 10.3-0.48mdk
- from Pixel:
  o mousedrake: don't use a udev rule, this doesn't always work
    for input/mice, and never for ttySL0
  o fix Mandrivalinux to Mandriva Linux in description
    (Eskild Hustvedt)
  o diskdrake: enhance grub device.map parsing (#17732)

* Sat Aug 20 2005 Olivier Blin <oblin@mandriva.com> 10.3-0.47mdk
- net_applet:
  o use Gtk2::NotificationBubble for IFW
  o do not crash when unexpanding details in IFW window
  o do not fail to start if messagebus is down
  o do not show drakids in menu if IFW isn't available
- drakids: display protocol as text
- drakconnect: install bpalogin if needed only
- localedrake (Thierry): enable to select scim+pinyin
- drakTermServ (Stew): ignore config file for First Time Wizard,
  assume defaults (#17673)

* Fri Aug 19 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.46mdk
- drakconnect: only install bpalogin if needed (blino)
- drakTermServ (stew):
  o client tree edit fix (#17653),
  o write to floppy (#17655)
- harddrake service: use the new way to blacklist modules (#12731)
- harddrake GUI: only install HW packages of high priority
- net_applet: cosmetic fixes (blino)
- printerdrake: removed stuff for automatic print queue setup when
  starting CUPS (till)

* Thu Aug 18 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.45mdk
- rpmlint fixes
- diskdrake: better reiser4 support (pixel)
- drakids (blino):
  o use "Allowed addresses" instead of "Attacker" in whitelist
  o improve list removal workaround using a copying grep
- keyboardrake: revert removal of keyboard layout weight of zh.
  (Funda Wang, #16873)
- printerdrake: misc enhancements
- net_applet (blino):
  o use balloons to notify attacks
  o show attack window on balloon click

* Thu Aug 11 2005 Flavio Bruno Leitner <flavio@mandriva.com> 10.3-0.44mdk 
- changed requires from modutils to module-init-tools

* Wed Aug 10 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.43mdk
- diskdrake: fix misc bugs with encrypted folders (pixel, #16893 & #17142) 
- harddrake service: speedup startup on some old machines
- mousedrake: do write an udev rule for serial mice (pixel, #17114)

* Tue Aug  9 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.42mdk
- localedrake: fix switch to a language that need an input methd (#17352)
- diskdrake (pixel):
  o differentiate (nfs)servers on ip first to have less dups (#17236)
  o fix update boot loader on renumbering partitions (#16786)
  o write /etc/mdadm.conf when creating a new md (#15502)
- drakconnect (blino):
  o do not write aliases interfaces in iftab
  o handle access point roaming using wpa_supplicant
  o initial IPv6 support (6to4 tunnel)
  o keep MS_DNS1, MS_DNS2 and DOMAIN variables in ifcfg files
  o overwrite previous wpa_supplicant entries with same SSID or BSSID
- drakhosts, draknfs: do not crash when config file is empty (antoine,
  #17255)

* Fri Aug  5 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.41mdk
- drakconnect (blino):
  o allow to use WEP keys in wpa_supplicant
  o use ifplugd for wireless interfaces
  o use ifup/ifdown with the boot option to handle ifplugd
- draksplash (blino):
  o handle progress bar color
  o install jpegtopnm if needed
- drakTermServ: GUI enhancements (stew)
- drakUPS: do not detect some keyboards as UPSes
- drakxtv: fix configuring drivers other than bttv
- autosetupprintqueues: fix logs (till, #17264)
- harddrake:
  o do not detect PCI/USB modems twice (as modems and as unknown
    devices)
  o run keyboardrake for keyboards
  o do not offer to configure driver of keyboards and mice (#17254)
- localedrake: fix global KDE config when switching locales and when
  font changes whereas KDE charset doesn't (Mashrab Kuvatov)
- printerdrake: Added special handling for the "capt" driver (Canon
  LBP-810/1120 winprinters) (till)
- scannerdrake: fix detecting scanners
- XFdrake (pixel): don't have empty ModeLines lying around (#16960)

* Wed Aug  3 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.40mdk
- do not write rules conflicting with udev ones
- don't package dbus stuff && finish-install in drakxtools-backend
- diskdrake: minimal reiser4 support (pixel, #15839)
- drakclock: add some ntp servers from brazil (pixel, #16879)
- drakconnect (blino):
  o apply gateway modifications (#17260)
  o fix applying DNS change (#17253)
  * fix for new sysfs tree architecture
- drakgw: make sure shorewall gets enabled (blino, #17238)
- draksound: handle a couple more drivers
- net_applet: put wireless items in a submenu (blino)

* Fri Jul 29 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.39mdk
- do not detect WingMan & Logitech devices as UPSes (#16995, #16994)
- drakconnect: fix testing network connection (blino)
- draksound: emphasize if drivers are OSS or ALSA based (#15902)
- localedrake: fixed KDE font for extended cyrillic languages (pablo)
- net_applet: add support for active firewall (blino)
- printerdrake (till):
  o fix configuring sane
  o print queue auto setup

* Wed Jul 27 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.38mdk
- enforce GNOME button order when not under KDE
- make more dialogs transient if possible
- drakconnect (blino):
  o fix ISDN configuration
  o fix writing module aliases
  o write hosts in correct order in /etc/hosts (#15039)
  o do not kill mcc (#17024)
- drakfirewall (blino):
  o don't write alias interfaces in shorewall interfaces file
  o run shorewall clear if firewall is stopped (#17046)
- drakhosts, draknfs: improved GIU (antoine)
- draksound: fix intel support (#16944)
- mousedrake: fix alps touchpads detection (blino)
- net_applet (blino):
  o enable activefw
  o misc wireless enhancements
- XFdrake: adopt to new mandriva-theme package naming schema (Funda
  Wang, #16977)

* Tue Jul 19 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.37mdk
- fix layout for programms embedded with their menubar (eg: harddrake,
  printerdrake, rpmdrake) (#13931)
- draknfs: remove ipnet/32 in access_list (antoine)
- harddrake2: really reap zombie children and let be able to run a
  second config tool again (#16851)
- net_applet: misc improvments (blino)

* Mon Jul 18 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.36mdk
- drakconnect: write firewire mac_addresses again (oblin)
- draknfs:
  o fix displaying help the second time
  o make sub dialogs modal and transcient to their main window
  o advanced options' help:
    * improve layout
    * fix text phrasing
    * make it consistent with the GUI (ensure labels are named the
      same way on buttons and in help) and speak about labels not
      actual option names in config file
- drakhosts:
  o make sub dialogs modal and transcient to their main window
  o improve layout (hidden buttons)
- draksplash: do not die if loaded file isn't an image (blino, #16829)
- drakxtv: really display sg when there's no card (blino, #16716)
- require perl-Net-DBus (for net_applet and drakids) (blino)

* Fri Jul 15 2005 Olivier Blin <oblin@mandriva.com> 10.3-0.35mdk
- net_applet: initial wireless support
- drakgw: move wait message after package installation
  (or else the interface isn't active)
- draknfs (Antoine):
  o move menu above banner
  o use expander to show/hide advanced options,
  o remove empty value in advanced option
  o change draknfs tittle (thx Fabrice Facorat)
  o add exit on ok button
  o ensure nfs-utils is installed
- drakTermServ (Stew): add/remove entries to default PXE config

* Mon Jul 11 2005 Olivier Blin <oblin@mandriva.com> 10.3-0.34mdk
- really write modem/adsl ifcfg files (fix ONBOOT setting)
- don't restart network service at drakconnect startup
- draknfs (Antoine):
  o always display ok_cancel button
  o add a checkbox to enable/disable advanced options
- drakTermServ (Stew):
  don't try to manipulate PXE stuff if the directory isn't present

* Fri Jul  8 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.33mdk
- drakboot: add support for graphical grub (Herton Ronaldo Krzes)
- draknfs: various adjustement in main windows (antoine)
- drakvpn: fix untranslated strings (#16736)

* Thu Jul  7 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.32mdk
- drakconnect: do not restart network to apply modifications, run ifup
  or ifplugd instead (blino)
- draknfs, drakhosts: GUI improvements (antoine)

* Tue Jul  5 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.31mdk
- drakfloppy: do not package it anymore since kernel is too big
  (#10565)
- drakhosts, draknfs: new tools (antoine)
- harddrake service: fix faillure on startup

* Fri Jul  1 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.30mdk
- diskdrake:
  o misc LVM enhancements (pixel, the "Anne" effect, #16168, #16176,
    #16189, #16668)
  o enhanced dmraid support (pixel)
  o don't allow labels on "/" for !extX fs since mkinitrd only handle
    ext2/ext3 labels (pixel)
  o describe "grpquota" and "usrquota" mount options (#15671)
- drakbug: fix reporting bugs for "Standalone Tools" and prevent shell
  parsing unquoted bugzilla URL(blino & me, #16580)
- drakfirewall (blino):
  o add 'routeback' option for bridge interfaces in shorewall
    interfaces file
  o don't write loc to fw ACCEPT rules, we always reset the policy to
    accept (#16087)
- draksplash (blino):
  o write progress bars in bootsplash config files
  o update crossbars when scale values are modified
- net_applet: reduce memory footprint (#15308)

* Thu Jun 30 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.29mdk
- do not load librpm when not needed (rafael, me)
- diskdrake: enhanced dmraid support (pixel)
- drakboot: handle no bootloader configuration found (pixel)

* Mon Jun 27 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.28mdk
- drakxtv:
  o enable to configure cx88 driver
  o update card lists from kernel-2.6.12
- net_applet: reduce fork()/exec() pressure on system (blino)
- service_harddrake: fix switch from nvidia to nv for X.org

* Fri Jun 24 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.27mdk
- diskdrake (pixel):
  o enhanced dmraid support
  o some free space computing for LVM
  o support labels for more file systems
- drakauth (blino, pixel):
  o fix crash (#16564)
  o fix NISDOMAIN
- localedrake: add scim-ccinput support (funda wang)
- net_monitor: fix crash (blino)
- more PXE infrastructure (blino)

* Mon Jun 20 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.26mdk
- drakconnect: don't strip VLAN and MTU fields from ifcfg files (blino)
- diskdrake: initial dmraid support (pixel)
- fix some programs after cleanups:
  o drakconnect, drakvpn (blino, #16505, #16502)
  o harddrake2 (#16472)
- XFdrake: fix 3D on ATI cards

* Fri Jun 17 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.25mdk
- drakboot:
  o make it use stage1_5 thus enabling to survive disk change, ie
    geometry alteration (pixel)
  o fix reading config with new grub (thus fixing detectloader,
    bootloader-config & installkernel)
- harddrake: make it load mouse modules on change, since
  modprobe.preload is read before harddrake is run, thus fixing
  synaptics (blino)

* Wed Jun 15 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.24mdk
- fix banner widget breaking rpmdrake and the like
- XFdrake: prevent loading/unloading twice the same glx module on non
  NV cards

* Tue Jun 14 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.23mdk
- drakauth: stop messing with likeauth and nullok options and keep
  them on the pam_unix line (pixel, #12066)
- drakboot:
  o adapt to new grub
  o don't drop "shade" and "viewport" lines (pixel, #16372)
- drakconnect: add senegal ADSL provider entry (daouda)
- XFdrake: protect quotes in monitor names (pixel, #16406)

* Wed Jun  8 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.22mdk
- drakfirewall (blino):
  o do not crash when restarting shorewall
  o do not write buggy shorewall masqfile when connection sharing is
    disabled

* Tue Jun  7 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.21mdk
- bootloader-config, drakboot, diskdrake: fix some LABEL bugs (pixel)
- drakauth: read existing authentication conf (pixel)
- drakbackup: tape backup/restore fixes to work with new .backupignore
  scheme & other bug fixes (stew)
- drakboot: keep read-only, read-write and label as verbatim as
  possible (pixel)
- drakconnect (blino):
  o big code base cleanups
  o keep NETWORKING_IPV6 and FORWARD_IPV4 variables in
    /etc/sysconfig/network
  o fix old ISDN modems
  o fix calling s2u on system hostname change
- drakedm: get list of DM from /etc/X11/dm.d/*.conf (pixel)
- draksplash: misc fixes (blino)
- finish-install: add language selection to finish-install

* Mon May 30 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.20mdk
- handle more DVB cards
- drakconnect: third party support update (blino):
  o point the user to the relevant packages/documentation/url if
    needed,
  o do not allow to configure a device if its requirements aren't
    satisfied
- harddrake service: load drivers for newly added devices so that they
  work out of the box on first boot after card plugging (AGP, IDE, DVB,
  SCSI, TV)
- printerdrake: support for PPD file names with spaces (till, #16172)

* Fri May 27 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.19mdk
- drakedm: handle /etc/X11/dm.d/* entries (as proposed by Loic Baudry)
- localedrake:
  o display SCIM combinaisons in a sub menu
  o enable to select extra SCIM combinaisons: scim+anthy, scim+canna,
    scim+fcitx, scim+m17n, scim+prime, and scim+skk;

* Fri May 27 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.18mdk
- drakgw, drakshorewall: misc fixes (blino)
- draksplash (blino):
  o use scrollbar in preview window
  o try not to be larger than screen size minus toolbars size
  o close_window -> close_all
- harddrake: fix misdetecing USB mass storage devices (#13569)
- localedrake:
  o enable to select scim+uim again
  o install needed packages for kinput2
- net_applet: let user call drakroam (blino, #16019)

* Tue May 24 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.17mdk
- drakgw (blino):
  o wizardify
  o allow not to enable DNS, dhcpd and proxy servers
  o allow not to enable CUPS broadcast
  o use network interfaces instead of network addresses in CUPS
    configuration
- harddrake: use mousedrake to configure tablets & touchscreens

* Sun May 22 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.16mdk
- interactive layer: fix canceling managment in text mode
- XFdrake: only run ldconfig if needed (aka only if GL config was
  altered), thus speeding up auto-config of X in harddrake service
- fix joystick detection (pixel, #16099)

* Thu May 19 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.15mdk
- drakconnect, harddrake: detect all ADSL modems of each kind
- harddrake GUI:
  o detect yet more webcams and USB audio devices
  o DVB support:
    * list DVB cards in their own category
    * install needed packages for DVB
  o list tablets and touchscreens in their own category
  o fix detecting joysticks
  o really list ATM devices
- harddrake service: install/remove DVB drivers if needed

* Thu May 19 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.14mdk
- interactive layer: handle canceling wizards in text mode
- hardware support:
  o detect more webcams
  o detect more ADSL USB modems (needs further drakconnect work)
- harddrake:
  o create new categories for USB audio, ATM, Bluetooth, WAN, and radio devices
  o split joysticks category into real joystick and gameport controller ones
- localedrake: clarify "other countries" vs "advanced" label depending if the
  language is spoken in several countries and if the language needs an IM method

* Tue May 17 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.13mdk
- drakboot (blino):
  o add the "Create new theme" button back
  o allow to choose between "text only", "verbose" and "silent"
    bootsplash modes
- drakconnect (blino):
  o use iwpriv for WPA with rt2x00 drivers (since they don't support
    wpa_supplicant)
  o keep # and * characters in phone number (#16031)
- drakroam:
  o fix perms on /etc/wlandetect.conf (#16020)
  o really write waproamd config files (blino)

* Mon May 16 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.12mdk
- fix GtkTextView wrapper
- drakups: do not detect MS joystick as UPS (#15930)

* Thu May 12 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.11mdk
- diskdrake: default to "Custom" when group fileshare exists (pixel, #15917)
- drakbackup (stew):
  o drop webdav support (can be mounted as a normal net filesystem
    these days)
  o remove translation on "tape" media selection (#15437)
  o rework .backupignore handling (#12352)
- drakconnect: netconnect.pm: reorder drakconnect first screen (blino)
- drakups: fix detecting Wingman gamepad as UPS (#15750)
- harddrake: ensure wait message is centered on mcc
- harddrake service: fix PCMCIA breakage (#15742)
- fix serial controllers detection (#15457)

* Tue May 10 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.10mdk
- draksplash (blino):
  o improved layout (separate window for image previews, notebook to
    split silent/verbose/console settings)
  o update scale factors when the theme name is changed too
  o use default jpeg image path in config file for both silent and
    verbose images
  o force the exact image size when writing a theme
  o write bootsplash v3 configuration files (progress bar still
    missing)
  o allow to modify progress bar and console box by dragging the mouse
  o really get default vga mode
  o shrink preview window on resolution change
  o handle both silent and verbose images
- localedrake (UTUMI Hirosi):
  o add support for iiimf
  o do not install anymore uim-anthy for japanese users

* Wed May  4 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.9mdk
- diskdrake (pixel):
  o fix displaying number of logical extents
  o allow resizing ext3 LV if not mounted
  o allow resizing reiserfs LV even if not mounted
- drakbackup (stew):
  o clarify quota message, optional delete old backups (#15066)
  o optional mail "From" address (#15293)
  o fix automagic addition of /root to backups when not desired
- drakconnect (blino):
  o ask wireless settings before boot protocol selection
  o remove useless warning in install, we never override configuration (#10827)
- draksplash (blino):
  o fix theme creation
  o preview theme in real time, cleanups
  o use default values for scale settings
  o draw a cross inside the text box
- drakTermServ (stew):
  o update for new etherboot
  o predict NBI disk space usage and check
  o catch failed NBI creation (#13902)
  o catch failed dhcpd.conf creation (#13943)
  o misc small bug fixes

* Mon May  2 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.8mdk
- ensure most sub dialogs reuse the icon of their main window
- drakboot: improve layout
- drakconnect: fix USB devices detection for ndiswrapper (blino)
- harddrake: fix SATA & hw RAID detection (detect them pior to detecting PATA)

* Fri Apr 29 2005 Thierry Vignaud <tvignaud@mandriva.com> 10.3-0.7mdk
- drakconnect (blino):
  o don't write /etc/ppp/options anymore, adjust options in peer files
  o display VPI/VCI values in decimal
  o configure pppoe connections in a ppp peer file
- drakroam (blino):
  o do not write blank ESSID
  o exit and warn when no wireless interface is found (#15244)
- drakups: do not detect IR devices as UPSes (#15495)
- XFdrake: if one prefer using "Modes" instead of "Virtual", keep it
  as is (pixel)

* Mon Apr 25 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.3-0.6mdk
- drakconnect (blino):
  o fix WPA key (#15621)
  o allow to disable WPA even if no key is used
  o handle errors in wireless packages installation
- drakroam: fix Signal Quality parsing (blino)

* Thu Apr 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.3-0.5mdk
- mandrakesoft is now mandriva

* Thu Apr 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.3-0.4mdk
- drakconnect: basic tokenring support

* Thu Apr 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.3-0.3mdk
- drakbackup, drakfont, draksplash: switch to gtk+-2.6's new file selector
- drakbackup, drakroam: fix layout
- drakfont: filter file list so that only fonts are displayed

* Wed Apr 20 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.3-0.2mdk
- drakconnect (blino):
  o merge wireless steps and move advanced settings in advanced mode (#15501)
  o configure wpa driver in drakconnect, wpa_supplicant init script is dropped
  o fix default wireless mode to be "Managed" instead of "Secondary"
  o really use given encryption key
  o improve ndiswrapper driver configuration (allow to select driver,
    device and many errors handling)
  o fix fallback sysfs if ethtool failled
  o do not write zeroed MAC addresses in iftab, it confuses ifrename
  o do not crash if modprobe fails
  o unload ndiswrapper first so that the newly installed .inf files
    will be read
  o allow to choose the wireless encryption mode between "None", "Open
    WEP", "Restricted WEP" and "WPA Pre-Shared Key"
- drakfirewall: fix automatic net interface detection (blino)
- drakroam: fix SSID listing (blino)
- keyboardrake: update keyboard list for next xorg-x11 (pablo)
- mousedrake (blino):
  o preselect synaptics touchpad if no external mouse is present
  o better detection for touchpad
  o append evdev in modprobe.preload if a touchpad is detected
  o always configure an universal mouse so that USB mices can be hotplugged
  o always set synaptics touchpad as secondary and don't list them in
    mousedrake
- net_applet: increase network check timeout to lower the load (blino)
- XFdrake: suggest 1280x1024 instead of 1280x960 which causes pbs (pixel)

* Fri Apr 15 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.3-0.1mdk
- drakbackup: fix direct-to-tape backup/restore issues (stew, #15293)
- drakconnect (blino):
  o use sysfs as fallback to detect wireless interfaces (eg:
    rt2x00/prism2_*)
  o allow to modify METRIC settings in the wizard
  o fix displaying wifi data in manage interface

* Tue Apr 12 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-24mdk
- drakconnect: fix connection establishment (rafael)

* Mon Apr 11 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-23mdk
- drakconnect (blino):
  o fix error reporting for ndiswrapper package installation (#15373)
  o handle spaces in ndiswrapper drivers path
- XFdrake (pixel):
  o fix empty ModeLine lines
  o 1152x864 needs more modelines than the poor 1152x864@75Hz builtin
    xorg (#11698)

* Fri Apr  8 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-22mdk
- drakconnect: always restart slmodem, even if it was already
  installed (blino)
- harddrake: fix harddrake crash with USB/PCI DSL modems (blino, #15034)

* Thu Apr  7 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-21mdk
- drakconnect (blino):
  o fix support for fix h[cs]f modems
  o create correct /dev/modem && install correct package for HCF modems
- drakroam (blino):
  o don't truncate default gateway (#15247)
  o hide roaming frame by default
- net_applet (blino):
  o really allow users to start connection without having to type the
    root password
  o fix refresh

* Tue Apr  5 2005 Olivier Blin <oblin@mandrakesoft.com> 10.2-20mdk
- mousedrake: really apply specific ALPS touchpad settings (#14510)
- drakconnect:
  o install dkms packages if found
  o support more slmodems
- net_monitor: improve wifi detection
- drakroam:
  o do not crash if no essid is selected (partially fix #15244)
  o hide unavailable features, add close button
- drakboot (Pixel): apply patch from bugzilla #15216, adding support for
  "password=..." and "restricted" at per-entry level (thanks to jarfil)
- misc charset fixes (Pixel, Pablo)

* Mon Apr  4 2005 Olivier Blin <oblin@mandrakesoft.com> 10.2-19mdk
- drakconnect:
  o only switch up wireless devices during detection
  o do not reupload firmware for eagle-usb modems if already done
  o disconnect internet interface before trying to connect
- mousedrake: configure wacom devices with synaptics touchpads too
- printerdrake (Till):
  o Fixed bug #4319: Printer options cannot be set after renaming the
    printer or changing the connection type
  o Fixed bug of PostScript printers with manufacturer-supplied PPD
    cannot be renamed at all
  o Fixed bug of print queue being deleted when renaming fails
  o Fixed bug of printerdrake trying to open a message window when
    non-interactive queue generation fails
  o Fixed pre-definition of $printer->{ARGS}, this bug made printerdrake
    crashing sometimes
- diskdrake (Pixel): add /usr/local and /opt to suggestions_mntpoints

* Fri Apr  1 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-18mdk
- drakconnect: enable ethernet interfaces during detection, thus
  fixing Ralink wireless detection (blino)
- harddrake: fix crash
- mousedrake: configure wacom devices with synaptics touchpads too
  (blino)

* Thu Mar 31 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-17mdk
- drakconnect: do not use ifplugd for wireless cards (and don't allow
  to enable it) (blino)
- drakfirewall: make it usable (pixel, #15116)
- drakups: do not detect USB joystics as UPSes (#15131)
- harddrake:
  o do not try to install packages that are not availlable (#15106)
  o do no try to install too generic hw packages (#15101)
  o do not detect USB joystics as UPSes (#15102)
- localedrake: do not try to logout wm (pixel, #15087)

* Wed Mar 30 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-16mdk
- drakconnect (blino):
  o fix speedtouch microcode url (#15095)
  o fix sagem modem config
  o try to use the country specific CMV for sagem modems
- harddrake:
  o list hardware RAID controllers in their own section (so that they do not
    appear in the unknown one)
  o ensure we detect all known SATA controllers and all known sound cards
  o fix optical mice detection (#15082)
- net_applet: really load network configuration at start (blino)
- printerdrake: do not mis-detect some USB keyboards as printers (till)

* Tue Mar 29 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-15mdk
- drakconnect (blino):
  o fix eaglectrl path (#15033)
  o detect more Bewan devices
  o fix support for sagem modems not using pppoa
- harddrake: add an option in harddrake to probe imm/ppa (pixel,
  #12560)
- localedrake:
  o fix russian size (pixel, #14988)
  o "unicode" checkbox is visible only in expert mode
- fix tools' crash when drakconf is not installing (#13392)

* Fri Mar 25 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-14mdk
- drakroam:
  o do not crash (blino)
  o fix translations
- net_applet (blino):
  o ask for root password if needed when setting a new profile
  o force refresh if asked by user from the menu

* Thu Mar 24 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-13mdk
- banners: make banner be RTL aware (aka follow language direction and
  display itself mirrored for RTL languages) (#11910)
- diskdrake (pixel):
  o ensure we use/propose a free md when creating a new one
  o after "mdadm --assemble" there can be some inactivate mds busying
    devices, stopping them
- drakconnect (blino):
  o make Bewan PCI modems work again
  o add support for modems using pppoatm (e.g. SpeedTouch) and ISP
    using RFC 1483 Routed VC MUX (e.g. Free Degroupe)

* Wed Mar 23 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-12mdk
- XFdrake: fix probing on neomagic (pixel)
- harddrake: package rpmsrate so that installing hw packages works

* Tue Mar 22 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-11mdk
- drakconnect: do not list wifi* interfaces (blino, #14523)
- harddrake2: install packages needed for hw support
- keyboarddrake: run dmidecode only once we acquired root capabilities
  (pixel, #13619)

* Mon Mar 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-10mdk
- drakboot: enhance yaboot macos entry handling (cjw, #14642)
- drakconnect: disable network hotplug for the via-velocity driver
  (#14763)
- drakups:
  o fix driver for APC UPSes for auto USB probing
  o set extra parameters if present
- net_applet (blino):
  o force start from menu (#14858)
  o don't modify autostart config file value if started with --force
- XFdrake (blino):
  o use new recommended settings for synaptics-0.14.0
  o use specific Synaptics settings for ALPS devices (#14512)

* Fri Mar 18 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-9mdk
- drakTermServ: detect all NIC that're know to drakconnect
- drakups: fix device path when manually adding an UPS (#12290)
- logdrake: fix explanation mode only displaying last line (#14368)

* Fri Mar 18 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-8mdk
- diskdrake (pixel):
  o fix remove on LVM in newt interface (#14254)
  o remove the lvm if destroying it succeeds (#14249)
- drakboot: handle grub file names that do not correspond to a mounted
  filesystem (pixel, #14410)
- drakconnect: remove other mac address occurrences in iftab (blino)
- drakTermServ (stew):
  o lose the "system" calls
  o use pxe.include now
- drakperm:
  o do not ignore groups with empty password field (#14777)
  o better looking GUI: span groups & users on several columns (up to 3)
- localedrake: always warn the user to logout, even if we can't help
  (pixel, #14403)

* Thu Mar 17 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-7mdk
- drakconnect:
  o fix localized sorting (#14634)
  o manage interface (blino):
    * allow to modify non configured devices
    * really detect wireless devices
- harddrake: fix adsl devices detection (blino, #14747)
- logdrake: fix save dialog (blino)
- printerdrake: fix queue name auto-generation, it sometimes hanged in
  an endless loop (till, #14426, #14525, #14563)
- XFdrake (pixel): 
  o instead of having xorg.conf symlinked to XF86Config, do the
    contrary
  o use monitor-probe-using-X
  o remove the "ratio" combo and have the resolutions from current
    ratio by default and allow "Other" to see all others

* Wed Mar 16 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-6mdk
- drakboot: fix dropping line macos in yaboot.conf (pixel, #14642)
- drakconnect (blino):
  o allow to display multiple instances of the similar adsl devices
  o fix unicorn packages installation
- interactive layer: fix some nasty bug
- localekdrake:
  o preserve utf-8 setting (#12308)
  o properly set UTF-8 for HAL mount options if needed (#13833)
  o enable to enable/disable utf-8
  o install scim-input-pad when switching IM for japanese
  o ensure there's never a "previous" button on first step (even when
    stepping back)
- printerdrake: fix setting of default printer on daemon-less CUPS
  client (till, #13940)
- XFdrake: probe DDC, then fallbacks on DMI

* Tue Mar 15 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-5mdk
- diskdrake: add support for XBox (stew, pixel)
- drakboot: don't die when we have no entries in grub menu.lst (pixel)
- drakconnect (blino):
  o allow not to set gateway device (#14633)
  o fix and force CMVs symlink creation for eagle-usb
- drakfirewall: allow connections from local net to firewall (blino,
  #14586)
- XFdrake (pixel):
  o for 1400x1050, put the resolutions (60 and 75Hz are already in
    extramodes, but they are GTF modelines, we can overrule them) 
  o don't add modelines for 1280x1024, they are already in standard
    vesamodes (builtin Xorg)
  o when adding gtf modelines, sort them with high frequencies first
    (since Xorg prefer the first matching modeline (!))

* Thu Mar 10 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-4mdk
- harddrake2: enable to upload the hardware list
- XFdrake:
  o fix crash when called from hwdb-clients
  o skip the 4/3 detailed_timings otherwise they conflict with the
    Xorg builtin vesamodes (pixel)
- drakconnect (blino):
  o use a higher timeout for modem dialing (#10814)
  o make wpa_supplicant.conf readable by root only

* Wed Mar  9 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-3mdk
- drakconnect:
  o workaround buggy sk98lin kernel driver (#14163)
  o write selected dhcp client in ifcfg files (blino)
- draksec: fix setting null values (#14364)

* Tue Mar  8 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-2mdk
- drakconnect (oblin):
  o scan hidden ssid
  o manage interface:
    * handle more DHCP options
    * move DHCP settings in a notebook page
- XFdrake: choose a 4/3 resolution by default (pixel)
- XBox support (stew)

* Mon Mar  7 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-1mdk
- diskdrake: allow live resizing of reiserfs on lvm (pixel)
- drakboot: fix detecting yaboot (pixel)
- drakconnet (blino):
  o configure CMV for sagem modems
  o delete gateway:
    * if reconfiguring the gateway interface to dhcp
    * if gateway device is invalid (#11761)
    * if needed when configuring DSL devices (#13978)
  o manage interface:
    * detect all ethernet interfaces
    * allow to modify DHCP settings
- localedrake: let's be able to setup gcin (funda wang)
- printerdrake: detect if the user has manually edited
  /etc/cups/client.conf (till)
- XFdrake: still improving monitors support (pixel)

* Wed Mar  2 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.35mdk
- drakboot (pixel):
  o fix corrupted "Precise RAM size" field (#13874)
  o handle boot-as and master-boot (#13846)
- drakconnect: workaround buggy kernel (#12609)
- net_applet: refresh every second, and do not reread network conf on
  each refresh (blino, #11467)
- printerdrake (till):
  o add possibility to add a remote LPD printer in beginner's mode (#13734)
  o fix incorrect display of accentuated characters in PPD options
    also for boolean options (#13928)
  o let detected LPD printer model be shown in a pop-up window and not
    in the add printer wizard
  o let detected socket printer model be shown if the IP/port was
    manually entered
  o fix selection of test pages
  o ensure that recommended driver is preselected in expert mode, even
    if the recommended driver is a manufacturer-supplied PPD with
    language tag
- ugtk2 layer: misc fixes
- XFdrake (pixel):
  o add a ratio choice, and restrict the resolutions to this choice
  o add 1280x600 for VAIO PCG-C1M (#5192)
  o fix section with only comments
  o "keyboard" InputDevice can also be called "kbd"
  o do not only add modelines not defined in xorg, otherwise xorg will
    prefer the modelines we provide (eg: it will use 1024x768@50
    whereas it could have used 1024x768@60)
- configure iocharset and codepage option for hal (pixel, #13833)

* Tue Mar  1 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.34mdk
- diskdrake: allow to choose encryption algorithm (blino, #13472)
- drakhelp, drakbug: use www-browser (daouda)
- printerdrake: fix "add printer" wizard chen embedded in the MCC (#13929)
- XFdrake: further monitor fixes (pixel)

* Tue Mar  1 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.33mdk
- drakconnect: enhance "wrong network mask format" message (blino, #10712)
- drakTermServ: sort list of nbis (stew, #13998)
- keyboardrake: set compose key as "rwin" if not set (pablo)
- XFdrake (pixel):
  o replaced by use monitor-edid instead of ddcxinfos
  o add many resolutions
  o set the "Monitor preferred modeline" from EDID in xorg.conf
  o handle lower than 640 resolutions
  o set better resolution

* Mon Feb 28 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.32mdk
- drakboot: make sure /boot/grub/install.sh is 755 (pixel)
- drakconnect (blino):
  o allow to alter DHCP timeout (# 11435)
  o add support for PEERDNS, PEERYP and PEERNTPD (#9982)
  o workaround broken ethtool from hostap drivers (#13979)
  o handle USERCTL settings for modems too
- net_applet (blino):
  o add menu entry (#11898)
  o netprofile support (#12094)
  o allow to select watched interface
- printerdrake: let country and not language decide about default
  paper size (till)

* Fri Feb 25 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.31mdk
- drakconnect (blino):
  o allow users to start the connection (#12837)
  o pre-detect modem device
- keyboarddrake: new default keyboard is "us" for Chinese (pablo)
- printerdrake: driver "oki4w" was renamed to "oki4drv" (till)

* Fri Feb 25 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.30mdk
- drakconnect :allow to select "unlisted" provider in adsl provider
  list (blino)
- drakfont: fix uninstalling fonts (#9324)
- drakproxy: do not update kde config file if kde isn't installed (blino)

* Thu Feb 24 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.29mdk
- drakconnect:
  o add norwegian ADSL providers (Eskild Hustvedt)
  o remove all non-digit characters in phone number (blino, #10813)
  o minimal WPA support (blino)
- drakxtv: scan TV channels for TV cards that do not require any
  driver configuration (#13865)
- drakups:
  o fix crash due to latest perl-Libconf 
  o fix reading UPS db
- net_applet: fix name of mcc tool (blino & me, #13896)
- printerdrake:
  o enable to alter options of a not set up non-Foomatic queu
  o fix accentuated characters in PPDs not correctly reproduced in the
   printer options dialog
- GUI layers:
  o fix displaying "Advanced" instead of "Basic" in advanced_state by
    default (pixel, #13944)
  o force to open file selector as a modal window (rafael, #13942)

* Tue Feb 22 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.28mdk
- drakfont: allow to select multiple files (blino)
- localedrake:
  o adapt to new uim splitting (UTUMI Hirosi)
  o adapt to new scim packages splitting (Funda Wang)
  o fix koi8-u font size (Funda Wang, #13809)
- keyboardrake: handle lb locale (pablo)
- printerdrake: if a printer is set up with HPLIP and has still an old
  HPOJ configuration, it will be automatically removed (till)
- scannerdrake (till):
  o display unsupported scanners as such in the scanners list (#12049)
  o load kernel modules (and make them loaded on boot) if specified in
    ScannerDB
  o tell user if his scanner requires manual editing of config files
    to work (the appropriate scanner models are marked in ScannerDB)

* Wed Feb 16 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.27mdk
- drakboot: make it more robust (pixel)
- drakproxy: set up KDE too (blino)
- harddrake: list usb mice that are not listed in usbtable (#13575)
- interactive layer: use the new gtk+ file chooser (pixel)
- keyboarddrake: make keyboard layout more user friendly
- printerdrake (till):
  o force only ASCII letters, numbers, and underscores being used in
    print queue names
  o wait for CUPS being ready before querying the printer states for
    the printer list in the main window
- reduce drakxtools-backend's requires (pixel)

* Mon Feb 14 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.26mdk
- draksound, service_harddrake: handle more sound cards
- localedrake: alter font settings for zh_CN and zh_TW (funda wang)
- printerdrake (till):
  o allow HPLIP setup also when setting up the print queue manually
  o fix undetection of network printers without DNS hostname entry
  o longer timeouts for "ping", as some network printers were missed
- service_harddrake: handle removal of cards (#7049)

* Fri Feb 11 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.25mdk
- harddrake service: fix removing PCMCIA controller
- hardware support: detect & load modules for RNG (crypto hw)

* Thu Feb 10 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.24mdk
- drakxtv:
  o only offer to configure tv cards that (may) need to be configured
  o do not complain about no tv cards when there're but they do not
    require any configuration beyond loading proper module (#7443,
    #11270, ...)
- harddrake:
  o detect more webcams
  o do not detect speakers as keyboards
- printerdrake: misc fixes (till)

* Thu Feb 10 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.23mdk
- printerdrake (till):
  o add automatic setup of HP printers with HPLIP
  o fixes for embedded mode
- drakconnect:
  o add support for ACP (Mwave) modems
  o fix stepping back from lan interface step with ndiswrapper
  o fix ndiswrapper installing
- interactive layer: fix selecting a file (eg: ndiswrapper's drivers)
- hardware support:
  o detect & load modules for:
    * toshiba driver for some laptops
    * some multiport serial cards
    * DVB
    * joysticks
  o add support for multiple different AGP controllers
  o handle a few more special serial port cards

* Wed Feb  9 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.22mdk
- localedrake: switch arabic font for KDE from "Roya" to "Terafik"
  that supports ascii glyphs (pablo)
- ugtk2: API changes for rpmdrake (rafael)

* Wed Feb  9 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.21mdk
- drakboot: fix ACPI checkbox (pixel, #13335)
- drakkeyboard: synchronized keyboards with X11 (pablo)
- harddrake service: prevent adding spurious empty lines at end of
  /etc/hotplub/blacklist on stop
- printerdrake: updates

* Tue Feb  8 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.20mdk
- drakconnect (blino):
  o add basic ndiswrapper support
  o select manual adsl connection type if the network interface was
    static
  o add missing protocol for Free and Telecom Italia in ISB DB
- drakproxy: support gnome proxy (blino)
- printerdrake (till):
  o adapt to new printer drivers packages
  o limit automatically generated print queue names to 12 characters
    and warn user if he manually enters longer names (which will make
    the printer unaccessible for some Windows clients) (#12674).
- allow upper case letters in users' real names (rafael)
- net_applet: automatically start in fluxbox and XFce4 too (blino)

* Fri Feb  4 2005 Olivier Blin <blino@mandrake.org> 10.2-0.19mdk
- drakconnect: add bpalogin support for cable connections

* Thu Feb  3 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.18mdk
- drakconnect: fix CAPI kernel drivers installation (blino)
- drakfirewall: port 445 is used for Samba (w/o NetBios) (blino)

* Fri Jan 28 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.17mdk
- diskdrake: fix autocheck flag in /etc/fstab for / (pixel, #13283)
- drakbackup: Wizard, System Backup configuration problems (stew, #13235)
- harddrake service:
  o fix PCMCIA autoconfig
  o make --force force harddrake to reconfigure everything

* Wed Jan 26 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.16mdk
- diskdrake: use the new option auto=dev instead of auto=yes when
  configuring mdadm (pixel)
- drakTermServ (stew):
  o drop quasi-pxe setup in dhcp.conf as we can use real pxe now
  o portmap check, dhcpd.conf.pxe.include (#13138 & #13139)
- package installation: use the new --gui option to urpmi for the
  drakxtools to ask for media change (rafael)
- mygtk2 related fixes (pixel)

* Fri Jan 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.15mdk
- fix mygtk2 for drakloop (pixel)
- printerdrake: fix main loop (daouda)

* Fri Jan 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.14mdk
- drakconnect: update ISP db (baud)
- harddrake: fix pcmcia controllers detection

* Fri Jan 21 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.13mdk
- keyboarddrake: minimal XkbModel support (pixel)
- diskdrake (pixel):
  o don't write /etc/mdadm.conf when no raid
  o use option "auto=yes" in mdadm.conf to ensure mdadm will create
    /dev/mdX devices when needed
- printerdrake:
  o fix subdialogs when embedded in mcc
  o fix banner's title by initializing l10n domains before ugtk2

* Wed Jan 19 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.12mdk
- diskdrake: progress bar when formatting ext3 (pixel)
- drakauth: fix switching back nsswitch.conf to local authentication
  (pixel, #13024)
- drakbackup: custom cron configuration (stew, #13056)
- drakboot: do not create a maping table when uneeded (#12307)
- drakconnect: fix bug introduced by mygtk2 (pixel)
- drakfirewall: fix ethernet card detection (pixel, #12996)
- harddrake2: fix crash on opening help windows
- interactive layer: separate alignement for basic and advanced
  entries (pixel)
- XFdrake (pixel):
  o when reading an existing X config file, ensure it is not too bad,
    otherwise propose to start from scratch (#8548)
  o set up framebuffer in standalone mode too
  o for fbdev, advise to reboot instead of restarting X server

* Wed Jan 12 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.11mdk
- harddrake2: display the menubar and the banner when embedded

* Wed Jan 12 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.10mdk
- drakbackup, drakTermServ: silent install of terminal-server (urpmi
  --X is deprecated) (rafael)
- localedrake (Funda Wang):
  o install scim-chewing for zh locale
  o fix font setting for zh_CN
- printerdrake: show banner when embedded
- write in lilo.conf the global root= (pixel, #12312)

* Thu Jan  6 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.9mdk
- diskdrake: display a progress bar while formating (pixel)
- localedrake: fix UIM config b/c of new UIM-0.4.5

* Wed Jan  5 2005 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.8mdk
- drakauth: "Administrator (root)" is more user-friendly than "root"
- drakbackup (stew):
  o directories with spaces Mandrakeclub
  o perms on tarballs too (#12861)
- drakconnect: update ADSL ISPs list (baud)
- drakfirewall: "Samba server" is better named "Windows Files Sharing
  (SMB)" (pixel, #10585)
- draksound, harddrake service: handle a couple of new ALSA drivers
- handle handle spaces in SMB username (pixel)
- keyboardrake: handle various new keyboard layouts (pablo)
- localedrake: do not localize console in japanese (Funda Wang)
- remove codepage= option for fs types which don't handle it (eg:
  ntfs) (pixel)

* Thu Dec 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.7mdk
- detect more floppies when dmidecode is supported (pixel)
- drakconnect:
  o do not crash when configuring a modem
  o fix NETMASK autofilling
- localedrake: do not localize console when using jp (Funda Wang)
- XFdrake: make "XFdrake --auto" fully automatic (pixel)

* Wed Dec 15 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.6mdk
- handle more PCMCIA/CardBus cards
- do not try to load floppy module if there's no floppy drive (#8211)
- drakTermServ: misc GUI enhancements (pixel, stew)
- harddrake service: configure PCMCIA host controller if needed
- new package drakx-finish-install (pixel)
- new mygtk2 layer

* Fri Nov 26 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.5mdk
- diskdrake: handle common geometry XXX/240/63 is quite common thus
  fixing yet another infamous "XP doesn't boot" (though it should
  already be fixed via EDD) (pixel)
- XFdrake: don't write X config when there is none (otherwise we write
  a partial and broken X config)

* Thu Nov 25 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.4mdk
- diskdrake: more intelligent sort of fstab to handle loopback files
  or bind directory (pixel, bug anthil #1198)
- drakboot: detect on lilo on floppy (pixel, #12213)
- drakconnect: in "ADSL provider" step, reset the protocol on provider
  switch
- draksound: handle new sound drivers from kernel-tmb and kernel-multimedia
- drakupdate_fstab: fix /dev//dev/foobar in /etc/fstab (pixel, #12224)
- harddrake service:
  o fix setting scsi and usb probell in live CD (thus fixing
    mousedrake --auto with USB mice on live CD)
  o do not die if sound never was configured (aka on first boot from a
    live CD)

* Wed Nov 17 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.3mdk
- bootloader: let be kernel-i686-up-64GB aware (pixel)
- diskdrake: LVM/DM/MD fixes (pixel)
- drakupdate_fstab: use the right encoding when creating an entry for
  /etc/fstab (pixel, #12387)
- PPC fixes (Christiaan Welvaart, pixel)
- service_harddrake: on startup, redo ethX aliases

* Fri Nov 12 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 10.2-0.2mdk
- Rebuild for new perl
- drakauth (pixel):
  o correctly restore pam.d/system-auth when setting "local" authentication 
  o no use_first_pass on "auth sufficient pam_unix.so" line for pam_castella
- localedrake: switch zh_CN to GBK (Funda Wang)
- logdrake: speed it up

* Wed Nov 10 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.2-0.1mdk
- drakauth: add SmartCard authentication (pixel)
- drakbackup: advise user about anacron (stew, anthill #1134)
- drakconnect:
  o add support for Philips Semiconductors DSL card (blino)
  o security fix: let ifcfg files be readable only by root when a WEP
    key is set (blino, #12177)
  o update/add ADSL ISP entries (baud)
- drakTermServ (stew):
  o create cfg dir if needed
  o use xorg.conf
  o touch /etc/dhcpd.conf.etherboot.kernel if missing
  o ignore vmnet for broadcast address
  o start reworking PXE support.
- harddrake2: display more information about memory
- localedrake: fix configuring fcitx IM (Funda Wang)
- XFdrake: do not detect smartcards (pixel)

* Thu Oct 28 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-27mdk
- bootloader: run grub chrooted (gwenole)
- diskdrake:
  o show older partition types (eg: ntfs) on x86_64 (gwenole)
  o newly created raids must have a fs_type (pixel)
- drakconnect:
  o add support for freebox v4 ADSL modem with USB link
  o show correct strings for freebox and n9box ADSL modems
- drakups: fix again MGE USB UPSes

* Tue Oct 12 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-26mdk
- bootloader-config: in grub menu.lst, keep previous "serial ..." and
  "terminal ..." lines (pixel, #12054)
- drakconnect:
  o fix crash in delete wizard
  o workaround more buggy drivers that returns a bogus driver name for
    the GDRVINFO command of the ETHTOOL ioctl

* Mon Oct 11 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-25mdk
- drakconnect: workaround buggy prism2_usb that returns a bogus driver
  name for the GDRVINFO command of the ETHTOOL ioctl

* Mon Oct 11 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-24mdk
- drakconnect (blino):
  o delete wizard: remove /etc/sysconfig/network-scripts/ethX files
  o ADSL configuration:
    * remove /etc/sysconfig/network-scripts/ethX files that may have
      been created by sagem scripts
    * don't write ifcfg-ppp0 for static/dhcp connections

* Fri Oct  8 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-23mdk
- drakconnect:
  o fix encapsulation for chinese ISPs (Funda Wang, #10965)
  o fix H[CS]F modems configuration (adapt to new kernel packages
    names)
  o start slmodemd when installing it (thus preventing the average
    user to have to restart his machine in order to get a working
    connection)
  o try /dev/ttyS14 too for serial modems (ie internal PCI modems that
    don't need any driver but export a serial port instead)

* Fri Oct  8 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-22mdk
- bootloader-config: on a recent kernel, remove any existing devfs=
  kernel option in order to enable udev (pixel)
- drakconnect: add chinese ISPs (Funda Wang, #10965)
- XFdrake: fix parsing fully commented Section (pixel)

* Wed Oct  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-21mdk
- bootloader-config: fix installing kernel-2.6.8.1-12.1mdk (pixel)
- drakups: fix brown paper bug in USB detection

* Tue Oct  5 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-20mdk
- drakups:
  o fix port for MGE's USB UPSes
  o fix drivers for MGE UPSes
  o fix installing nut
  o add support for "American Power Conversion" UPSes
  o restart upsd daemon once nut config is written
  o write config in pure wizard mode
  o when manual adding an UPS:
   * fix reading driver DB
   * fix reading driver from the list
- diskdrake: do not fail with c0d0p* devices (pixel)
- drakconnect: applying changes can be quite time expensive,
  especially with ppp and wifi connections thus let's show a "wait"
  message
- drakfont: fix closing import dialog (#11052)

* Tue Oct  5 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-19mdk
- drakconnect: 
  o ADSL DB (baud):
    * add a few new ADSL ISPs
    * fix wrong VCI which wasn't in hexa for brazililan Velox/Telemar ISP
  o manage interface (blino:
    * recompute NETWORK and BROADCAST fiels
    * use both type and device name in non-ethernet interfaces list
    * do not crash if BOOTPROTO is empty, use 'none' by default (#11899)

* Mon Oct  4 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-18mdk
- drakconnect: do not lose GATEWAYDEV if it is a non wireless one and
  a static wireless card is configured (and vice versa) (blino)

* Mon Oct  4 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-17mdk
- 64-bit fixes (gwenole)
- drakconnect: write wlan-ng config files for prism2 drivers (blino)
- harddrake service: 
  o do not disable glx when switching from nvidia driver to nv
    (indirect support, #11285)
  o do not fail when hw db is corrupted

* Mon Oct  4 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-16mdk
- drakconnect (blino):
  o only write TYPE field in ifcfg files for xDSL connection
  o do not lose ONBOOT setting for manual/DHCP DSL connections
  o fix the "IP %s address is usually reserved" warning
  o sagem modems:
    * fix again DHCP/static connections with sagem
    * write static IP in eagle-usb.conf if needed
    * load specific modules/programs before config is written
    * do not reset IP address when configuring
    * automatically guess gateway for static connections

* Fri Oct  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-15mdk
- fix serial UPS detection

* Fri Oct  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-14mdk
- mousedrake, harddrake service: do not crash with touchpads (blino)
- harddrake service: on stop, blacklist snd-usb-audio (#8004)

* Fri Oct  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-13mdk
- diskdrake: don't die when device-mapper is missing (eg on 2.4
  kernel) (pixel, #11834)
- drakconnect : call the scripts in
  /etc/sysconfig/network-scripts/hostname.d like the network scripts
  are doing when changing the hostname (fredl)
- drakups:
  o add --wizard option in order to directly run the wizard
  o do not show banner when embedded
- harddrake:
  o list tablets with mice
  o fix UPS devices listed in both "UPS" and "unknown" classes
  o provide more data on UPS
- localedrake:
  o set KDE in m17n emvironment if needed
  o split its menu entry in two (one for user config, one for system
    embedded in mcc)

* Thu Sep 30 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-12mdk
- disable the new gtk smart search which display an entry box (pixel)
- preload nvram on laptops
- print translated usage message (#5657)
- bootloader-config, drakboot: add raid-extra-boot=mbr when installing
  on mdX (pixel, #11699)
- diskdrake (pixel):
  o fix LVM2 support
  o fix "Illegal division by zero" when installing lilo (#11738)
  o skip unopenable devices when looking for device geometry
- drakperm: list users rather than groups when requested for (anthill #1161)
- drakroam: specify device to iwconfig when applying settings (blino,
  #11279)
- localedrake:
  o fix KDE font names to match currently shiped Xfs font names (pablo)
  o fix setting fonts at install time
- drakconnect (blino):
  o all linmodems (including Hsf and Hcf ones) are now supported with
    2.6 kernels
  o ask to connect for modem/isdn connections again
  o better default connection detection
  o check if IP address is already used for static interfaces
  o handle madwifi (fredl)
  o try to detect default connection in adsl > isdn > modem > ethernet
    order
- drakups: really fix refreshing UPS list when adding a new UPS though
  the add wizard
- harddrake: list all mice and keyboards (thus lowering unknown
  hardware in hwdb-clients)
- mousedrake, XFdrake: use input/mice instead of psaux for synaptics
  touchpads with 2.6 kernels (blino, #11771)
- net_applet (blino):
  o do not destroy/re-create menu if state hasn't changed, or else the
    menu may disappear without any reason
  o fix again running processes detection
- net_monitor (blino):
  o fix start/stop
  o check every 5 seconds (instead of 20) for new or disconnected
    interfaces (#11780)
- printerdrake: misc fixes (pixel)
- XFdrake: use driver "keyboard" instead of "Keyboard" (fix Xorg-6.8
  support) (pixel)

* Fri Sep 24 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-11mdk
- handle aes-i586 instead of aes (pixel, #11588)
- bootloader-config: fix typos in usage (pixel)
- diskdrake (pixel):
  o get geometry from EDD
  o don't add /dev/pts line in fstab anymore (already done in initrd
    and by udev)
  o log more explanations
  o remove every PVs when destroying a VG (#11579)
  o handle renamed devices (eg: hde->hda or hda->sda)
  o silently ignore encrypted filesystems with no encrypt_key
- drakconnect (blino):
  o zeroconf:
    * really enable zeroconf if zeroconf is requested
    * write blank zeroconf hostname if zeroconf is disabled
    * fix disabling zeroconf
    * do not disable not installed (prevent warnings in console)
    * zcip isn't a service,
    * stop tmdns service if zeroconf is disabled,
  o move "Start at boot" step for lan-like adsl/cable connections
  o do not disable ifplugd support for wireless cards
  o do not let speedtouch-start launch connection
  o fix installing kernel packages for winmodems
  o fix /dev/modem symlink on ttySL0 (#8947 again)
  o use avmadsl option for capi cards to use settings generated by
    drdsl
  o PPPoA: fix reseting vpi and vci if vpi equals zero
  o ADSL provider DB: rename "Télé2 128k " as "Télé2"
- drakupdate_fstab: allow SYNC=no option in /etc/sysconfig/dynamic
  (blino)
- drakups:
  o refresh UPS list when adding a new UPS though the add wizard
  o fix automatically detect/add an UPS
  o default to automatic detection
- localedrake:
  o add support for SKIM IM
  o install x-unikey when switching to vietnamese
  o always use "Sazanami Gothic" font in japanese
- mousedrake: prevent a broken X configuration to break mouse
  configuration (pixel)
- net_monitor: remove connection time timer if connection fails (#11590)
- XFdrake: allow ignoring X config file when it contains errors (pixel)

* Fri Sep 17 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-10mdk
- drakbackup: use radio buttons in media selection (wildman)
- drakconnect (blino):
  o better looking description list in drivers list (me)
  o remove the "speedtch off" alias (fix mdk10.0 upgrade)
  o don't write aliases for pcmcia cards, thus fixing the pcmcia
    service startup
  o stop capi service before new config is written so that capiinit
    can unload the old driver
  o make isdn over capi work again
  o do not ask which driver to use when only capidrv is supported
  o install unicorn-kernel package for Bewan modems if available
  o add "Unlisted - edit manually" entry in modem provider list (#11549)
- harddrake service (blino):
  o probe firewire and pcmcia network devices too
  o update iftab when new ethernet devices are detected

* Wed Sep 15 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-9mdk
- drakconnect:
  o don't create empty pppoe.conf if the package isn't installed
  o load modules and run start programs
- bootloader-config: fix crash when when removing some break entries (pixel)
- keyboarddrake, XFdrake: better turkish support (pablo)

* Tue Sep 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-8mdk
- localedrake: offer to select IM if language has one preselected
  (eg: CJKV, else option is only availlable in advanced mode)
- harddrake service: adapt to new nvidia driver location

* Tue Sep 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-7mdk
- add man pages for drakbackup and drakconnect
- drakauth: misc fixes (stew)
- drakconnect:
  o misc cleanups (blino)
  o setup slmodem (blino)
  o workaround buggy eth1394 that returns a bogus driver name for the
    GDRVINFO command of the ETHTOOL ioctl (so that we set a
    sensible name for firewire network adapters in GUIes)

* Tue Sep 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-6mdk
- drakconnect: install firmware if needed for CAPI devices (blino)
- harddrake:
  o detect not yet supported ethernet cards too
  o detect more bridges and the like
- scannerdrake: try harder not to detect non scanner USB devices (#7057)

* Tue Sep 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-5mdk
- drakbackup:
  o fix crashes in CD/Tape setup (stew)
  o fix wizard's UI behavior (Nicolas Adenis-Lamarre)
- drakconnect (blino):
  o handle CAPI drivers
  o add support for xDSL over CAPI (eg: AVM cards)
  o fix pppoe configuration
- draksec: move help from tooltips into separate page (#9894)
- scannerdrake: fix "dynamic()" in scannerdrake to do not contain
  anything interactive (till)

* Mon Sep 13 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-4mdk
- drakbug_report: fix crash
- XFdrake: adapt to new proprietary package naming (pixel)

* Fri Sep 10 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-3mdk
- net_applet (blino):
  o fix crash on connect/disconnect (#11389)
  o refresh status on every 5 second

* Fri Sep 10 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-2mdk
- description
  o split drakxtools description in drakxtools and drakxtools-newt
  o describe missing tools
  o sanitize tool names
- drakconnect: do not ask twice if network should be started on boot
  for ADSL modem (blino)
- keyboarddrake, XFdrake (pablo):
  o fix compose:rwin
  o fix some keyboard layout on xorg in order to match to match x.org

* Fri Sep 10 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-1mdk
- fix console UIs (pixel)
- drakboot: do not kill the whole bootsplash wizard when embedded (blino)
- drakconnect: fix cnx status in "internet" interface (blino)
- harddrake service: autoconfigure mice if needed
- localedrake: fix ENC setting when IM is disabled

* Thu Sep  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.27mdk
- localedrake:
  o really reset IM on language switch
  o set ENC and locale specific stuff even when IM is disabled
  o fix thai IM

* Thu Sep  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.26mdk
- bootloader-config: handle raid-extra-boot (pixel, #11350)
- drakboot: handles more cases where lilo wants to assign a new Volume
  ID (pixel)
- localedrake:
  o install miniChinput when configuring chinput
  o fix miniChinput configuration for Singapore 
  o handle languages with default IM w/o any configured IM (aka keep
    "none" user choice) but default to per locale default IM when
    switching between locales
  o fix configuration of IM when altering depending on encoding (eg:
    miniChinput)

* Thu Sep  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.25mdk
- bootloader-config (pixel):
  o fix regexp to work with "linux-2.6.8.1-10mdk"
  o handle lilo "static-bios-codes" option
  o prevent LILO from reading from tty
  o only expand symlinks when renaming "linux" into the kernel version
    based label (eg: "2681-10")
- drakboot:
  o ensure ~/.dmrc is owned by user else GDM complains about
  o handles the lilo case where it wants to assign a new Volume ID (pixel)
- drakconnect: 
  o ignore rpm's backups (#10816)
  o always update iftab when config is written (blino)
  o detect slamr, slusb and ltmodem modules for modems (fredl)
- drakupdate_fstab: handle options in any order (fix harddrake service
  regarding amove media as well as regarding cdroms, burners and dvds)
- harddrake service: log which tools are runned

* Wed Sep  8 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.24mdk
- drakboot (blino, #11282):
  o update splash when removed too
  o use Mandrakelinux theme by default
  o don't give theme name to remove-theme
- drakconnect: fix empty "manage interface" (blino, #11287)
- drakperm: fix freeze (#11274)
- harddrake service: fix X11 autoconfiguration

* Tue Sep  7 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.23mdk
- bootloader-config: take care of symlink based bootloader entries (pixel)
- diskdrake (pixel):
  o ignore first line of /proc/swaps
  o partially handle /udev/xxx device names in fstab
  o ignore rootfs "device"
  o don't warn for loopback files
- drakbug: fix --report and --incident (daouda)
- drakconnect (blino):
  o "delete network interface" wizard:
    * use long device names
    * be aware of internet service -> regular ifcfg files
  o misc fixes (especially regarding sagem ADSL modems)
- harddrake service: really autoconf TV cards
- more synaptics fixes (blino)
- use "users" options for removable devices (so that users can unmount
  them if the devices were mounted by root) (blino)

* Mon Sep  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.22mdk
- diskdrake (pixel):
  o detect linux software raid magic
  o detect LVM2
  o misc fixes
  o fix displaying "mdmd0" instead of "md0"
- drakboot: ensure we do not enable autologin w/o any user
- drakconnect (blino):
  o fix detection in 2.4 kernel for net devices with high traffic
  o only complain about kernel-2.4.x for h[cs]f modems
  o fix kppp config reread
  o read kppp config when user dir is configured
  o use /dev/modem if no modem was detected (do not crash when we edit
    a connection whose modem is unplugged)
- harddrake service: everything should be done automagically now
- localedrake:
  o list specific packages to install for japanese when using SCIM
  o install scim-m17n as well for generic SCIM configuration (more
    input methods)
  o log more explanations
  o set QT_IM_MODULE too since it's needed by Qt-immodule-20040819
    (UTUMI Hirosi)
  o disable translations on console for kn, pa, ug too (pablo)

* Mon Sep  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.21mdk
- misc GUI enhancements
- diskdrake: be more failsafe with half broken existing raids (pixel)
- drakconnect: fix crashes (#11100)
- harddrake service: really add module for storage controllers, AGP
  controllers, TV cards
- mousedrake, XFdrake: fix synaptics configuration (blino)

* Fri Sep  3 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.20mdk
- detect more devices
- misc GUI cleanups
- netconnect: support DHCP and static for sagem devices (blino)

* Thu Sep  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.19mdk
- add icons to most tools' windows
- drakboot: do not crash if default autologin or default desktop
  doesn't exist (blino)
- drakupdate_fstab: do not use supermount by default for removable
  devices (blino)
- localedrake:
  o enable SCIM for Amharic language
  o fix missing banner title
- net_applet: tell when internet connection is not configured (blino)
- printerdrake: misc enhancements (till)
- service_harddrake: add modules to conf files if a tv card is detected (blino)

* Tue Aug 31 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.18mdk
- drakclock (warly):
  o check if the ntpdate command succeed or not
  o do not perform a date command when we use ntpdate
  o fix hour setting though mouse on the clock
  o make the hour tick shorter
  o repaint the calendar (especially when the day changed)
- drakconnect:
  o fix crashes (#11100)
  o misc fixes (blino)
- drakfirewall: use the loc zone in sharewall policy only if the loc
  interface exists (florin, #10539)
- harddrake2:
  o add UPS class (fredl)
  o be more enable friendly regarding themes (eg font size properly
    adapt to theme changes)
- net_applet: make it start again

* Mon Aug 30 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.17mdk
- drakclock: fix layout so that NTP frame is not badly cut on small
  resolution (#10971)
- net_applet:
  o allow to connect/disconnect from net_applet
  o launch net_monitor once
  o launch net_monitor in background
- printerdrake:
  o add column to show whether the printers are enabled or disabled to
    the list of available print queues in the main window
  o add command to the edit-printer window to enable and disable print
    queues
  o fix managment of "--expert" command line option

* Sun Aug 29 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.16mdk
- drakconnect: add metric support according to connection type (blino)
- drakroam (Austin):
  o fix "Add" button behavior
  o don't show channel 0 for auto mode
  o move DHCP column to left for better sizing
- drakupdate_fstab: do not mount and add/delete in fstab when many
  partitions (blino, #11005)
- logdrake: fix displaying only last parsed file
- printerdrake (till):
  o add support for daemon-less CUPS client
  o fix graying out of buttons/menu entries in the main window
  o fix unrecognized local queues when the spooler daemon is not
    running during printerdrake startup
- XFdrake: fix crash on resolution change

* Fri Aug 27 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.15mdk
- GUI cleanups:
  o drakboot: fix canceling first step
  o localedrake: let's look & behave like a wizard (fix cancel on
    country choice)
- drakconnect: detect Intel & ATI PCI modems
- localedrake: really install proper packages depending on (locale,
  input method) tuple (and not just those depending on IM)
- XFdrake: add dell D800 specific modeline and resolution (Olivier
  Thauvin)

* Thu Aug 26 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.14mdk
- fix ddcprobe for other archictectures
- drakconnect: restart network for non ethernet adsl devices (blino)
- harddrake service:
  o add --force parameter (#9613)
  o do run configurator
  o restore bootsplash (blino)
- printerdrake: prepare support for daemonless CUPS client (till)
- XFdrake: fix synaptics configuration (blino)

* Wed Aug 25 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.13mdk
- fix modules conf parsing (blino)
- ddcxinfos: extensive rewrite and cleanups to use the new int10
  interface and a last-resort means to get VBE/EDID information from
  special -BOOT kernel during early boot (gwenole)
- drakconnect (blino):
  o add Siol (the bigest ADSL provider in Slovenia) in ADSL providers
    DB (Gregor Pirnaver)
  o allow multiple aliases per host
  o always add an hostname alias and add it on the loopback device
    (#10345)
  o do not ask the user to do an inifinite looping in MCC ...
  o prevent recognize ppp0 as both modem and adsl (#10772)
- drakroam: fix crash when config directory does not exist (#10935)
- listsupportedprinters (till): introduce it for auto-generation of
  Mandrakelinux hardware support DB
- localedrake: 
  o fix country selection (blino, #10938)
  o install proper packages depending on (locale, input method) tuple
- mousedrake, XFdrake (blino):
  o synaptics touchpad support
  o fix wacom support
- printerdrake:
  o fix crash
  o handle print queues with the "lbp660" and "ml85p" drivers (which
    directly communicate with the printer instead of sending the
    output to a CUPS backend) (till)
  o prevent queues using "lbp660" and "ml85p" from opening message
    windows when the print queues are auto-generated by
    dynamic/hotplug (till)
  o if the user gets an error/warning message during setup of a
    lbp660/ml85p queue, he is automatically put back to the previous
    step in the add-printer wizard (till)
  o do not embedd warning messages in the add-printer wizard, as they
    have no "Previous" button (till)

* Mon Aug 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.12mdk
- really fix drakxtools build for ppc & sparc
- use sysfs to detect firewire devices thus fixing eth1394 detection
  (blino)
- drakconnect (blino):
  o ensure iftab is always up-to-date
  o fix spurious ifcfg-ippp0 creation
- net_monitor (blino):
  o do not assume internet isn't configured if obsoleted cnx scripts
    do not exist
  o fix connect button sensitivity
  o watch connection time, not disconnection time
- printerdrake:
  o added fully automatic, non-interactive, X-less print queue set up
    by the "autosetupprintqueues" command, preferrably to be started
    by hotplug
  o fix file check for package installation
  o fix problem of Brother laser printer on parallel port not showing
    its name in auto-detection result.
  o let printer name, description, location be entered after
    determining the model in the add printer wizard
  o let default print queue name be derived from the model instead of
    being "Printer", "Printer1", ...
  o simplify print queue name generation in non-interactive printer
    setup
  o fix "Previous" button in the test page step of the add printer
    wizard
- XFdrake: do not set DRI mode anymore which is not needed anymore
  with latest PAM

* Thu Aug 19 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.11mdk
- drakconnect: use mac_ieee1394 descriptor in iftab for firewire links
  (WIP) (oblin)
- fix drakxtools build for ppc & sparc
- keyboarddrake: fix it not modifying xkb (pixel)
- printerdrake:
  o fix crash
  o prevent potential crashes (blino)
  o do not ignore some internal errors (blino)
  o fix unloaded "usblp" kernel module before local printer
    auto-detection (blino)
  o do not install anymore gimpprint (included in gimp2_0) (till) 
  o do not configure GIMP and OpenOffice.org which were patched so
    that they do not need anymore to be configured regarding print
    queues (till)
  o text fix for scanners in HP's multi-function devices (till)
- service_harddrake: check usb controllers on boot (oblin, #9613)

* Wed Aug 18 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.10mdk
- drakconnect (oblin):
  o do not write 'ifcfg-Manually load a driver' file
  o fix sagem pty in pppd config
  o prevent boot from timeoutingforever if modem can't be synchronized
- localedrake: fix default IM setting when switching language (#10831)
- net_applet: fix tooltip's messages
- harddrake: add a PCMCIA controllers class

* Tue Aug 17 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.9mdk
- drakboot:
  o install acpi and acpid if needed (pixel, #10760)
  o allow to choose net profile in advanced mode (oblin)
  o enable to allow to choose a video mode if boot is not graphical
    while configuring bootsplash (oblin)
- drakbug: better wrapping
- drakconnect (oblin):
  o do not use noipdefault pppd option for pptp connections
  o fix pppoe with sagem ADSL modem
  o write MAC addresses into /etc/iftab
  o pppoe/pptp fixes
- drakroam: support multiple roaming daemons support (oblin)
- drakupdate_fstab: fix adding usb medias (oblin, #10399)
- drakvpn: do not assume drakvpn is already configured if the tunnel
  file is made of comments only (oblin)
- localedrake: handle turkmen and tatar (pablo)
- net_monitor:
  o let's be more l10n-friendly
  o fix default connection time (Fabrice FACORAT)
- XFdrake (pixel):
  o do not use XF86Config-4 anymore
  o handle /etc/X11/xorg.conf
- typo fixes (#10713, ...)

* Wed Aug 11 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.8mdk
- bootloader-config: log command on mkinitrd faillure
- drakbug (olivier):
  o update product list and fix case (bugzilla is case sensitive)
  o fix product, component and version for bugzilla
  o fix bugzilla url
- drakhelp (daouda):
  o use webclient-kde instead of konqueror
  o add epiphany browser
- drakroam:
  o initial import of wlandetect version, from Austin Action
- mousedrake, diskdrake: create /etc/udev/conf.d/xxx.conf as well as
  devfsd rules (pixel)
- net_monitor:
  o add a horizontal separator in stats to prevent visual disguts
    between supposed non aligned labels
  o fix looking aka vertical alignment of labels (Fabrice FACORAT, #10300)
  o fix resizing (Fabrice FACORAT, #10300)
- XFdrake: s/XFree/Xorg/ (pixel)

* Mon Aug  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.7mdk
- diskdrake: switch from raidtools to mdadm (pixel)
- drakboot: sort themes, users and WMs lists
- drakupdate_fstab: do not complain about ips in /etc/fstab (pixel)
- localedrake:
  o changed default font for gb2312 (Funda Wang)
  o rename the "More" button as "Other Countries" (pixel)
- net_applet:
  o do not die when gateway canot be guessed (Joe Bolin)
  o fix status toolip
  o allow multiple instances, but only one per user (Joe Bolin)

* Fri Aug  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.6mdk
- add a 6px border around scrolled TextViews (Fabrice FACORAT, #10561)
- drakbackup: fix crash when selecting an entry in pull down menus
- localedrake:
  o fix configuring IM
  o fix x-unikey support (Larry Nguyen)

* Fri Aug  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.5mdk
- drakclock: if ntp is used, get the new time before updating the
  hwclock (Emmanuel Blindauer, #10537)
- drakconnect (oblin):
  o install kdenetwork-kppp-provider when configuring a modem
  o fix external ISDN modem configuration (Anthill #1033)
  o use ifup/ifdown rather than restarting the network service for
    ADSL & ISDN
- draksound:
  o add support for ALSA on PPC and SPARC
  o update sound drivers list
  o map dmasound_pmac <=> snd-powermac (Christiaan Welvaart)
- fix autologin somewhat (pixel)
- localedrake:
  o add x-unikey support for Vietnamese
  o switch korean to scim-hangul IM by default
- update ppc support (Christiaan Welvaart, pixel)
- XFdrake: replaced XFree86 and XFree with Xorg (pixel, #10531)

* Wed Aug  4 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.4mdk
- don't set /etc/sysconfig/desktop anymore, configure ~/.wmrc,
  ~/.gnome2/gdm and ~/.desktop instead (pixel)

* Tue Aug  3 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.3mdk
- bootloader-config (pixel):
  o try to keep the order of kernel options
  o don't allow unknown kernel names to mess everything
  o handle win4lin kernels
- draksec: sanitize GUI:
  o upcase fields values
  o fix spacing issues
- localedrake:
  o fix current IM setting reading
  o reset IM setting when switching to a new IM
  o support nabi input method too
- net_applet: automatic launch for KDE, GNOME and IceWM (daouda)
- misc typo fixes
- diskdrake: fix LMV resizing (anthill #994) (pixel)
- service_harddrake: fix nuking x.org config on 2.4.x <-> 2.6.x kernel
  switch (#10487) (pixel)

* Fri Jul 30 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.2mdk
- drakbackup (stew):
  o fixes Anthill #1009 and #1010 (DVD recording, disk quota)
  o direct-to-tape enahancement
- drakconnect:
  o do not restart the network service if ethernet modem
  o only restart network for ADSL if we use an ethernet modem
  o fix sagem ADLS modem support (olivier)
- draksec: sync with msec-0.44
- draksplash:
  o do not crash when the image format is unknown
  o fix preview refresh
- localedrake:
  o enable to choose input method in advanced mode
  o support im-ja input method too
- service_harddrake: do not offer to configure mouse if we've already
  automatically reconfigure it b/c of 2.4.x vs 2.6.x switch

* Thu Jul 29 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10.1-0.1mdk
- diskdrake: fix Compaq Smart Array support (pixel)
- drakauth: misc (vincent)
- drakbackup, drakTermServ: fix crashes on append_set (stew)
- drakbug: (daouda)
  o scroll down text while typing
  o many cleanups
  o stable releases are 'Official' and 'Community'
- explanations: only log succesfull renamings
- harddrake GUI: do not automatically configure removable media but
  use diskdrake
- modules: read modutils or module-init-tools config depending on
  which kernel is run (pixel)
- net_monitor: save/restore options

* Wed Jul 21 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-57mdk
- drakauth (vincent):
  o restart services if needed
  o describe authentification kinds
  o modify nss_path one to sub config winbind for AD
- drakconnect: misc bug fixes (olivier)
- localedrake: fix xmodifiers setting which is broken since
  perl-MDK-Common-1.1.13-1mdk
- net_monitor:
  o fix GraphicalContext memory leak (olivier)
  o translate connection type (Fabrice Facorat)
  o fix spacing (from Fabrice Facorat, #10300)

* Mon Jul 19 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-56mdk
- bootloader-config (pixel):
  o save prior boot loader config file (#10072)
  o don't unset prompt when timeout is undefined (and don't care when
    timeout is 0)
  o also add long name when adding add short name
- net_monitor:
  o add a border spacing of 5 pixel (Fabrice Facorat, #10299)
  o disable the connect button if up interface is found (there is
    currently no reliable way to find the gateway interface)
    (olivier blin)
  o use ifup/ifdown to connect/disconnect (olivier blin)
  o no need to be root to monitor connection (olivier blin)
- drakconnect (olivier blin):
  o make connection status check work as non root
  o do not write wireless encryption key if empty
  o use blacklist too for adsl connections

* Sat Jul 17 2004 Daouda LO <daouda@mandrakesoft.com> 10-55mdk
- remove historical consolehelper files (pam.d and console.apps)

* Thu Jul 15 2004 Olivier Blin <blino@mandrake.org> 10-54mdk
- drakboot: use bootloader and Xconfig instead of detect-resolution
- net_applet:
  o use drakconnect to configure network
  o use 'ip route show' to find the gateway device when no GATEWAYDEV
    is defined
- drakauth: add "Active Directory" through winbind (pixel)
- bootloader-config: fix installation on floppy (#10260) (pixel)
- drakedm: typo fix (lost -> lose) (rvojta)

* Thu Jul  8 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-53mdk
- bootloader-config (pixel):
  o nicer "usage: ..." 
  o add actions "add-entry" and "remove-entry"
  o add option --label
  o add option --chainload
  o rename --vmlinuz to --image
  o remove unneeded spaces in append=" foo"
  o handles "optional" in LILO
- drakbackup: fixes for Anthill #927 & #929 (filenames with spaces,
  .backupignore, gui behavior)
- drakboot: update bootsplash even if framebuffer was disabled (oblin)
- XFdrake: add 1024x480 (pixel, #5192)
- redo modules managment (prepare for reading either modprobe.conf or
  modules.conf based on the running kernel version) (pixel)
- fix build with new glibc

* Mon Jul  5 2004 Pixel <pixel@mandrakesoft.com> 10-53mdk
- drakxtools-backend needs ldetect-lst (for complete_usb_storage_info())

* Mon Jul  5 2004 Pixel <pixel@mandrakesoft.com> 10-52mdk
- ensure proper upgrade: explictly tell urpmi that old drakxtools-newt
  conflicts with drakxtools-backend
- drakauth: more features (vincent guardiola)
- drakconnect: pptp support (#6515) (olivier blin)
- localedrake: configure menu-method's language too so that altering
  language is done for KDE menu entries too (instead of just programs'
  messages) (Thierry Vignaud)

* Thu Jul  1 2004 Pixel <pixel@mandrakesoft.com> 10-51mdk
- create package drakxtools-backend
- bootloader configuration: misc fixes (pixel)
- XFdrake: fix typo causing multiple "Keyboard" entries in XF86Config
  (pixel, #10163)

* Thu Jul  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-50mdk
- drakupdate_fstab (oblin): fix moving mount point (#6982, #10175)
- drakauth: for Active Directory, allow: Kerberos, SSL/TLS, simple and
  anonymous (pixel)
- net_monitor (oblin):
  o always display a speed label for transmitted graph
  o allow the user to use different scales for received and
    transmitted (#10177)
  o always draw an arrow next to transmitted amount

* Tue Jun 29 2004 Pixel <pixel@mandrakesoft.com> 10-49mdk
- add bootloader-config (used by bootloader-utils and bootsplash scripts)
- drakboot (pixel):
  o major backend rewrite b/c of code sharing with new installkernel
  o when adding a new kernel, have a nicer new name for conflicting
    entry
  o when modifying kernel parameters in all entries, skip the
    "failsafe" entry (#10143)
  o when modifying a symlink, ensure we also use the long name for the
    old symlink in the existing entries
- drakconnect (Olivier Blin):
  o never disable "DHCP host name" entry box, it shouldn't be linked
    with "Assign host name from DHCP address" checkbox (#2759, #9981)
  o unblacklist sis900 since its link beat detection works with latest
    kernels
- draksound: remove unneeded "above" lines in modules::write_conf
  (Olivier Blin) (#8288)
- ugtk2 layer: catch missing wizard pixmap, otherwise we end up with
  unshown windows and error messages can't pop up (pixel)
- don't require mkbootdisk

* Wed Jun 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-48mdk
- drakboot (oblin):
  o ask for bootloader choice when framebuffer isn't configured (#9925)
  o do not update bootsplash in autologin wizard
- drakclock: be mouse wheel aware (oblin, #9926)
- drakconnect (olivier blin):
  o blacklists the sis900 driver (#9233) for network hotplugging
  o properly handle ascii WEP keys (#9884)
  o rephrase zeroconf dialog (cybercfo)
- drakxtv: fix tv driver not loaded on boot (oblin, #9112)
- localedrake: new default IM for CKJ
  o set up SCIM for chinese
  o set uo SCIM+UIM for japanese
- mousedrake: load usbhid instead of hid is now named (pixel, svetljo)
- XFdrake (pixel):
  o better auto monitor config
  o sync with bootsplash's detect-resolution

* Tue Jun 22 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-47mdk
- add net_applet (daouda)
- drakconnect: update ADSL ISP database (baud <baud123@tuxfamily.org>):
  o default to pppoa method whenever encapsulation is 6 (PPPoA VCmux),
  o default to pppoe method whenever encapsulation is 1 (PPPoE LLC)
  o add new ISP entries : Belgium ADSL Office, Brasil (4 ISP),
    Bulgaria ISDN/POTS, Greece, Switzerland BlueWin / Swisscom Telecom
    Italia/Office Users, Turboline Austria Telstra,
- harddrake2: do not display version number in title bar
- shorewall configuration: accept from fw to loc (florin)

* Mon Jun 21 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-46mdk
- harddrake service:
  o do not uselessy fork shells
  o faster auto mouse reconfiguration on major kernel switch
  o fix logs of newly added hardware
  o fix mouse autoconfiguration done on every boot instead of on 2.4.x/2.6.x
    switches
  o handle newly added wireless network card (broken since early 2004/02)
  o log error when we cannot run the config tool or when it isn't executable
  o only log about nv <-> nvidia swtich only if we do have to perform it
- harddrake GUI:
  o display media type for mass storage devices
  o enhanced data for mice and hard disks
  o fix undisplayed fields
  o show disk ID if we cannot guess its vendor string from it
  o show splited vendor and description fields for USB hard disks too
  o really ensure that "identification" section is displayed first
 
* Fri Jun 18 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-45mdk
- authentication: more LDAP work (pixel)
- drakbackup: fix .backupignore issue (stew)
- drakupdate_fstab: add support for floppies
- harddrake service:
  o mouse: autoreconfigure it when switching between 2.4.x and 2.6.x kernels
  o network: automatic config with DHCP of new cards
  o removable media: automatically config
  o x11:
    * do not automatically swtich from nv to nvidia driver (b/c the
      nvidia driver is buggy on some machines)
    * automatic configuration of new card
  o only stop the boot progress bar if we've a non automatic tool to run
- harddrake GUI:
  o show more data on SCSI disks
  o do not display USB disks in both harddisks and unknown sections
  o fix cpu and SCSI hd help
  o show right driver for USB devices (from /proc/bus/usb/devices)
  o enhanced help
  o show detailled data on bus connection
- interactive layer: display "cancel" button instead of "previous" in
  wizards' first step

* Mon Jun 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-44mdk
- diskdrake: fix hde devfs link (pixel)
- drakconnect: start to make strings more helpfull
- drakperm: enable drag 'n drop (only when looking at customized settings)
- draksec: do not show empty pages in notebook if security level is not set
- draksplash: make it work again...
- harddrake2:
  o do not list usb hard disk as unknown (fix doble entries)
  o fix misdetection of nvidia nforce ethernet cards (broken since forcedeth
    replaced nvnet on 2004-01-21 in MDK10's ldetect-lst)
  o ethernet card detection: only rely on driver for matching ethernet cards,
    thus preventing mislisting of other/unwanted devices and enableing to catch
    ldetect/ldetect-lst/detect_devices bugs where some devices are *not* seen by
    drakx and drakconnect.
  o display more data about hard disks (geometry, number of primary/extended
    partitions)

* Wed Jun  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-43mdk
- drakauth: add "Active Directory" authentication (WIP) (pixel)
- drakbackup: (stew)
  o deal with kernel ring buffer that is flooded with msgs for tape
    device detection (#9877)
  o GUI fixes
  o enforce binary ftp transfers
- drakconnect: (poulpy)
  o switch ONBOOT to on/off for isdn and adsl connections
  o new way to specify how to up connection for pppoe(xDSL) and
    others(ADSL)
  o rename /etc/ppp/peers/adsl as /etc/ppp/peers/ppp0 as we now use
    ifup-ppp for adsl, it will look for ppp0
- drakservices: add descriptions for NFS and SMB (#9940) (pixel)
- harddrake service: run it earlier (aka before network service)
- XFdrake: add resolution 1920x1200 called WUXGA (used by Dell Laptops
  Inspiron 8500, 8600 and Latitude D800) (#6795) (pixel)
- XFdrake, drakedm: switch to x.org  (pixel)

* Tue Jun  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-42mdk
- handle the nfs/smb service disabled (Olivier Blin)
- drakconnect:
  o handle interface w/o ip addresses
  o make LAN wizard more user friendly: move "manual choice" after 
    detected interfaces
  o detect again ethernet interfaces that are down (got broken in 10-38mdk)
- drakboot:
  o do not write partial GRUB config file (thus garbaging previous config) if an
    error occured
  o fix "two windows appears on canceling after an exception" bug

* Fri May 28 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-41mdk
- drakconnect:
  o fix protocol switching from manual to DHCP when stepping back in
    wizard
  o read VLAN and IP aliased interfaces config too
- drakbackup: fix typo in tape restore (Federico Belvisi).

* Fri May 28 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-40mdk
- drakconnect:
  o blacklist loopback interface in new detection scheme
  o switch from internet service to regular ifcfg files (poulpy) (WIP)
  o fallback on sysfs in order to get driver and card description when
    ethtool is not supported (eg: ipw2100 driver for intel centrino)

* Thu May 27 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-39mdk
- diskdrake (pixel):
  o allow /home on nfs (#7460)
  o disable package instead of removing nfs-utils or samba-server
    (when "diskdrake --fileshare" disables a export kind) (#9804)

* Thu May 27 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-38mdk
- detect aliased network interfaces too
- drakfirewall: handle BitTorrent (robert vojta)
- keyboardrake (pablo):
  o support more keyboards
  o Nepali uses devanagari script
- localedrake: handle Latgalian language (pablo)
- net_monitor: ignore sit0
- switch Japanese input method to "uim" (pablo)

* Tue May 25 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-37mdk
- drakbackup: fix dropped .txt files when running mkisofs (stew)
  (Anthill #799)
- drakconnect (#9669):
  o prevent identification mismatch on ethtool results
  o fix card name lookup when driver does not support GDRVINFO command
    from ETHTOOL ioctl and there's only one card managed by this
    driver
- switch from deprecated OptionMenu into new ComboBox widget

* Mon May 24 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-36mdk
- ugtk2:: still provide compat stuff for OptionMenu widget (#9826)
- drakTermServ: add /etc/modprobe* mount points for client hardware
  config (stew)

* Wed May 19 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-35mdk
- authentication:
  o fix winbind configuration and do the same for LDAP
    and NIS (vincent guardiola, pixel)
  o install autofs for nis authentication (florin & fcrozat)
- diskdrake: handle LABEL=foobar in /etc/fstab (pixel)
  (ex2/3 only for now, no xfs)
- drakclock: do saner check for ntp package (Robert Vojta)
- drakconnect:
  o fix speedtouch ADSL model (using kernel mode) (poulpy)
  o better LAN vs wireless filtering by using SIOCGIWNAME ioctl)
  o handle ipw2100 wireless driver
  o do not offer to set DOMAINNAME2 since it is never saved nor read
    (#9580)
  o kill "speedtouch and ISDN only work under 2.4 kernel" warnings
    (poulpy)
- drakfirewall: open more ports for samba
- harddrake service: do not run XFdrake in automatic mode
- misc cleanups & bug fixes (pixel)
- scannerdrake: fix firmware installation (till)
- XFdrake (pixel):
  o can now configure monitors on heads > 1
  o do not succeed automatic configuration (not auto_install) when
    there is many cards (as requested by Joe Bolin)
  o speed-up monitor choosing dialog when {VendorName} is undef
  o vmware doesn't like 24bpp (#9755)
  o defaults to the greatest depth rather than 24
- do not prefer devfs names when reading /proc/mounts (which uses
  devfs names) (pixel)
- ugtk2 layer: transparently replace obsolete OptionMenu widget by the
  new ComboBox widget

* Tue May  4 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-34mdk
- drakconnect:
  o fix last step of interface destruction wizard
  o wizard: take ISDN protocol into account for people outside Europe
    to use it (poulpy)
- drakupdate_fstab: fix adding twice an entry in fstab, one with the
  old name, one with the devfs name (pixel)
- XFdrake: kill XFree86 3.x support (pixel)

* Fri Apr 30 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-33mdk
- create ~/tmp if needed when running a program
- device managment: fix sdX <=> scsi devices mapping (especially for
  USB devices) (pixel)
- drakclock: time is displayed as HH:MM:SS with RTL languages
- drakconnect (poulpy):
  o manage interface: more gui layout fixes
  o try harder to locate firmware on windows partition (#3793)
  o no need to up ippp0 in net_cnx_up, it's been up'ed at startup
- harddrake gui: list SATA controllers in their own category (anthill
  #741)
- harddrake service: log removed/added hw
- localedrake: use utf8 if any of the languages chosen is utf8, not
  only the main one (pixel)

* Fri Apr 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-32mdk
- diskdrake, XFdrake: make --auto really not interactive
- drakconnect:
  o wizard: fix ISDN support (poulpy)
  o manage interface: smoother layout
- drakxtv:
  o fix brown paper bag bug regarding tv cards detection
  o sync card and tuner lists with 2.6.6-rc2
- harddrake GUI: split USB sontrollers and ports
  o new data structure
- harddrake service: autoconfigure X11, sound and removable media
- log more actions regarding modules managment in explanations

* Tue Apr 20 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-31mdk
- drakbackup: some drives don't return "ATIP info from disk" (stew)
- drakclock: check /etc/init.d/ntpd instead of /etc/ntp.conf for ntp
  installation (daouda)
- drakfont: fix font importing (#9423) (dam's)
- drakconnect (manage interface): fix insensitive IPADDR, NETMASK and
  GATEWAY fields by default are not sensitive by default in DHCP
  (broken by #8498 fix) (poulpyà

* Thu Apr  8 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-30mdk
- fix inverted translations in french catalog (#8217)
- fix drakxtools postuninstall script
- drakbackup (stew):
  o remove config-info (will be in a man page)
  o reuse more code from ugtk2 layer regarding cursors managment
  o combine/rework restore code
- drakTermServ (stew):
  o do not move existing dhcpd.conf
  o add an include for terminal-server instead
- drakups: update to new libconf-0.32 API (dam's)
- harddrake service: log nv<=>nvidia switches
- localedrake: set default font to use in KDE for devanagari and
  malayalam scripts
- ugtk2: fix faillure with perl-Gtk+-1.04x (#9411)

* Mon Mar 29 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-29mdk
- harddrake service: skip nv/nvidia test when there's no nvidia card

* Mon Mar 29 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-28mdk
- harddrake service: fix disabling nvidia driver (#9300)

* Fri Mar 26 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-27mdk
- drakconnect:
  o fix some bugs in ISDN configuration
  o warn than speedtouch only works with 2.4.x kernels for now
  o fix "manage interface" that broke speedtouch configuration
  o blacklist b44 for ifplugd
- drakboot blacklist again Savage gfx cards, they're broken again with
  lilo

* Wed Mar 24 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-26mdk
- diskdrake: tag removable medias as noauto in fstab file (pixel, #9076)
- drakboot: add nolapic support option (planel)
- drakclock (Robert Vojta, #9141):
  o display current timezone
  o sort servers
- drakclock, drakperm: GUI fixes (Robert Vojta: #9141, #9153)
- drakconnect:
  o complain louder about supported kernels for ISDN cards
  o enable to delete ADSL and ISDN connections
  o do not complain anymore about kernel when using bewan adsl modems
    since they works now with 2.6.x kernels
  o do write drakconnect config file when there's only one configured
    interface (#8998)
  o fix speedtouch support: use kernel mode on 2.6.x kernels
- drakgw: fix drakgw removing MII_NOT_SUPPORTED parameter from ifcfg
- drakTermServ: fix button layout
- drakxtv:
  o read current configuration (Scott Mazur)
  o fix setting options for bttv instead of saa7134 (#5612)
  o fix saa7134 detection (#5612)
  o fix wiping out /etc/modules.conf (Scott Mazur)
  o default canada-cable to NTSC (Scott Mazur)
  o handle tv cards managed by cx88 and saa7134 (#9112)
  o use right device (#3193)
  o offer to set the user to config (#3193)
  o sync with 2.6.3-4mdk
- firewall: do not write the REDIRECT squid rules if one has only one
  NIC connected to the net zone (florin)
- harddrake service: switch between nv and nvidia driver if commercial driver
  isn't installed
- keyboarddrake: az, tr and tr_f needs XkbOptions 'caps:shift' (pixel)
- logdrake: fix non first searches (#9115)

* Fri Mar 19 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-25mdk
- add missing icons for localedrake menu entry (dadou)
- diskdrake: fix compaq smart array support (pixel, #9029)
- drakboot: reread current bootsplash config (olivier blin, #8888)
- drakconnect:
  o always offer to restart adsl connections
  o fix bewan adsl modem support by providing an ad-how
    /etc/ppp/options
  o only warn about the fact we need 2.4.x kernel
    * when we're under 2.6.x
    * for bewan modem (not for other adsl modems) and pci rtc modems
  o only kill pppoa for sagem modem (fix bewan modem shutdown)
- draksound: install alsa-utils if needed (#6288)
- include drakups again

* Wed Mar 17 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-24mdk
- set window icon
- diskdrake: (pixel)
  o fix "xp does not boot anymore" (#7302, #7959, #8891)
  o add --change-geometry=<device>=[<cylinders>,]<heads>,<sectors>
  option in order to allow forcing the geometry used in the partition
  table. This allows helping poor Windows booting using old int13
  function 2.  This should work when Windows has not been resized.
- drakclock: fix server lookup (#8846)
- drakconnect:
  o do not pass eth interface and user to adsl-start, they're already
    provided in pppoe.conf (#2004)
  o fix pci modem support
  o fix SmartLink modem managment (#8959)
  o really fix modem symlink (#7967)
  o try harder to get a name (in wizard) and information (in manage
    interface) for cards whose driver do not support ethtool ioctl
  o update wanadoo dns servers ip addresses
  o wizard:
    * bewan support
    * fix adsl stop on pppoa links
    * preselect pppoa for bewan modems
    * for ADSL Bewan, ISDN and PCI modems, warn that only 2.4.x
      kernels are supported
    * only show encapsulation parameter for sagem modem
  o "internet access" window:
    * enable to alter hostname
    * do not offer to alter domain name since this is achievable
      through FQDN
- drakfont: make subdialogs be transcient for main window when not
  embedded
- drakedm: fix dm restart
- draksound (olivier blin, #8501):
   o do not alter oss<->alsa drivers mapping table
   o when current driver doesn't match current sound card, list
     alternatives for both current driver and the default driver
- drakTermServ: fix misnamed inittab (stew)
- drakupdate_fstab: choose wether to use supermount is now based on
  variable SUPERMOUNT in /etc/sysconfig/dynamic (pixel)
- harddrake2:
  o show module for system bridges if it's not unknown (aka not
    managed by kernel core)
  o update icons
- localedrake: list Filipino, Low-Saxon and Kyrgyz (pablo)
- logdrake: fix wizard
- service_harddrake:
  o remove /etc/asound.state *before* restarting sound service
  o add agpgart modules to modprobe.preload if needed

* Mon Mar 15 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-23mdk
- drakbackup: (stew)
  o install extra packages when using wizard too
  o report error on key transfer in GUI if needed
- drakboot:
  o list yes/no for autologin in a more intuitive way, that is yes is
    grouped with user and wm pull down menus (robert.vojta@qcm.cz,
    anthill #390)
  o always generate a precise entry using the precise version and
    remove the linux-2.4 or linux-2.6 (but keep the "linux" entry)
    (pixel)
- drakclock: make the ntpdate after stopping the ntpd (manu@agat.net,
  #8141)
- drakfont: make "install" button be insensitive when there's no
  selected fonts
- drakconnect:
  o fix misdetection of some network cards (aka do not try to match a
    physical device when SIOCETHTOOL ioctl is not supported) (#8010)
  o fix missing quotes around wireless encryption key (#8887)
  o wizard:
    * do not list anymore wireless cards in LAN connection, only in
      wireless connections
    * fix unlisted ADSL modems when there's no network card (#8611)
    * handle orinoco_pci and orinoco_plx driven card as wireless ones
    * skip "start on boot" step for LAN (already managed by network
      scripts)
    * write ether conf later on QA request
  o renew "internet access" window:
    * sanitize buttons layout (#8637)
    * sanitize fields layout
    * fix config reading/writing
    * fix connection status (#7800)
    * fix unlisted first dns server
  o manage interface:
    * do not write IPADDR, NETMASK and NETWORK fields in ifcfg-ethX
      when using DHCP (fix writing "no ip"/"no netmask" in config file)
    * default protocol is dhcp (fix fields checking when an interface
      isn't yet configured)
    * fix gateway setting (#6527)
- drakfirewall, drakgw: add ppp+ and ippp+ at the interfaces list
  (florin) (#8419)
- localedrake: always define KDM fonts dependending on encoding
  (pablo, #8714)
- logdrake: fix explanations in mcc that got broken by #8412 speedup
- printerdrake: install "scanner-gui" instead of "xsane" when it sets
  up an HP multi-function device (till)
- scannerdrake: install "scanner-gui" instead of "xsane", so that
  scanning GUI actually used can be determined by the system
  environment (till)

* Thu Mar 11 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-22mdk
- fix imm & ppa managment on kernel 2.6 (pixel)
- no entry in fstab for zips (now cleanly done by hotplug) (pixel)
- drakbackup (stew):
  o fix crash on first wizard run (#8654)
  o deal with mixture of formats on restore
  o do not save host passwd when user requests not to (#8700)
  o fix issue with first incremental pass not using base as
    comparison
  o support for plain tar (#8676)
- drakconnect wizard:
  o start to handle bewan ADSL modems
  o port old ISDN wizard upon new wizard layer
- drakfirewall, drakgw: network card name rather than just ethX in device list
  (florin and me)
- drakgw (florin):
  o add some tests for the REDIRECT squid rules
  o fix previous button on first step (anthill #386)
  o fix "sharing already configured" #8669 (florin)
  o fix the proxy REDIRECT shorewall rule,
  o fix the disable, enable functions
  o fix the shorewall interfaces configuration
  o really enable the proxy squid
- draksplash: make it works again
- drakTermServ (stew):
  o add gdm user if needed
  o autologin warning
  o copy server X keyboard config to client
  o default kernel version
  o default thin client setup
  o do not destroy "fat" client inittab
  o use std banner
- drakgw: fix previous button on first step (anthill #387)
- harddrake2: fix ISDN cards detection
- keyboardrake: list jp106 keyboard too (pablo)
- logdrake: searching speedup (#8412)
- printerdrake (till):
  o let URIs listed by "lpinfo -v" be shown in the dialog for entering
    a URI manually
  o make first dialog be somewhat clearer
- XFdrake: catch exception (#8726) (pixel)

* Wed Mar  3 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-21mdk
- drakconnect: add australia in adsl providers db (#5056)
- support cryptoloop and aes when using encryption on kernel 2.6 (pixel)

* Wed Mar  3 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-20mdk
- drakbackup: use preferred conf file read/write method (stew)
- drakconnect: hide dns settings by default when using dhcp
- drakupdate_fstab (pixel):
  o fix device removal
  o log calls
- printerdrake: fix HPOJ configuration when manually setting up a
  device (till)

* Tue Mar  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-19mdk
- fix doble ISDN detection (#6535)
- drakconnect: fix modem symlink (#7967)
- drakboot --boot is now a wizard
- printerdrake: fix missing "default settings" option in the printer
  options dialog (till)

* Tue Mar  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-18mdk
- drakboot (pixel):
  o if the default bootloader entry is invalid, choose another one
  o remove "VT8751 [ProSavageDDR P4M266] VGA Controller" (0x5333,
    0x8d04) from graphical lilo blacklist (#8133)
- drakconnect:
  o fix pci modem type matching
  o list pump in dhcp clients list (synced with ifup one)
  o preselect first availlable dhcp client (according to ifup priority
    list)

* Tue Mar  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-17mdk
- logdrake mail alert: fix crash due to icon renaming

* Mon Mar  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-16mdk
- adduserdrake: default to "man" icon (pixel)
- drakconnect manage interface: fix bootproto filling (#8498)
- harddrake2: update icons
- printerdrake (till):
  o do not configure the GIMP-Print plug-in on more than 50 users (#6423)
  o fix no "ptal:/..." in manual device URI list (#8483)
- scannerdrake (till): fix firmware not found by "gt68xx" SANE backend
  (#7242)

* Mon Mar  1 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-15mdk
- left align labels
- drakfirewall: remove the masq zone and add policies, rules only if
  there is an interface in loc (florin)
- draksec:
  o sanitize main explanation text
  o prevent pull-down menus to fill availlable space in packtables
- printerdrake (till):
  o fix HPOJ config
  o support new HP multi-function devices
  o better Lexmark X125 printer support

* Fri Feb 27 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-14mdk
- drakautoinst: support two-floppies boot style for replay_install
  disk as well (gc)
- drakbackup: fix tape backup/restore (#8284) (stew)
- drakconnect: fix crash on manually choosing modem again
- printerdrake: better layout for about dialog box (dadou)

* Thu Feb 26 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-13mdk
- drakconnect wizard:
  o never delete up/down scripts
  o only write internet service if start at boot requested
- banners: prevent shadow to be darker on theme switches

* Thu Feb 26 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-12mdk
- drakbackup: use ATAPI:/dev/hdX for both 2.4/2.6 compatibility (stew)
- drakconnect wizard:
  o do not ask for apply settings since most just have been written
  o only write ether config for lan...
  o install needed packages for pppoa, pppoe, pptp
- drakTermServ (stew):
  o really filter symlinked kernels. nohup the dm restart
  o don't let any kernel symlinks be visible for making NBIs
- harddrake-ui package: requires sane-backends so that scanner
  detection works smoothly (#8305)
- localedrake: use xim by default for CJK languages for which we don't
  ship good enough native gtk2 input methods (pablo)

* Wed Feb 25 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-11mdk
- harddrake service: 
  o look at sound cards changes on bootstrapping
  o when sound card is added/removed, delete current sound levels so
    that sound service reset it to sg sane

* Wed Feb 25 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-10mdk
- drakbackup: rework CD recording for ATA device setup (stew)
- drakconnect manage interface (poulpy):
  o modem configuration has been completed
  o write /root/.kde/share/config/kppprc for any local change

* Tue Feb 24 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-9mdk
- drakconnect: alter both /etc/analog/adiusbadsl.conf and
  /etc/eagle-usb/eagle-usb.conf when configuring sagemXXX

* Tue Feb 24 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-8mdk
- drakconnect wizard:
  o ethernet: fix module lookup for pcmcia cards
  o adsl ISP db (Benoit Audouard):
    * set default protocol to pppoa for various ISPs
    * update 9telecom entry
    * add encapsulation method for "tiscali 512k.fr"
    * fix wrongly inverted encapsulation methods for "Free" isp cnx
      offers
- drakTermServ (stew):
  o mknbi-set always wants a kernel version now
  o deal with conflicts with msec > 3 and exporting / (use
    no_root_squash).
  o always pass a kernel to mkinitrd-net (#8216)
  o add --restart option for terminal-server.
- printerdrake, scannerdrake: misc gui fixes (till)
- printerdrake (till):
  o give clear warning/error messages if a package installation fails
  o let printer model in first-time dialog also be shown if there is
    no description field in the device ID of the printer
- scannerdrake: ask user before installing packages (till)
 
* Mon Feb 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-7mdk
- drakconnect
  o add wizard:
    * always write up/down scripts
    * only write initscript when starting at boot was choosen
    * write ethX aliases and ifup/ifdown scripts when configuring a LAN
    connection
  o remove wizard:
    * when no network configuration is configured, just report it
    * only list configured interfaces when offering to delete them
    * keep ethX aliases b/c in order to prevent ethX be renumbered on
      next boot
    * down the network interface when deleting it

* Mon Feb 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-6mdk
- drakconnect: fix sagem8xx && speedtouch adsl modem scripts

* Mon Feb 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-5mdk
- drakconnect: write vci and vpi parameters in decimal base when
  configuring speedtouch

* Mon Feb 23 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-4mdk
- drakbackup (stew):
  o verify user has selected a cron interval and media (#8138)
  o tweak wizard setup
- drakconnect:
  o misc santizing in manual module loading
  o adsl provider db: fix vci number for Belgium and France (poulpy)
  o wizard:
    * modem:
      + enable one to manually choose the serial port to use while
        configuring modem
      + really default to dynamic dns, gateway and ip (really fix #7705)
      + do not overwrite current kppp settings with provider db ones
        but on provider switch
    * adsl: prevent having to choose between '' and 'adsl' connections
    * ethernet: enable one to manually load a driver like expert mode
      in old pre-10.0 wizard
  o manage interface:
    * modem:
      + read kppp authentication method
      + handle new PAP/CHAP method
    * ethernet:
      + handle and translate BOOTPROTO
      + do not complain about gateway format when it's not set
    * fix untranslated strings

* Fri Feb 20 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-3mdk
- drakconnect: fix empty vci/vpi paremeters when speetouch firmware
  wasn't provided
- logdrake: fix title when run from mcc (#8111)

* Fri Feb 20 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-2mdk
- drakboot/diskdrake updates regarding partition renumbering (pixel)
- drakconnect:
  o do not overwrite provider vpi/vci settings (poulpy)
  o detect more sagem 8xx modems
  o enable to refuse network restarting
  o add "Free non degroupe 1024/256" in adsl provider db
- drakperm: fix "current" checkbox vs "group" and "user" pull-down
  menus
- localedrake: better uim support (pablo)
- modules configuration: fix some agpgart aliases issues regarding
  2.4.x/2.6.x kernels (pixel)

* Fri Feb 20 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-1mdk
- drakconnect: fix writing modules aliases (fix broken speedtouch)
- drakbackup: use Gnome icon order (stew)

* Thu Feb 19 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.21mdk
- drakboot: fix theme displaying under console (Olivier Blin)
- drakconnect: since no PCMCIA cards support link status notification,
  ifplugd should be disabled for all pcmcia cards by default (#8031)
- XFdrake: kill spurious icons (pixel)
- fix some wrapping (pixel)
- do not use global scrolled window but many local scrolled windows
  instead (pixel)
- fix uim-xim input method (pablo)

* Thu Feb 19 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.20mdk
- fix broken "advanced" and "help" buttons (pixel)
- switch japanese from kinput2 to uim input method
- fix file dialog when embedded (#7984) (pixel)
- drakbackup (stew):
  o fix issue with multisession CDs (Anthill #349)
  o encourage user to finish configuring media before leaving wizard.
- drakvpn (florin):
  o add plenty of help files, add anonymous support for sainfo
  o add quite much help explanations
  o add anonymous support in sainfo
- harddrake2: sanitize buttons layout when embedded

* Wed Feb 18 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.19mdk
- diskdrake: type 0x17 can be ntfs
- drakbackup: rework backupignore behavior (Anthill #306) (stew)
- drakconnect
  o wizard:
    * do not use ifplugd on wireless connections by default
    * fix "network needs to be restarted" step
    * do not overwrite current wireless parameters with default
      values
    * tag some wireless options as advanced ones
  o manage interface:
    * update adsl (poulpy)
    * sanitize buttons layout

* Tue Feb 17 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.18mdk
- new default icon for wizards banner
- drakconnect
  o wizard:
    * handle atmel_cs wireless driver
    * sort lan protocols
  o manage interface: update (poulpy)
- drakvpn: one can now start from scratch with ipsec.conf (florin)
- enforce gnome button order everywhere
- harddrake: really fix doble blanked ISDN detection
- mousedrake (pixel):
  o detection defaults on automatic choices
  o fix mouse detection on kernel 2.4
- printerdrake: fix problem that not used parallel ports were detected
  as printers (till)

* Tue Feb 17 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.17mdk
- drakboot: remove bad entries after reading existing conf file (pixel)
- drakclock: let's look better when embedded
- drakconnect:
  o wizard:
    * explain about DNS (#7908)
    * fix automatically found "...2" dns when network is done
  o manage interface: check gateway entry (poulpy)
- drakfont: new banner style
- drakvpn:
  o fix drakvpn logic when translated
  o fix steps skiped b/c of translations
  o start to sanitize gui (more user friendly labels, pull-down menus, ...)
  o fix the ";" mark in the "Security Policies" section (florin)
- interactive layer: don't have a scroll inside a scroll which causes
  display pbs (#7433) (pixel)
- printerdrake (till):
  o recognize parallel printers also when they miss the
    "CLASS:PRINTER;" in their device ID string (ex: Brother HL-720,
    bug #7753)
  o warn when there's no network access
  o remove printer list button when there's no network also in expert
    mode.

* Sun Feb 15 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.16mdk
- fix harddrake crash (#7897)
- printerdrake (till):
  o handle weird printer ID strings, as the one of the Brother HL-720
    with empty manufacturer and description fields (#7753).
  o recognize also "SN:" as serial number field in printer ID string
    (HP PhotoSmart 7760, bug #6534).
  o load the "usblp" module instead of the "printer" one on kernel
    2.6.x

* Sat Feb 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.15mdk
- drakbackup: (stew)
  o FTP restore failure feedback
  o allow multiple catalog/file restore selection
- drakconnect:
  o fix automatically found "...2" dns server
  o fix crash on canceling "already configured net device"
    configuration (#7679)
  o by default do not start connection at boot for modems (#7705)
  o prevent displaying dummy empty fields in text mode (#7593)
- harddrake:
  o fix ISDN detection (#6535)
  o prevent detecting twice the same devices (#4906)
  o workaround sane-find-scanner detecting too much usb scanners
- center popup windows (pixel)
- don't have a wait_message above another empty wait_message when
  probing hardware (pixel)
- add support for embedding rpmdrake

* Fri Feb 13 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.14mdk
- drakboot: better grub support, esp. when /boot is a separate
  partition (pixel)
- diskdrake: reconfigure boot loader on partition renumbering
- wizards: add relief around trees and lists

* Fri Feb 13 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.13mdk
- all tools: new banner style
- add drakvpn (florin)
- drakbackup: fix crash on file search, failure to report ftp error
  (stew)
- drakconnect:
  o wizard:
    * fix wireless network interfaces detection
    * ask isp for ip and gateway by default (#7705)
  o manage interface: (poulpy)
    * fix adsl/eth confusion
    * fix apply button
- harddrake service: only probe for local printers
- harddrake2:
  o remove statusbar on interface team request
  o do not force black color for fields values which badly conflict
    with inverted accessibility themes
- fix module dependancies problem because of 2.4/2.6 mappings, better
  support 2.4 and 2.6 alltogether by keeping 2.4 names in modules.conf
  (gc)
- XFdrake: handle packages not found (#7786)

* Thu Feb 12 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.12mdk
- drakconnect:
  o preselect right protocol for ethernet though connections
  o only offer to connect now for ppp connections
  o fix module retrieving when configuring an adsl connection over
    ethernet
- authentication: (pixel)
  o install ldap packages *before* doing ldapsearch
  o pam*.so modules do not have /lib/security/ prefix anymore

* Thu Feb 12 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.11mdk
- drakconnect wizard:
  o fix choosing dhcp as adsl protocol
  o do not allow to step forward if no network card was found
    (workaround #7672)
- keyboardrake: support 2.6.x kernel (pixel)
- drakbackup: misc changes (stew)
- draksec: fix unable to save checks when config file is empty
- harddrake: support more webcams

* Tue Feb 10 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.10mdk
- fix poped dialogs when embedded (#7246) (pixel)
- drakbackup/drakTermServ: misc updates (stew)

* Mon Feb  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.9mdk
- drakconnect wizard:
  o fix unability to select gateway (#7585)
  o detect athX interfaces too (#7531)
- drakfont: fix crash on option toggling (#7248)

* Mon Feb  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.8mdk
- drakconnect wizard:
  o blacklist forcedeth for network hotplug (#7389)
  o fix ethernet devices description matching
  o fix unwritten ethernet interface config
  o fix empty list in "multiple internet_connexions" step
- fix vendor/description for some Lite-On drives
- ugtk2 layer: fix some layout (spurious space at window bottom)
  (pixel)

* Sun Feb  8 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.7mdk
- drakx11: make XFdrake startup be instantenous for non nv|ati cards
- drakTermServ: add PXE image support (Venantius Kumar)

* Fri Feb  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.6mdk
- move drakbug, drakclock, drakperm, draksec, drakTermServ,
  net_monitor in drakxtools since they require ugtk2 (#7413)
- workaround gtk+ bug #133489 (behaviour on click when in scrolled
  window) (pixel)
- drakboot: do not try anymore to set global video mode and compat
  option
- drakfirewall: handle ip ranges (#7172) (pixel)
- draksound: advertize alsaconf too since sndconfig failled for cards
  only managed by ALSA (#7456)
- logdrake: do not fail when disabling twice the alert mail cron
- mousedrake: allow changing protocol in standalone (pixel)

* Fri Feb  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.5mdk
- fix embedded apps

* Fri Feb  6 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.4mdk
- print --help on stdout rather than stderr (gc according to gnu std) 
- diskdrake: (pixel)
  o fix lvm support when devfs is not mounted
  o fix lvm extent sizing (fix illegal division by 0)
  o fix getting the output of pvs vgs lvs commands
  o fix get_lvs() (and use lvs instead of vgdisplay)
  o don't display start sector and cylinders used for LVs
  o display "Number of logical extents" of LVs
- drakbackup: provide more detailed info on files backed
  up/ignored. (Anthill #306) (stew)
- drakboot: write fstab for /tmp using tmpfs when "clean /tmp" is
  chosen (pixel)
- drakboot, drakconnect: fix some layouts
- drakconnect wizard:
  o fix pcmcia card config (#7401, #7431)
  o fix wireless settings (#7432, faillure to set parameters)
  o split wireless step into two steps since there way too much
    options
- draktermserv: fix user list in mdkkdm (stew)
- harddrake: fix module parameters with kernel-2.6.x
- keyboardrake, localedrake: fix some locales (pablo)
- mousedrake: use protocol "ExplorerPS/2" instead of "auto" for kernel
  2.6 (pixel)
- XFdrake: (pixel)
  o do not test X config under vmware (#5346)
  o allow 24bpp for DRI (since all drivers now support it)

* Mon Feb  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.3mdk
- drakconnect wizard:
  o support more wireless cards
  o split out "wireless connection" configuration out of "lan
    connections" path
- logdrake: (arnaud)
  o make cron script be able to use either local smtp server or a
    remote one
  o add "remove cron entry" on arnaud request

* Mon Feb  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.2mdk
- draconnect: preselect pppoa for speetouch again

* Mon Feb  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-0.1mdk
- harddrake: fix adsl modem detection
- draksound: handle new aureal drivers
- do not user ide-scsi emulation for ide ZIPs (pixel)
- do no ide-scsi emulation for cd burners with kernel-2.6.x (pixel)

* Mon Feb  2 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-28mdk
- drakconnect:
  o enable to set hostname even when using DHCP (#7230)
  o handle not loaded drivers (#7273)

* Fri Jan 30 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-27mdk
- drakconnect:
  o wizard:
    * fix configuring unconfigured eth interfaces
    * ignore spurious .directory entries when loading kppp provider db
    * do not offer to select dhcp client for static interfaces
  o manage: only show gateway for eth devices (poulpy)
- diskdrake (pixel):
  o fix overflows at 4GB when adding partitions
  o tell kernel to remove the extended partition
  o replace iocharset= with nls= for ntfs in /etc/fstab

* Thu Jan 29 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-26mdk
- drakconnect: use somewhat nicer interfaces name (eg: "eth0: 3com
  905") in manage interface (poulpy)
- drakTermServ: configure clients with defined IPs to set hostname so
  gnome works (stew)
- fix accentued characters with fr and ru locales (pablo)

* Thu Jan 29 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-25mdk
- drakconnect:
  o wizard:
    * fix ethernet network card list
    * fix interface config file writing
    * fix DHCP client installation
    * fix static/dhcp step branching
  o manage interface: (poulpy)
	* fix modem login fetching
	* use somewhat nicer interfaces name (eg: ethernet0 rather than
	  eth0)
     * fix adsl loading and saving
- draksec:
  o add help for newly introduced MAIL_EMPTY_CONTENT item
  o notify that shell timeout is in seconds
  o fix parsing of default values for multi argument msec functions
- net_monitor: do not force switch to last page on network interface
  reload

* Wed Jan 28 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-23mdk
- drakbackup: (stew)
  o another cron issue reported on Anthill
  o fix broken sys, other restore
- drakconnect:
  o new drakconnect wizard:
    * remaining issues: isdn and zeroconf config, bewan modem, isapnp
      cards, X11 behavior on name change
    * provider database for modem and adsl connections
    * renewed steps
    * show device name rather than ethX
    * modem:
      + handle CHAP/PAP
      + enable to use dynamic ip/dns/gateway
    * adsl:
      + update for eagle package replacing adiusb
      + detect eci modems and explain why we cannot handle them
  o manage part: update (poulpy)
- draksound: fix unwriten sound aliases when configuring not yet
  configured cards (#6988)
- printerdrake: kill stupid userdrake dependancy (gc)
- ugtk2 / interactive layers:
  o make trees and lists take all availlable space
  o pack/align checkboxes to left
  o rework window sizing: size all windows and add a scrollbar for the
    whole window if needed (not just around advanced settings) (pixel)
- misc fixes for 2.6.x kernels (gc, pixel & planel)

* Tue Jan 20 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-22mdk
- drakboot: add a warning telling to run lilo after modifying
  lilo.conf (#6924)
- drakconnect: enhanced "manage" part (poulpy)
- drakfirewall: add icmp support and "Echo request (ping)" choice
  (pixel)
- drakgw: transparent proxy support (florin)
- more kernel 2.6.x support (pixel)
- fix subdialogs when embedded (#6899)

* Thu Jan 15 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-21mdk
- prevent spurious top windows to appears when embedded in mcc

* Thu Jan 15 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-20mdk
- diskdrake:
  o more lvm2 support (pixel / Luca Berra)
  o update partition reread on kernel side and rebooting if needed (pixel)
- drakboot:
  o boot loader config: do not complain on canceling
  o graphical boot theme config:
    * handle grub too (bootsplash being independant of boot loader)
    * fix layout when embedded
- drakconnect: update manage interfaces (poulpy)
- drakTermServ: first time wizard (stew)

* Wed Jan 14 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-19mdk
- diskdrake: updated lvm2 support (pixel)
- drakboot: boot theme configuration is back (warly)
- drakboot, drakclock, drakconnect, drakfloppy, drakfont, drakperm,
  draksec: sanitize buttons bar
- drakedm: fix dm list
- printerdrake: sort printer models list

* Mon Jan 12 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-18mdk
- drakedm: when offering to restart dm, offer yes/no as choice rather
  than ok/cancel (#6810)
- drakdisk: sanitize buttons when working on mount points (smb,
  webdav, ...)
- drakfloppy: handle both kernel 2.4.x and 2.6.x (before size field
  was not properly when switching between threes b/c we looked for
  module.ko instead of module.o.gz and the like)
- drakfont: renew GUI through subdialogs
- localedrake: update languages list (pablo)
- printerdrake: do not push anymore help menu at right

* Mon Jan 12 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-17mdk
- drakfirewall: allow a range of ports (anthill bug #267) (pixel)
- drakfont:
  o fix unstalling fonts
  o sanitize application options, about, font import and font removeal
    layouts
- fix behavior when embedded in interactive layer:
  o prevent subwindows being too small
  o prevent subwindows breaking when canceled
- run_program layer: don't print refs in log when output is redirected
  (blino)
- wizards layer: only complain if a problem actually happened
- drakconnect:
  o first snapshot of new manage wizard (poulpy)
  o "delete network interface" wizard:
    * show a finish button on last step
    * exit once delete interface wizard has ended instead of then
      running the std add wizard...
    * list ppp interfaces too

* Fri Jan  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-16mdk
- support newer gtk2 bindings
- fix drakboot --boot embedding
- fix logdrake wizard when embedded

* Fri Jan  9 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-15mdk
- alias scannerdrake => drakscanner
- drakauth: integrate chkauth (which is now deprecated) (pixel)
- drakbackup: (stew)
  o DVD+RW support,
  o fix bogus cron message
- drakboot:
  o split it into bootloader and autologin configuration
  o drop no more handled keytable line in grub config file  (pixel)
  o simplify lilo boot message. Not mentioning the timeout parameter
    (#5429)  (pixel)
  o remove /boot/grub/messages and don't use the i18n command which
    are obsolete since grub doesn't handle it anymore (pixel)
- drakconnect: fix sagem800 configuration (poulpy)
- drakdisk: basic lvm2 support (pixel)
- drakfloppy must not be in drakxtools-newt, must now require mkbootdisk
  (which is not installed by default anymore)
- drakperm: do not discard 0 when perms are 0xx like
- drakTermServ: support new etherboot floppy image syntax and file
  locations (stew)
- drakxservices: fix descriptions (#1704) (pixel)
- enable other packages to override libDrakx translations with those
  from their own domains
- handle /etc/modprobe.preload
- harddrake: detect megaraid controllers as scsi ones
- harddrake service:
  o for removable devices, we've to remove/add them one by one, so
    when several devices of the same class are removed/added, we ask
    if we should handle them several time.
  o let ask confirmation once per class instead (olivier blin, #6649)
  o do no ask several times the kernel to switch into verbose mode
    (olivier blin)
  o really display which devices were removed
- misc cleanups
- tool layout:
  o add a separator below buttons
  o really pack the two button sets at edges
  o try to have a better layout when embedded: let's have only one
    scrollbar that scroll the whole window

* Tue Dec 30 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 9.3-14mdk
- ugtk2.pm: fix ask_dir dialog (#6152)

* Mon Dec 22 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-13mdk
- do not show useless "ignore" button when requesting root password
  through kdesu
- drakperm: keep changes when switching view moed
- drakclock:
  o prevent one to open zillions of sub dialogs
  o reuse std dialogs
  o remove stock icons
- fix buttons layouts and text wrapping in in drakboot, drakfloppy and
  drakperm
- logdrake's mail alert wizard: 
  o properly handle faillure
  o accept local user names as well as emails
- printerdrake, harddrake2: push help menu at right
- scannerdrake: (till)
  o add upload firmware feature 
  o configure non-root access to parallel port scanners automatically.

* Tue Dec  9 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-12mdk
- net_monitor:
  o properly handle multiple interfaces (each one having its own pixmap)
  o make it fit when embedded
  o kill icons on button
  o kill profile managment (duplicated features already availlable
    within mcc)
- drakconnect:
  o split in multiples pieces
  o move profile support into mcc
  o fix writing spurious "WIRELESS_NWID=HASH(0x8e93758)" in ifcfg-<intf>
  o add "delete an interface" wizard
- draksound: handle new snd-bt87x driver 

* Fri Nov 28 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-11mdk
- improve buttons layout in interactive written tools
- drakconnect:
  o fix sagem configuration
  o do not silently ignore internal errors
- drakgw:
  o make --testing somewhat more useful
  o log more explanations
  o really support embedding
- wizards: do not show up anymore banners when embeeded

* Tue Nov 25 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-10mdk
- detect serial MGE ups
- drakconnect:
  o fix #5664: list ppp0 for modem and adsl connections too and ippp0
    too for isdn ones
  o fix #6184: read back "Connection Name" and "Domain Name" fields
    when configuring modem
  o fix adsl configuration steps that were hidden
  o configure all isdn cards, not only the first one
  o fix "kid exited -1" warnings
  o handle zaurus connected through USB cables resulting in usbnet
    driver creating usbX interfaces
- mousedrake: default to "PS/2|Automatic" for ps/2 mice (automagically
  use IMPS/2 when needed)
- XFdrake: misc fixes

* Wed Nov 19 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-9mdk
- resync serial_probe with kudzu
- fix some untranslated strings

* Mon Nov 17 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-8mdk
- rebuild for reupload

* Sat Nov 15 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-7mdk
- fix links

* Fri Nov 14 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-6mdk
- drakconnect: fix speedtouch start/stop scripts when firmware is
  already there or when firmware installation is canceled
- harddrake2: do not show module if unknow for system bridges since
  it's normal
- harddrake service: remove net aliases if needed
- move clock.pl from mcc into drakxtools package
- provide drakclock, drakdisk, drakhardware, drakkeyboard, draklocale,
  draklog, drakmouse, draknet_monitor, drakprinter, drakx11 new names
- XFdrake: choose a not-to-bad default when X auto config fails in
  auto install

* Sat Nov  8 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-5mdk
- drakconnect:
  o fix lan always marked as detected even when no detection was performed or
    when there's no ethernet devices
  o list acx100_pci as a wireless network cards driver so that one can
    set wireless parameters for it (#6312)
- harddrake2: 
  o do not display "unknown module" in red for modems known to not
    need any module (#3047)
  o enumerate cpus from 1 instead of 0 (#4704)
  o typo fix #6134: (JAZ drives are nothing to do with jazz music)

* Fri Nov  7 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-4mdk
- drakconnect:
  o mcc view: fix network interfaces list update (really remove from
    the Gtk+ list lost interfaces)
  o prevent droping wireless parameters for modules not listed in
    wireless modules list
  o more usb wireless detection fix

* Thu Nov  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-3mdk
- drakconnect:
  o fix wireless cards detection (#3690, #4181, #5143, #5814, ...)
  o always list sagem_dhcp in list, showing it only in expert mode is
    confusing
- drakconnect/localedrake: fix a few unstranslated strings

* Wed Nov  5 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-2mdk
- drakbackup: enable bz2 compression option (stew)
- drakconnect: detect again unconfigured network interfaces

* Tue Nov  4 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.3-1mdk
- overall misc cleanups
- diskdrake: check both nfs servers version 2 and version 3, and
  remove duplicates (bug #6055) (pixel)
- drakconnect:
  o fix going back in some places (isdn, ...)
  o fix #6159: fix detection when a local name server is faking the
    connection because of its cache by checking at least a packet is
    ack-ed
  o translate a few strings (part of #5670)
  o handle more than 4 ethernet cards
- drakconnect, drakfirewall, drakgw: show up a combo box with detected
  network interfaces (but still let the user manually type it sg like
  ppp0 if needed) instead of letting the user guessing the network
  interface
- drakfont: support getting fonts from samba (Salane KIng)
- harddrake:
  o show isdn & adsl adapters too (adsl adapters were previously
    classed as modems)
  o use drakconnect to configure modems
- drakfirewall: translate services names
- "mail alert" wizard from logdrake:
  o save options into /etc/sysconfig/mail_alert instead of hardcoding
    them in the cron task and restore them when configuring it again
  o ensure services are always listed in the same order
  o send the mail only if there's really sg to warn about (aka do not
    sent empty mails)
  o generate perl_checker compliant cron tasks
- translations: updates, breakages

* Tue Nov  4 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-19mdk
- drakboot: disable lun detections for ide burners
- drakconnect:
  o fix empty fields in expert mode
  o fix anthill bug #50: ensure /etc/ppp/pap-secrets is not world
    readable since it contains password/user mapping for dialup
- net_monitor: handle multiple network interfaces

* Mon Oct 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-18mdk
- drakconnect:
  o do not blacklist anymore bcm4400 for network hotplugging
  o support ISDN usb adapters
- drakperm:
  o force user|group|other rights order in edit dialog
  o one was able to alter system rules in memory wheareas this is not
    supported since they're enforced by msec.
    disable "ok" button for system rules to prevent confusion.
- harddrake service: workaround anthill bug #18 (do not overwrite sound
  aliases when no hardware change occured)
- misc amd64 fixes (gwenole)
- net_monitor:
  o fix connection status detection
  o fix profile managment switch

* Thu Oct 16 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-17mdk
- drakbackup: all users overrides individual selection in wizard
  (#5916) (stew)
- drakconnect:
  o fix #425, #1881: wireless adapters settings were lost when
    altering network configuration when not from wizard mode
  o when steping back in wizard, do not overwrite first card
    parameters with last one's (#3276)
  o fix expert mode (lost checkboxes states when "expert mode" option
    is checked)
  o blacklist bcm4400 for network hotplugging
- drakfont:
  o fix ttf conversion (#5088)
  o log more explanations
- draksec: fix unsaved security administrator setting (#6103)
- misc chinese fixes (arnaud, pablo)
- printerdrake: fix lpd call (pablo)
- translations updates (pablo)
- misc amd64 fixes (gwenole)

* Fri Sep 19 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-16mdk
- drakconnect: fix #5825 (hostname set as ARRAY(0x...))

* Thu Sep 18 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-15mdk
- drakboot: (pixel)
  o fix switching from grub to lilo
  o fix drakboot crashing once bootloader has been altered in text
    mode
- printerdrake: further fix cups configuration (till)
- update translations

* Wed Sep 17 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-14mdk
- printerdrake: fix cups configuration regarding commented out rules

* Wed Sep 17 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-13mdk
- diskdrake: (pixel)
  o fix writting wrong types in fstab
  o fix handling of mount points with underscoresb (#5728)
  o do not check current partition for already used mount point
- drakauth : fix NIS managment (#5668) (pixel)
- drakhelp: load online drakbug help (daouda)
- draksound: (#5403)
  o make sure to use OptionMenu instead of Combo boxes
  o move help into a tooltip
- upate translations

* Tue Sep 16 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-12mdk
- diskdrake: (pixel)
  o fix growing ext2/ext3 partitions
  o handle beos partitions with filesystem befs (#5523)
- drakbackup:
  o use hd as default daemon media (stew)
  o fix translation issues (Arpad Biro)
  o fix user cron misbehavior (Keld Jørn Simonsen)
- drakTermServ:
  o fix translation issues (Arpad Biro)
  o fix help text format (stew)
- drakboot: when "Back" is pressed, restore the list of entries in
  bootloader (#5680) (pixel)
- drakbug: add support for bug submission about stable releases into
  anthill (stew)
- drakconnect: (poulpy)
  o fix adsl support regarding ppoe.conf (#5674)
  o fix speedtouch (#5056)
- draksound:
  o do not overwrite current driver if it's a viable driver for the
    current sound card (#5488)
  o show the current driver too (being preselected) so that users do
    not get confused
- drakupdate_fstab: fix supermount handling (pixel)
- fix hidden or cutted buttons (#1919, #2364, #2705, #3667, ...)
- fix expert mode resulting in advanced setting being displayed by
  default but label still being "advanced" instead of "basic" (#4353)
- harddrake service: switch to verbose mode when using bootsplash
  (warly)
- localedrake: fix chinese input (#4408)
- printerdrake: (till)
  o fix LIDIL devices management
  o really handle PSC 1xxx and OfficeJet 4xxx
  o added support for user-mode-only HPOJ devices (HP PSC 1xxx and
    OfficeJet 4xxx) (#5641)
- standalone tools: speedup startup by invoking "rpm -qa" only once (fpons)
- XFdrake:
  o use 24bit for fglrx in automatic mode (fpons)
  o prevent lost Xauth access (pixel)
  o fix logout from gnome (pixel)
  o fix not translated test page (pixel)

* Thu Sep 11 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-11mdk
- drakboot: misc fixes (pixel, fpons)
- drakconnect:
  o do not set hostname if there's a dynamic interface
  o fix firmware loading (poulpy)
  o fix profiles with spaces in name (#5586)
- drakfont: fix faillure to install fonts (#5571)
- drakfirewall: make it work with dialup connexion (#4424) (florin)
- drakgw: fix canceling info steps (florin)
- harddrake2:
  o fix freeze while configuring modules (infamous #4136)
  o warn about no module parameters instead of not showing the dialog
- localedrake: configure kdmrc too (pixel)
- logdrake: always display the log domain names in the same order
- printerdrake: help making printerdrake icon bar be shorter (#5282)
- update wizard banners (davod beidebs)
- XFdrake: handle ati drivers (nplanel, fpons)

* Tue Sep  9 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-10mdk
- disdrake: fix userdrake not runnable (#5447) (pixel)
- drakboot:
  o fix too small kernels window width (#5040)
  o fix too big main window
- drakconnect:
  o when no profile is set, use default one (poulpy)
  o add support for sagem dhcp (francois)
- drakperm: do not complain about saving on view change
- drakxtv: install xawtv if needed (#5130)
- logdrake: fix infinite entries (#5448)
- printerdrake: fix options saving (#5423) (till)

* Mon Sep  8 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-9mdk
- drakfont: fix not being able to select directories (#4964)
- drakconnect:
  o fix profiles managment (poulpy & tv)
  o fix firmware loading (#5307, poulpy)
- fix net_monitor not working as root
- printerdrake:
  o use new help scheme (daouda)
  o reread database when switching between normal and expert mode
    (till)
- scannerdrake: complain if saned could not be installed
- XFdrake: use OptionMenu's rather than Combo's (more consistent gui
  and better behavior when embedded)

* Sun Sep  7 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-8mdk
- localedrake: configuration fixes (gc)
- drakgw: fix #2120 & #2405 (florin)
- drakconnect: (poulpy)
  o workaround messed up ppp0 configration
  o fix profiles

* Thu Sep  4 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-7mdk
- diskdrake: fix #5204 (pixel)
- drakbackup: fix untranslatable strings, ... (stew)
- drakconnect:
  o fix #5242: loop on winmodem connection if no windomem but winmodem
    is selected
  o offer to select modem device
- fix buildrequires for 64bits ports
- fix lsnetdrake on AMD64 (gwenole)

* Sun Aug 31 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-6mdk
 - drakboot: default parameters are those of the default target (pixel)
 - drakedm: in non expert mode, only display the list of *installed* display
   managers
 - drakfloppy, drakconnect: fix more dialogs height
 - fix requires

* Thu Aug 28 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-5mdk
- drakhelp: add support for contextual help (daouda)
- explanations are back (pixel)
- fix autologin for xdm (pixel)
- drakconnect:
  o fix dialogs height
  o fix #4372 (poulpy)
  o profiles are back
- printerdrake: new GUI (till)

* Wed Aug 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-4mdk
- drakconnect:
  o non wizard gui
    * fix hostname setting
    * set hostname at the same time we apply dns changes (on apply
      button press)
  o both wizard and non wizard modes: (poulpy)
    * fix #4363
    * fix speedtouch firmware file name
- drakxtv: resync with kernel's bttv
- printerdrake: misc fixes (till)

* Tue Aug 26 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-3mdk
- drakconnect (non wizard gui):
  o add --skip-wizard option to get into non wizard mode
  o hide profile in "internet config" dialog if profiles are disabled
  o "Configure hostname..." button: offer to configure DNS too
  o only allow to run one wizard at once
  o reload the configuration once the wizard exited
  o prevent one to do concurrent config changes from the gui while the
    wizard is run
  o only write conf & install packages on exit if something really has
    been altered so that we do not write the config twice if the
    "apply" button was already pressed

* Tue Aug 26 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-2mdk
- diskdrake: (pixel)
  o fix WebDAV configuration embedding (#4703)
  o use fs=ext2:vfat or fs=udf:iso9600 for supermount-ng
- printerdrake: misc fixes (till)
- service_harddrake: prevent depmod to be runned everytime
- XFdrake: more fixes for multilayout keyboards

* Mon Aug 25 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-1mdk
- drakfloppy: make it CJK aware
- drakTermServ: add /etc/modules for local hardware config (stew)
- fix #4579: drakconnect not working on console (poulpy)
- printerdrake: misc fixes (till)

* Sat Aug 23 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.35mdk
- drakperm:
  o add new rules at top
  o always display editable rules before non editable ones
  o disable up button when selected rule is the first one
  o disable down button when selected rule is the latest one or when
    next rule is non editable
  o fix moving up/down rules
  o fix no saving if we've sort rules

* Sat Aug 23 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.34mdk
- disdrake: explain why ntfs resizing had failled (pixel)
- drakbackup: (stew)
  o fix crash on file select of "Other" finish custom cron
    configuration
  o normal users can now do cron backups
- drakconnect:
  o fix no detection in expert mode
  o better firmware load from floppy managment (poulpy)
  o fix pppoa use for speedtouch USB (poulpy)
- drakfirewall: add samba in services list
- drakperm: make security level menu be more understandable & usuable
- draksec: translate default value in help tooltips too
- fix CJK wrapping in more places (#3670 and the like)
- make interactive button order be the same as gtk dialogs one and our
  dialogs but only in standalone mode
- misc fixes from pixel

* Thu Aug 21 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.33mdk
- fix CJK wrapping in interactive tools (#4642)
- remove ugly border around standalone tools
- wizards: increase height to prevent some hidden or cutted buttons
- diskdrake: fix small unallocated area at the end of the drive
  (pixel)
- drakconnect: (poulpy)
  o allow user to copy firmware from a floppy
  o fix another back step
  o fix wrong url
- drakxtv: only offer to configure xawtv if bttv was configured
- XFdrake: fix #3976 (francois)
- update keyboards list & translations (pablo)

* Tue Aug 19 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.32mdk
- pci hardware discovery: do full-probe by default
- show advanced options by default if --expert was passed or if expect
  checkbox was checked (#4353)
- drakconnect: fix internet reconnection (poulpy)

* Tue Aug 19 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.31mdk
- drakbackup: user definable crontab entry (stew)

- drakconnect:
  o fix up/down interface detection (poulpy)
  o fix some more previous buttons in drakconnect wizard mode
  o fix crash on interface enabling/disabling
  o fix lan changes (#4088)

- drakfloppy:
  o fix long-standing broken mkbootdisk call bug
  o sort modules and directories in treeview
  o save the options & modules list on exit and them restore it on
    load
  o try to be more user friendly:
    * if no error, display a success message, then exit
    * on error, instead of displaying the raw exit code that has no
      meaning for the end user, display in red the log message of mkbootdisk
    * remove insane expert button and so called expert frame

- drakpxe: match new pxe dhcp.conf configuration file (francois)

- harddrake2:
  o display the right fields description when no device is selected
  o make dialogs be modals and transcient

- diskdrake: (pixel)
  o fix lvm managment(#4239)
  o fix underscores being underlines (#4678)
  o fix interaction with mcc

- fix misc issues with shadow passwords and package managment
  (francois/pixel)
* Sun Aug 17 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.2-0.30mdk

- drakconnect mcc: 
  - allow hostname change
  - dhcp to static fixes

* Tue Aug 12 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 9.2-0.29mdk
- drakconnect: fix message (#4564)
- drakbackup: (stew)
  o fix #4381
  o search for files to restore
  o fix looping in catalog restore
  o gui enhancements (fabrice facorat)
  o deal with users that are deleted from the system (#4541)
- drakxtools depends on gurpmi
- lot of misc bug fixes

* Thu Aug  7 2003 Pixel <pixel@mandrakesoft.com> 9.2-0.28mdk
- drakxservices: xinetd services have a special treatment
- localedrake: fix the "zh_TW with country China" case
- no more stock icons 

* Mon Aug  4 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 9.2-0.27mdk
- ugtk2.pm:
  - revert "use checkboxes instead of icons"
  - fix not possible to select with mouse anymore (rpmdrake etc)

* Mon Aug  4 2003 Pixel <pixel@mandrakesoft.com> 9.2-0.26mdk
- various fixes
- clean tarball with no Makefile_c (thanks to Christiaan Welvaart)

* Sat Aug  2 2003 Pixel <pixel@mandrakesoft.com> 9.2-0.25mdk
- drakauth first appearance
- diskdrake --nfs and --smb:
  o instead of removing the "Search servers" button when the search is over,
    keep it to allow searching for new servers
    (the label is changed from "Search servers" to "Search new servers") (bug #4297)
- XFdrake
  o use something like """Virtual 1280 960""" instead of """Modes "1280x960" "1024x768" "800x600" "640x480""""
  o fix test dialog box
- drakbackup (various changes)
- drakboot
  o allow to choose /dev/fd0 for the boot device
  
* Thu Jul 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.24mdk
- drakbug:
  o use option menus instead of combos
  o use std button layout
- drakconnect:
  o double click on ethernet interface list lines run lan config
    dialog
  o remove nonsense expert button
- drakperm: fix crash on adding new permission
- harddrake: fix #4258
- mousedrake: use std button layout
- ugtk2:
  o add infrastucture for rpmlint toggle (semi-selected state mis-functionnal)
  o restore mouse selection

* Thu Jul 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.23mdk
- drakperm:
  o main window:
    * "ok" button should exit after having saved the preferences
    * localize levels in option menu
  o preferences dialog :
    * fix preferences saving on  exit
    * fix tips
- draksec:
  o restore help for msec checks
  o enhanced help in tooltips

* Thu Jul 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.22mdk
- drakautoinst, drakper, draksound, and many other tools: use option
  menus instead of combo boxes when the user is selecting from a fixed
  set of options
- drakboot: hide non working splash stuff
- drakperm:
  o sanitize gui (upcased labels, understandable labels, ...)
  o settings dialog:
    * localize all fields
    * add tips for all check boxes
    * use std button layout
    * use stock icons
  o rules toolbar: use stock icons
- net_monitor: fix crash on profile change due to netconnect api
  change

* Wed Jul 23 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.21mdk
- drakbackup: misc fixes (stew)
- drakboot: directly configure gdm & kdm
- drakconnect: fix #4050
- drakfont: fix #1679 & #3673
- drakgw:
  o fix not being able to step backward
  o fix canceling resulting in broken dhcp config
  o make --testing option being usefull
- drakhelp: fix no help for de/it/ru locales (daouda)

* Tue Jul 22 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.20mdk
- drakconnect: fix "lan config" dialog where fields were not filled
- draksec: vertically align OptionMenus

* Mon Jul 21 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.19mdk
- diskdrake, drakconnect: add an help button in standalone mode
- draksec
  o describe all security levels
  o make it clear that security admin is not a security level
  o colorize security levels names
  o do not offer to set syadmin when reports are disabled
  o fix infamous "when embedded draksec can be enlarged but never shrink back"
  o make 1st tab title somewhat clearer
- harddrake2: workaround buggy gtk+-2.x that do not enable wrapping textviews when
  realized
- renew drakconnect wizard gui (2/x):
  o make previous button always be availlable when configuring lan
  o keep user changes when going back to main connection types menu
  o do not loop if one refuse to save changes, just skip the save step
  o fix final success message
  o really translate type connection to be translated
  o try to get more space on screen
  o dhcp host name cannot be set if one want to get it from dhcp server

* Sat Jul 19 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.18mdk
- draksec:
  o sort functions & checks when writing configuration
  o really fix config load

* Fri Jul 18 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.17mdk
- draksec:
  o fix preferences loading & saving
  o sort again functions & checks

* Thu Jul 17 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.16mdk
- do not exit the whole application when one destroy a dialog
- drop gtk+1 requires
- renew drakconnect gui (1/x):
  o embedded mode:
    * remove ugly icon
    * fix internet gateway buttons layout
    * smaller dialogs
    * correctly align fields in "lan configuration" dialog
    * run wizard in background (no more main window freeze until
      wizard exit)
  o wizard mode:
    * proxy configuration step: do not go back two steps back on
      "previous" click, but only one back
    * properly use checkboxes (do not put extra labels before when
      checkbox's label is empty)
- wizard mode:
  o stock items in wizards for previous/next
  o do not force permanent center of wizard windows, which is not
    user-friendly
  o always use s/TextView/Label/ 

* Tue Jul 15 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.15mdk
- drakbackup, drakperm: fix button layout
- drakboot, drakfloppy: use option menus rather than non editable
  combo
- drakboot:
  o grey theme config instead of hiding it
  o describe user and desktop lists
- drakfloppy: grey remove button if no module to remove in modules
  list
- draksec: wrap labels
- fix interactive apps on X11 (eg diskdrake)
- fix error and warning dialogs
- logdrake: ensure we got a valied email in "email alert"
- printerdrake: make printerdrake runable
- xfdrake: make it use stock items too

* Mon Jul 14 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.14mdk
- drakboot: fix /etc/lilo.conf generation when reading grub config by setting
  valid "boot=" parameter
- drakconnect, drakfloppy: make checkboxes out of ugly "expert <-> normal modes"
  buttons (saner gui)
- drakconnect:
  o kill duplicated code, share it with drakfloppy and others
  o renew GUI:
    * make sub windows be modal, centered on parent and trancient dialogs
      instead of toplevel windows
    * fix "Internet connection configuration" dialog
    * fix layout of main window:
      + pack together expert mode toggle and wizard button
      + merge wizard label and button
- drakfloppy:
  o fix warning on menu building
  o fix module browsing after gtk2-perl-xs switch
  o support new 2.5.x kernels' kbuild
  o fix old brown paper bug (mdk8.2/9.0 :-() not passing extra selected modules
    to mkinitrd
  o fix unable to pick a module again after having removed it from selection
  o renew GUI:
    * window with enabled expert options is too big when embedded: let's move
      expert options into a sub dialog
    * use stock dialogs
- draksec:
  o translate msec options' default values
  o display descriptions rather than raw function names
- drakTermserv: fix entry filling
- logdrake: fix crash when called from net_monitor
- net_monitor: switch from gtk+-1.2.x to gtk+-2.2.x (fix #3998 btw)
- sanitize guis, especially button layouts:
  o use std layout (ButtonBoxes) for buttons everywhere
  o use stock items everywhere
  o let interactive apps using stock items on x11 and old drak translated items
    in other backends
  o pack buttons always in the same order and places
  o use OptionMenu instead of Combo Boxes when the user is selecting from a
    fixed set of options

* Thu Jul 10 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.13mdk
- drakfloppy: one cannot edit output buffer
- drakperm: fix crash when moving lines around sorted columns
- draksec: more stock icons
- logdrake: fixes

* Thu Jul 10 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.12mdk
- drakboot, drakfont: use stock button
- drakconnect, drakfloppy: grey widgest instead of hiding them when
  not in expert mode
- drakconnect, draksec: fix crash
- drakbackup: misc fixes (stew)

* Wed Jul  9 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.11mdk
- more work on new perl binding for gtk+-2, especially for drakbug and
  rpmdrake

* Wed Jul  9 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.10mdk
- switch from gtk2-perl to gtk2-perl-xs
- a few more stock items

* Sun Jul  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.9mdk
- increase gui coherency of drakxtools vs other gtk+ apps: use stock icons
- drakbackup: (stew)
  o show units for hard-drive allocation
  o add "View Configuration" 1st screen.
  o honor user defined limits for backup disk consumption
  o log last backup and to enable view last backup log
  o fix gui crash on restore. (Keld Jorn Simonsen/Cooker list)
- drakconnect, drakfloppy, drakperm: let columns be sortable
- drakconnect (isdn): virtual interface ippp0 is started at boot
  (dam's)
- harddrake2: colorize help
- keyboard managment: added various new keyboard layouts (pablo)

* Tue Jul  1 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.8mdk
- drakbackup: try to better fit gui when embedded (fix #4111) (stew)
- drakTermServ: enable local client hardware configuration (stew)
- harddrake2: let gui behave better when embedded
- ugtk2: locales setting fix for rpmdrake (gc)

* Tue Jun 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.7mdk
- drakboot: more work on grub conf reread
- drakedm: fix crash on service restart
- drakfont: fix crash when trying to remove empty font list (#1944)

* Tue Jun 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.6mdk
- autoinstall: (pixel)
  o fix regarding LVMs
  o support encrypted partitions
- draconnect: misc fixes (poulpy)
- drakboot: reread grub config file if grub is the current boot loader
  (#3965)
- diskdrake: fix for nfs mount points (pixel)
- drakgw: reread current network conf (florin) (#468)
- i18n fixes (#3647 and co)
- mousedrake: add mouse test in non-embedded mode (#2049) (gc)

* Tue May 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.5mdk
- keyboardrake: resync with XFree86-4.3 (pablo)

* Tue May 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.4mdk
- drakconnect: fix #3628 (ensure 644 perms on /etc/resolv.conf)

* Wed May 21 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.3mdk
- drakbackup: fixes regarding file names in differntial mode (stew)
- drakboot, drakconnect, harddrake2, printerdrake: misc cleaning
- drakconnect:
  o workaround #3341 (display "Bad ip" instead of a blank field if we
    failled to parse the ip)
  o fix #853 (check ip) (poulpy)
- printerdrake: fix #1342 (english rephrasing)
- requires: fix #3485

* Tue May 20 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.2mdk
- printerdrake: misc bug fixes
- drakconnect: fix #763, #2336 (ethX aliases on network card changes)
  (poulpy)

* Tue May 20 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.2-0.1mdk
- drakconnect: fix #2530 (extraneous vindow on wizard error) (poulpy)
- drakedm: fix #1743 (offer to restart the dm service)
- drakfont: fix #3960 (divide by zero execption)
- draksec: fix #3616 (draksec discarding changes)
- my_gtk: fix #3952 (non working drakcronat)

* Fri May 16 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-38mdk
- drakboot:
  o do not install both lilo and grub when grub is choosen
  o further fix #2826: replace spaces by underscores in labels
  o further fix #3560: update main bootloader label after the
    bootloader switch
  o raise a wait message window so that the user can figure out what
    occurs (lilo installation being quite long)
- harddrake: localize drive capabilites (aka burning, dvd managment, ...)
- drakconnect: fix #852: add a step to warn user before writing
  settings (poulpy)

* Thu May 15 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-37mdk
- drakfont: fix #1352 (do not add font directory with dummy messages)
- harddrake2: fix #3487 (invalid charset in help windows)
- drakconnect: fix "isdn modem choice step is skipped" bug (poulpy)

* Mon May 12 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-36mdk
- drakboot:
  o do not loop on console (part of #3560) (pixel)
  o do not log localized messages
  o if the bootsplash is missing, just go back to main config window

* Wed Apr 30 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-35mdk
- draksec: fix #3618 (let one pick any security level)
- harddrake service: display all removed devices

* Tue Apr 29 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-34mdk
- drakedm: fix #3701 (return back to the display managers menu if one
  cancel the installation of the required packages)
- drakfont: empty the font queue when step back (poulpy)

* Thu Apr 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-33mdk
- fix provides

* Wed Apr 23 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-32mdk
- translation snapshot

* Mon Apr  7 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-31mdk
- harddrake gui: fix menu entry description
- drakbtoot: fix #2826 (aka crash when one enter space in lilo label)
- ugtk2: fix #3633
- drakconnect:
  o fix #1675: swap the text and button widgets
  o typo fix (dam's)
- new perl_checker compliance (pixel)
- xfdrake: better keyboard managment (pixel)
- update translations (pablo)
- build fix for 64bits arch (gwenole)

* Fri Apr  4 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-30mdk
- fix drakfloppy crash on boot floppy creation
- ugtk2.pm: fix slight pb with gtktext_insert (#3633) (gc)

* Fri Mar 28 2003 Pixel <pixel@mandrakesoft.com> 9.1-29mdk
- use ServerFlags DontVTSwitch for i845, i865 and i85x

* Mon Mar 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-28mdk
- drakconnect: add support for ltpmodem

* Fri Mar 21 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-27mdk
- harddrake service: increase default timeout from 5 to 25 seconds

* Sun Mar 16 2003 Warly <warly@mandrakesoft.com> 9.1-26mdk
- do a correct cvs up of all gi before (me sux)

* Sat Mar 15 2003 Warly <warly@mandrakesoft.com> 9.1-25mdk
- fix drakperm fatal error in editable mode

* Fri Mar 14 2003 Pixel <pixel@mandrakesoft.com> 9.1-24mdk
- fix XFdrake handling NVidia proprietary drivers

* Thu Mar 13 2003 Till Kamppeter <till@mandrakesoft.com> 9.1-23mdk
- printerdrake: Fixed bug #417: '$' character in printer URI was not
  correctly handled.
- Desktop group simplification (francois).
- Translation updates (pablo, fabian).

* Thu Mar 13 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-22mdk
- drakboot/drakx: fix #3161 (ensure right permissions on
  /etc/sysconfig/autologin for bad root umask case)
- enable smooth sound configuration update from mdk9.0 (new unified
  via sound driver) and from mdk8.x
- scannerdrake detection fixes (till)
- drakTermServ: Fix IP pool range (stew)

* Wed Mar 12 2003 Pixel <pixel@mandrakesoft.com> 9.1-21mdk
- diskdrake: have a default mount point for newly added removables
- drakupdate_fstab: allow --del to remove fd0 & fd1

* Wed Mar 12 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-20mdk
- drakedm: install dm if needed
- harddrake service: handle multiple remvable devices in the same hw
  class (eg: 2+ cd burners or 2+ dvd drives or 2 floppies, ...)
- drakgw: really use the chosen net_connect interface (florin)
- drakbackup: gtk2 port fixes (stew)
- drakboot: fix #3048 (pixel)

* Tue Mar 11 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-19mdk
- ugtk2: fix still seldom happening #1445 (clicking two times too
  fast) (gc)
- drakxservices: fix embedding and packing in standalone mode (tv)
- localedrake: add menu entry (fix #1461) (tv)
- draksec: fix wait messages displaying (label was not displayed) in
  both standalone and embedded modes (tv)
- printerdrake fixes (till)
- translation updates

* Fri Mar  7 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 9.1-18mdk
- ugtk2.pm: fix rpmdrake dumping core when multiple searchs in some
  sorting modes (#2899)
- network/adsl.pm: one small logical fix (fpons)

* Thu Mar  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-17mdk
- draksplash:
  o fix #1766
  o do not crash when browsing (#1947)
  o do not crash on color selection
- avoid virtual ethX to be reconfigured by drakconnect (francois)

* Thu Mar  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-16mdk
- draksound: fix #1929
- moved code of XFdrake NVIDIA support to generic in standalone. (francois)

* Thu Mar  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-15mdk
- fix infamous #2672
- let draksec fit in 800x600
- harddrake: fix detection of mod_quickcam's webcams
- scannerdrake: do not detect mod_quickcam's webcams as scanners
- logdrake:
  o do not update the text buffer when filling it
  o show the wait message also when searching while embedded (else the
    user will be confused and will wonder why logdrake is freezed
- fix drakwizard ("next" button being packed too far) (pixel)

* Wed Mar  5 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 9.1-14mdk
- localedrake: fix behaviour when only one lang is available (clicking
  on "cancel" on the country selection didn't cancel it)
- drakconnect: fixes in isdn configuration (flepied)
- drakperm (tv):
  o fix #1776
  o fix small memory leak (tree iterators)
  o restore edit dialog on doble click
- logdrake: restore "pre gtk+-2 port" search  behavior (tv)
  o empty log buffer on search startup
  o freeze buffer while searching
  o scroll down the log buffer on filling
- localedrake: don't categorize langs, for better looking (since
  most people will have very few of them) (gc)
- fixed wizard mode not taken into account for drakconnect in
  drakconf. (francois)
- fixed expert mode in drakconnect for dhcp for cleaning
  variables. (francois)
- fixed not to use invalid ethX. (francois)

* Mon Mar  3 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-13mdk
- drakboot: fix #2091, #2480

* Mon Mar  3 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-12mdk
- drakperm: fix rules saving
- printerdrake: various fixes (till)

* Fri Feb 28 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 9.1-11mdk
- drakconnect is no more supporting profiles. (francois)
- drakconnect support for sagem Fast 800 used by free.fr (francois)
- drakconnect support for ltmodem. (francois)
 
* Thu Feb 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-10mdk
- harddrake service: 
  o offer to configure cdrom/dvd/burners/floppies/
    and the like mount points
  o configure firewire controllers
- diskdrake fixes (pixel)
- drakconnect fixes (francois)

* Thu Feb 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-9mdk
- drakconnect: 
  o fix lan configuration window filling
  o fix net configuration window sizing
- drakperm: make it fit better in both embedded and non embedded modes
- drakgw: fix embedding
- logdrake: fix scrolling for embedded explanations
- mousedrake: fix embedding  (gc)

* Thu Feb 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-8mdk
- drakfloppy gtk+2 port
- drakboot:
  o cleanups
  o disable autologin settings when autologin is disabled
  o make embedded app look better
- harddrake2: 
  o fix #1858 (usb adsl speed touch modem misdetection)
  o provides "options" and "help" pull down menu when embedded
  o detect firewire controllers
- drakedm: strip empty lines
- lot of network fixes (francois)
- drakbackup gtk+2 port fixes: #1753, #1754, #1933, #2159 (stew)

* Tue Feb 25 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-7mdk
- drakfloppy: 
  o fix #1761
  o only list physically present floppies
- harddrake gui:
  o better support for zip devices
  o removable devices cleanups
  o display dvd/burning capacities
- harddrake service:
  o do not flash the screen if nothing has to be configured
  o removable devices cleanups
- fix #1802 (pixel)

* Mon Feb 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-6mdk
- fix logdrake's mail alerts (services alert, don't crash)
- drakperm: fix #1771, non editable combo1
- drakfloppy: fix #1760
- drakxservices: fix #502

* Mon Feb 24 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-5mdk
- clean up tools embeddeding in the mcc
  o make it hard to freeze the mcc
  o make tools loo better when embedded (no embedded wait messages,
    ...)
- harddrake2:
  o add "/dev" to devfs paths
  o do not offer to configure module when there's no module or when
    driver is an url or a graphic server
  o fix embedding

* Fri Feb 21 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-4mdk
- drakconnect fixes

* Thu Feb 20 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-3mdk
- drakboot: fix #1922
- drakgw, drakboot: remove gtk+ warnings
- harddrake2: fix latest l10n bugs
- disdkrake fixes (pixel)
- drakconnect: dhcp fix (poulpy)
- printerdrake fix (pixel)

* Thu Feb 20 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-2mdk
- logdrake: fix #1829
- translation updates
- scannerdrake:fix embedding
- drakxtv: workaround a drakx bug which don't always add bttv to
  /etc/modules (fix #)
- printerdrake:
  o fix embedding
  o hide the icon when embedded to get more space
  o various improvements (till)
- drakfont: fc-cache enhancement (pablo)
- drakTermServ: fix #1774, #1775 (stew)
- newt bindind: better trees managment on console (pixel)
- diskdrake fixes (pixel)
- xfdrake: log failure sources (pixel)

* Tue Feb 18 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-1mdk
- fix "nothing to edit" in drakperm (#1769)
- fix draksec help
- drakedm: fix badly generated config file by 3rd party progs
- i18n fixes (pablo, gc)
- scannerdrake updates (till)
- diskdrake fixes: raid, ... (pixel)
- printerdrake fixes (till)
- drakconnect fix (poulpy)

* Mon Feb 17 2003 Till Kamppeter <till@mandrakesoft.com> 9.1-0.34mdk
- Fixed automatic print queue generation for HP DeskJet 990C.

* Mon Feb 17 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.33mdk
- fix wizard mode (pixel)

* Mon Feb 17 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.32mdk
- harddrake: fix #1718
- translation snapshot

* Sun Feb 16 2003 Till Kamppeter <till@mandrakesoft.com> 9.1-0.31mdk
- Various fixes/improvements on printerdrake:
  o Restructured function "main()"
  o Auto-generation of print queues during installation
  o Support for unknown printers in auto-detection and auto-generation of
    print queues
  o Fixed display of printer help pages
  o Fixed determination of default printer

* Fri Feb 14 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-0.30mdk
- drakperm fixes
- drakfont fixes

* Thu Feb 13 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.29mdk
- fix gc breakage

* Thu Feb 13 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.28mdk
- vastly improved scannerdrake (till):
  o fixed scsi/usb/parrallel scanners detection
  o new known scanners
  o support scanners with multiple ports 
  o better configuration files
  o fix "SnapScan" <-> "snapscan" bug
  o fix "HP scanners had no manufacturer field"
- drakxservices fixes (pixel)

* Wed Feb 12 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.27mdk
- fix embedded drakconnect: 
  o no crash on expert "configure" buttons
  o better behaviour when buttons are hidden/showx
- harddrake/draksound: card list update
- pixel:
  o diskdrake: 
    * discrimate hpfs and ntfs
    * more precise message when formatting / fsck'ing / mounting
      partitions
    * hide passwords for smb mount points
  o XFdrake: fix #707
- drakperm: first gtk+2 port fixes, still more to come (pouly & me)
- fix drakbug help (daouda)
- drakconnect fixes (frederic lepied)
- updated translations (pablo)

* Fri Feb  7 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-0.26mdk
- drakconnect : dhcp & zeroconf fixes
- drakfont : full Gtk2

* Thu Feb  6 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-0.25mdk
- drakconnect fixes

* Thu Feb  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.24mdk
- fix drakfloppy
- diskdrake: s/fat/windows/ because of ntfs
- poulpy:
  o drakfont updates
  o drakconnect fixes
- translation updates (pablo & co)
- add drakedm to choose display manager
- drakhelp: install help on demand (deush)
- harddrake2: fix for rtl languages

* Wed Feb  5 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.23mdk
- draksec cleanups
- fix harddrake2 embedding in mcc
- update translations (pablo)

* Tue Feb  4 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.22mdk
- add support for adiusbadsl 1.0.2 (fponsinet)
- faster draksec shutdown

* Mon Feb  3 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.21mdk
- draksec:
  o gui look nicer
  o add help for check cron 
  o fix "first notebook page do not show up"
  o do not be listed in drakxtools-http
  o faster startup
- sanitize draxktools-http service script
- diskdrake: ntfs resizing bug fixes (pixel)

* Fri Jan 31 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-0.20mdk
- drakconnect: add more zeroconf support

* Thu Jan 30 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.19mdk
- printerdrake: fixes for new foomatic
- requires a recent enought perl-GTK2
- harddrake2:
  o fix misdetection of nvnet part of nvforce2 chips
  o move nforce system controllers in bridge class (which is renamed
    "bridges and system controllers")
  o mark class names as being translatable
- logdrake works again in both embedded and non embedded cases
- translation updates, add Tajiki (pablo)
- interactive: add support for trees on console (pixel)
- diskdrake: ntfs resizing support (pixel) (acked by ntfsresize author)

* Wed Jan 29 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.18mdk
- fix locales managment for non interactive tools (aka pure gtk+ tools)
- harddrake2:
  o restore cd/dvd burners detection
  o fix doble detection of pci modems
  o don't display vendor & description when we don't have them for ata disks
  o fix ghost modem detection
  o logdrake is embeddable again

* Tue Jan 28 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.17mdk
- drakfont updates (poulpy):
  o fix progress bar,
  o about box,
  o ugly border when embedded.
- printerdrake: various fixes for local printer (till)
- small fix in drakgw (florin)

* Mon Jan 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.16mdk
- fix wait messages (gc)
- vietnamese translation update

* Mon Jan 27 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.15mdk
- diskdrake:
  o make sub window be modal
  o fix text mode (pixel)
- drakconnect: 
  o don't log actions not done
  o fix modem detection (poulpy)
  o cleanups (poulpy, pixel)
- draksound: remove last source of "unlisted driver" because of hand
  edited /etc/modules.conf
- drakxtv: add test mode
- fix encoding conversions for non latin1 (gc)
- harddrake2:
  o use new help system
  o make sub window be modal
  o configure sound slots on bootstrapping
- logdrake:
  o don't display "wait while parsing" window when embedded in mcc
  o log all drakx tools (not only the first one)
- mousedrake: cleanups (pixel, gc)
- printerdrake: updates for new foomatic (till)
- requires old perl-gtk for drakfloppy and net_monitor which works
  again
- translation updates (pablo)
- xfdrake: various fixes (pixel)

* Fri Jan 24 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-0.14mdk
- drakconnect :
  o get back serial modem detection

* Thu Jan 23 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.13mdk
- fix standalone apps error on --help
- many enhancements to draksound:
  o no more unlisted message
  o "how to debug sound problem" window
  o offer to pick any driver if no detected sound card (for eg isa
    card owners) or if no alternative driver 
  o handle proprietary drivers
  o fix unchrooted chkconfig call
- draksec: display help in tooltips
- drakconnect :
  o cleaning (poulpy, me)
  o zeroconf support (poulpy)
- big interactive cleanup for drakx and focus handling (pixel)
- boot floppy fixes (pixel)
- diskdrake: don't display twice the same mount point (pixel)
- keyboardrake:
  o cleanups (pixel)
  o update supported keyboard layouts ... (pablo)
- xfdrake: (pixel)
  o cleanups
  o don't use anymore qiv to render background while testing X config
- add drakpxe (francois)
- printerdrake:
  o updates (till)
  o fix chrooted services (me)
- translation updates (many people)
- mousedrake: fix scrolling test (gc)
- ugtk2: fix some (small) memory leaks (gc)
- ppc updates (stew)
- english sentences proofreading (pablo, stew)
- fix gtk+-2 port of mousedrake (me), 

* Fri Jan 17 2003 Damien Chaumette <dchaumette@mandrakesoft.com> 9.1-0.12mdk
- drakconnect : 
  o little dhcp behavior rework
  o fix /etc/hosts localdomain
 
* Thu Jan 16 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.11mdk
- snapshot

* Thu Jan 09 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.10mdk
- draksound : fix and update driver list
- printerdrake: fix staroffice/ooffice configuration (till)

* Tue Jan 07 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.9mdk
- fix wizards

* Tue Jan  7 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.8mdk
- update french translation
- harddrake: treat usb hubs as usb controllers
- logdrake: set it non editable
- printerdrake:
  o simplify gimp-print configuration 
  o let it work
- various cleanups (pixel)
- standalone tools: first help system bits (deush)

* Mon Jan  6 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.7mdk
- printerdrake fixes

* Thu Jan  2 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.6mdk
- embedding fixes
- wizard fixes
- fix permissions setting
- internals cleanups
- drakconnect & printerdrake fixes
- gtk+-2 fixes
- faster xfdrake startup
- translations update
- fix redefinition warnings

* Mon Dec 30 2002 Stefan van der Eijk <stefan@eijk.nu> 9.1-0.5mdk
- BuildRequires: perl-MDK-Common-devel

* Thu Dec 19 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.4mdk
- gtk+2 snapshot

* Wed Dec 04 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.3mdk
- snapshot for mcc

* Mon Nov 18 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.2mdk
- more printerdrake redesign
- more perl_checker fixes
- standalone : provide a common cli options/help manager
- logdrake : use my_gtk to transparently handle embedding and ease future gtk2 port
- kill dead code

* Fri Nov 15 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 9.1-0.1mdk
- bump version
- add missing printer/ directory
- typo fix in drakxtv

* Thu Nov 14 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.12-1mdk
- printerdrake cleanups
- various perl lifting
- harddrake:
  o display floppy driver type as well as mouse type & network printer port
  o fix vendor/model spliting for eide disks when there's neither
    space nor separator
  o v4l card lists : resync with latest bttv & saa7134 drivers

* Mon Nov 11 2002 Pixel <pixel@mandrakesoft.com> 1.1.11-3mdk
- bug fix (most drakxtools)

* Sun Nov 10 2002 Pixel <pixel@mandrakesoft.com> 1.1.11-2mdk
- bug fix (printerdrake, netconnect)

* Thu Nov  7 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.11-1mdk
- harddrake:
  o only display "selected" fields, skip other (aka only display
    fields we described)
  o print name and value of skipped fields on console
  o only display help topics related to currently displayed fields in
    right "information" frame
  o if no device selected, display a message explaining the help dialog
  o don't display modem when there're none
  o describe most cpu fields
  o simplify the coloring logic

- detect_devices :
  o getModem() : simplify
  o getCPUs() : fix cpu fields parsing

* Wed Nov  6 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.10-4mdk
- s/_(/N(/

* Tue Nov 05 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.10-3mdk
- rebuild for newt

* Mon Nov  4 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.10-2mdk
- snapshot

* Wed Oct 16 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.10-1mdk
- harddrake :
  o try to discriminate webcams from video cards
  o fix not displayed unknow devices
- detection engin :
  o update eide vendors list
  o detect cpus
  o adsl work (damien)
- drakbug:
  o make ui faster
  o fix displayed result when the package isn't installed
- drakTermServ : fixes (stew)
- smb updates (stew)
- fix broken danish translations (wrong unicode encoding) (pablo)
- update other translations by the way (pablo)

* Fri Sep 20 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-53mdk
- remove useless warnings from harddrake

* Fri Sep 20 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-52mdk
- fix draksec

* Fri Sep 20 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-51mdk
- printerdrake: various fixes (till)
- drabug:
  o fix spurious '1' file creation
  o don't print error messages when a program isn't found

* Tue Sep 17 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-50mdk
- draksec:
  o add ignore option to pull-down list
  o remove not anymore used libsafe option
  o save items
  o reread already set item

* Tue Sep 17 2002 Warly <warly@mandrakesoft.com> 1.1.9-49mdk
- printerdrake fix for webfetch

* Mon Sep 16 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-48mdk
- fix die wizcancel in non wizard mode (dams sucks?)

* Sat Sep 14 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-47mdk
- fix printerdrake network scanning for printers/print servers hangs
  on with firewalled machines (till)
- fix printerdrake curl dependancy break urpmi (till)
- obsoletes drakfloppy (daouda)

* Thu Sep 12 2002 Damien Chaumette <dchaumette@mandrakesoft.com> 1.1.9-46mdk
- fix broken net_monitor

* Thu Sep 12 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-45mdk
- try to fix drakgw & drakfirewall thx to pixel and florin
- fix drakfloppy and logdrake (tv)

* Wed Sep 11 2002 Damien Chaumette <dchaumette@mandrakesoft.com> 1.1.9-44mdk
- drakconnect :
  o fix RTC, ISDN detection
  o fix pcmcia cards detection / module list
  o check DNS and Gateway IPs

* Mon Sep  9 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-43mdk
- move back draksec to drakxtools
- harddrake:
  o don't pollute sbin namespace with one shot scripts
  o add run wrapper script for harddrake service
  o disable ?dm part
- draksound:
  o really display default driver
  o wait message while switching
- update translations

* Sat Sep  7 2002 Daouda LO <daouda@mandrakesoft.com> 1.1.9-42mdk
- cvs up before packaging (fix messy drakboot conf). 

* Fri Sep  6 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-41mdk
- fix harddrake service, run non essential checks after dm start

* Fri Sep  6 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-40mdk
- harddrake:
  o fix usb mouse detection
  o list --test in -h|--help
  o enhanced draksound :
    * blacklist cs46xx and cs4281 drivers : we won't unload these
      drivers since they're know to oopses the kernel but just warn
      the user
    * chroot aware - can be used in drakx
    * workaround alsaconf's aliases
    * add an help button that describe ALSA and OSS
    * display current driver, its type (OSS or ALSA), and the default
      driver for the card
    * if there's no (usb|pci) sound card, print a note about sndconfig
      for isa pnp cards

* Fri Sep 06 2002 David BAUDENS <baudens@mandrakesoft.com> 1.1.9-39mdk
- Re-add old obsolete Aurora's images needed by drakboot (this is stupid)

* Fri Sep 06 2002 David BAUDENS <baudens@mandrakesoft.com> 1.1.9-38mdk
- Update mdk_logo.png
- Update drakbackup icons

* Fri Sep  6 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-37mdk
- drakperm, drakbackup: fix embedded mode

* Fri Sep  6 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-36mdk
- gtkicons_labels_widget() :
  o add support for mcc' big icon animation
  o cleanups
  o simplify notebook redrawing vs flick/icon_aligment

* Thu Sep  5 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-35mdk
- Update banners (David Baudens)
- my_gtk snapshot for rpmdrake (gc)

* Wed Sep  4 2002 Stew Benedict <sbenedict@mandrakesoft.com> 1.1.9-34mdk
- add perl-Expect requires for drakbackup (now enabled)

* Wed Sep  4 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-33mdk
- harddrake: fix scrolling tree

* Wed Sep  4 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-32mdk
- embbed drakbackup

* Wed Sep  4 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-31mdk
- snapshot for gtktext_insert with color/font capabilities (rpmdrake)

* Tue Sep  3 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-30mdk
- ugtk:
  o better fix for glib warning that don't make drakx feel mad
  o make icons more transparent when selected in mcc

* Mon Sep  2 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-29mdk
- harddrake:
  o use new icons
  o add menu icon
- mcc: ensure all binaries're there
- ugtk: remove all glib warnings

* Mon Sep  2 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-28mdk
- tinyfirewall is now drakfirewall (daouda)

* Fri Aug 30 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-27mdk
- ugtk: add alpha blendering support for mcc's icons through pixbufs
  o readd gdkpixbuf support
  o ensure imlib is used by default to load files, not gdk-pixbuf
  o compose_with_back(): load a png icon into a pixbuf and call
    compose_pixbufs with background pixbuf
  o compose_pixbufs(): render transparent icon onto background into a
    new pixbuf
  o merge gtkcreate_png_pixbuf() from gdk-pixbuf-0-branch : load an
    icon into a pixbuf
    gdk-pixbuf-0-branch also uses it to simplify a lot of code
  o gtkicons_labels_widget() :
    * add a new background pixbuf parameter that'll be composited with icons
    * render icons with alpha blender in right area
    * kill imlib_counter
    * kill imlib usage for 
    * kill dead code (was dead since i fixed mcc memory leaks)
- fix init-script-without-chkconfig-{post,preun}

* Thu Aug 29 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-26mdk
- harddrake: 
  o quit button really work in embedded mode
  o move so called eide raid controllers from unknown to ata
    controllers
- logdrake: add a scrollbar when embedded in mcc

* Thu Aug 29 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-25mdk
- snapshot (drakupdate_fstab --auto feature (pixel), logdrake don't
  display too much information in explanations to save space for what's
  useful)

* Thu Aug 29 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-24mdk
- snapshot for display_info availability in ask_browse for rpmdrake

* Thu Aug 29 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-23mdk
- drakupdate_fstab first appearance

* Wed Aug 28 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-22mdk
- harddrake: don't display the menu bar in embedded mode, but a "quit"
  button

* Tue Aug 27 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-21mdk
- drakconnect fixes (damien)

* Fri Aug 23 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-20mdk
- draksound: display right message ("no alternative") when no
  alternative rather than "no known module"
- fixes for multiple NIC boxes (florin)

* Fri Aug 23 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-19mdk
- draksound: use right sound slot

* Fri Aug 23 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-18mdk
- ugtk: fix most mcc memory leaks (pending ones seems related to perl-gtk)
- tinyfirewall: misc fixes (pixel)

* Fri Aug 23 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-17mdk
- snapshot (including new tinyfirewall)

* Thu Aug 22 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-16mdk
- snapshot (for rpmdrake)

* Wed Aug 21 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-15mdk
- add draksound
- mousedrake: default usbmouse link to input/mice rather than
  input/mouse0, thus giving support for multiple mouse, wacom tables,
  ...

* Wed Aug 21 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-14mdk
- fix dangling waiting watch mousecursor (well, please test!)
- adding draksplash (nathan)

* Mon Aug 19 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-13mdk
- snapshot (including better XFdrake)

* Wed Aug 14 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-12mdk
- snapshot (fix diskdrake making a hell of fstab)

* Tue Aug 13 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-11mdk
- snapshot (including "diskdrake --dav")

* Mon Aug 12 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-10mdk
- snapshot (various bug fixes including no-floppy-box-segfault)

* Fri Aug  9 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-9mdk
- harddrake:
  o module configuration window:
    * read current options
    * don't display ranges, we cannot really know when a range
      is needed and so display them in wrong cases
    * read & parse modules.conf only when configuring the module,
      not on each click in the tree
    * don't display ranges, we cannot really know when a range is needed 
      and so display them in wrong cases (kill code, enable us to simplify
      modparm::parameters after

* Fri Aug  9 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-8mdk
- snapshot

* Tue Aug  6 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-7mdk
- harddrake, scannerdrake: add scsi scanner detection support
- harddrake: detect external modems

* Tue Aug  6 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-6mdk
- rebuild for perl thread-multi

* Mon Aug  5 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-5mdk
- snapshot for rpmdrake

* Fri Aug  2 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-4mdk
- have interactive::gtk::exit in my_gtk so that my_gtk apps can call
  it and then fix the problem of clock mouse cursor on exit

* Thu Aug  1 2002 Pixel <pixel@mandrakesoft.com> 1.1.9-3mdk
- keyboarddrake now handles choosing toggle key (XkbOptions)

* Thu Aug  1 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.9-2mdk
- remove obsoleted drakconf
- various fixes
- [ugtk::gtkcreate_png] suppress all gtk warnings
- updated vietnamese translation (pablo)
- [interactive::gtk] fix many warnings when {icon} is not given (pixel)

* Thu Aug  1 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.9-1mdk
- integrate patches in my_gtk and ugtk for new rpmdrake:
  - [ugtk] add "gtkentry" so that we can create an entry and set
    initial value in one call
  - [my_gtk::main] don't set the events, to fix keyboard focus
    problem in entries when embedded
  - [my_gtk::_create_window] add $::noBorder, to not have a frame
    in the main window, so that it's possible to end up with
    windows with no border
  - [my_gtk] add ask_dir which is a ask_file with only the dir list
  - [my_gtk] add ask_browse_tree_info to the export tags, and:
    - add support for parents with no leaves, so that then we can
      partially build the trees (for speedup)
    - add "delete_all" and "delete_category" callbacks
    - use Gtk::CList::clear when removing all the nodes, much
      speedup
- Titi, harddrake :
	o workaround for the busy mouse cursor set by
	  gtkset_mousecursor_wait() in my_gtk::destroy
	o remove debugging prints
	o cleanups
    - drakx: various cleanups

* Thu Aug  1 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-16mdk
- my_gtk:
	o splitup it into my_gtk and ugtk as done by dams
	o resync with dams
	o increase the icon blinkage from 50ms to 100ms
- harddrake: 
	o use new embedded managment

* Thu Aug  1 2002 Pixel <pixel@mandrakesoft.com> 1.1.8-15mdk
- harddrake (titi):
	o add embedded mode for drakconf
	o print less gtk warnings
	o module configuration window
- fix mousedrake
- fix XFdrake in embedded
- enhance XFdrake
- don't require detect-lst (titi)
- printerdrake work in progress (till)

* Wed Jul 31 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-14mdk
- harddrake:
	o fix pcmcia network card detection (unknown => ethernet)
	o fix scsi detection :
		* fix SCSI controllers detection (unknown => scsi controllers)
		* fix misdetection of scsi devices as scsi host adapter
		* fix double scsi devices detection (both unknown and real
		  category)
- updated translations
- fix mousedrake (pixel)
- drakbug, drakbackup: spell/i18n fixes (pixel, me)
- xfdrake: fixes (pixel)
- new draksex (stew)
- diskdrake: (pixel)
	o fix LVM on RAID
	o explain the pb when maximal number of primary partitions is reached

* Mon Jul 29 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-13mdk
- harddrake:
	o service: fix config file conversion
	o harddrake::ui :
	  * s/channel/Channel/
	  * bus_id is for usb devices too
	  * remove obsolete fields info and name
	  * add nbuttons, device, old_device descriptions
- updated XFdrake (gtk resolution chooser work, i810 fixes, ...) (pixel)
- remove "Requires: groff" (nobody know why it's there) (Pixel)
- updated translations (nl/id/vi)
- standalone/logdrake: (deush)
	o don't display services that are not installed
	o word wrap string correctly
	o cleanup
- bootloader.pm: (pixel)
	o let the bootloader::mkinitrd error be seen by the GUI
	o fix dying when mkinitrd doesn't create an initrd
- interactive.pm: error messages fixes (pixel)
- diskdrake: add 0x35 partition table id meaning JFS (under OS/2)
  (thank to Mika Laitio)
- printerdrake: first step of automatic HP multi-function device
  configuration with HPOJ 0.9. (till)
- drakTermServ (stew)
	o Check for/install terminal-server and friends.
	o More intelligent error message when mkisofs fails.
	o  Cleanup code for use strict.
	o Fix crash when no backup dhcpd.conf.
- drakbackup: (stew)
	o Numerous GUI crash fixes, oddities. 
	o Install	needed packages.
	o Fix email, daemon modes.
	o Add rsync, webdav, cd, tape capabilities. 
	o Consolidate net method setup screens.
	o Add CD device capability query.

* Thu Jul 25 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-12mdk
- simplify harddrake service:
	o we don't need to set media_type, we don't use it
	o mouse and mass storage media use the same key, let merge their
	  code path
	o merge timeout and cancel cases

- harddrake::data : only do one probeall here (there's still many in
  detect_devices, probing caching should go there)

- harddrake:ui : 
	o add a fields data structure:
		* put together field translation and field description
		* this enable to get rid of %reverse_fields usage & creation
		* this ensure all field names & translations are marked
		  translatables for gettext
		* move $wait declaration around its usage and explicit its
            destruction
		* remove usb debugging message needed to trace the null
		  description bug i fixed in ldetect
		* simplify the device fields rendering "because of" the
            above
		* simplify the help window creation/display/destruction
		  (only one statement left)
	o explicitely call interactive->exit
	o remove all "no signal to disconnect" gtk+ warnings 


* Thu Jul 25 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-11mdk
- rebuild against new libldetect (fix (null) descriptions)
- new XFdrake (pixel)
- harddrake:
	o devfs names
	o scanner support;
		* don't account scanners as unknown devices
		* split scannerdrake:val into vendor and description
		* don't display bogus "val:%HASH"
- updated translations (fr, pl)
- tools can be runned on console again

* Tue Jul 23 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-10mdk
- harddrake :
	o remove - between vendor and model for ibm eide disks
	o network devices are configurable again now
- draksec : typo fix (deush)

* Tue Jul 23 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-9mdk
- harddrake :
	o don't show "cancel" button in about and help windows
	o service: convert config file from plain perl to Storable binary
	  file (faster startup)
- general reorganization cleanup:
    o move interactive_* into interactive::*
    o move partition_table_* into partition_table::*
- XFdrake: more cleanups (pixel)

* Sun Jul 21 2002 Pixel <pixel@mandrakesoft.com> 1.1.8-8mdk
- new snapshot (beware of XFdrake)

* Thu Jul 18 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-7mdk
- remove last draknet reference in harddrake::ui
- disable diagnostics and strict mode

* Thu Jul 18 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-6mdk
- able to restart WindowMaker if needed
- draknet is dead; vival el drakconnect
- devices managment:
	o no need to write /etc/sysconfig/harddrake2/previous_hw in
  	  %%post since harddrake2 service doesn't configure anything if
  	  previous config was empty
	o fix usb mac mouse detection
	o move scsi/ata controllers, burners, dvd, ... from
	  unknown/others into their own"non configurable" sections
	o fix problems with usb-interface
- XFdrake: big cleanup
- general cleanups
- translation updates

* Thu Jul 11 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-5mdk
- drakx :
	o code enhancement: increase coherency around the whole drakx
	  code regarding devices
	o decrease the debug verbosity
- harddrake2 :
	o i18n:
		* move $version out of translatable strings
	o ui:
		* increase default main window size
		* put back the hw tree root
		* eide devices: split info between vendor and model strings
- spec :
	o fix parrallel build
	o list and describe all gui tools from drakxtools

* Wed Jul 10 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-4mdk
- fix perl depandancy

* Tue Jul 09 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-3mdk
- harddrake2:
	o no need to 'use strict' in "binary" => remove warnings 
	o fix boot freeze on hw change: initscript was running us with
	  stdout redirected to /dev/null; just use a small sh wrapper to
	  fix it
	o harddrake::bttv: only log in standalone mode
	o display channel of eide devices 

- spec:
	o reorder entries in description
	o list all entries in first line of description
	o fix post: add start argument

* Mon Jul 08 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-2mdk
- spec :
  o enhance descriptions
  o various spec clean
  o harddrake :
 	* obsoletes/provides libdetect-lst, libdetect-lst-devel, detect,
	  detect-lst, kudzu-devel
	* split package between harddrake and harddrake-ui to minimize
    	  the harddrake service dependancies
	* add missing /etc/sysconfig/harddrake2
- harddrake2 :
  o cache detect_devices::probeall(1) so that hw probe is run once
  o hw configuration :
  	* eide devices: split up info field into vendor and model fields
  o ui:
	* enhanced help
	* mice:
		- s/nbuttons/Number of buttons/ 
		- delete qw(MOUSETYPE XMOUSETYPE unsafe)
	* complete help
	* center the main window
	* remove drakx decorations
	* don't display "run config tool" button if no configurator
	  availlable
  o logic:
	* skip configuration on firt run
	* don't restart harddrake on install
	* skip hw classes without configurator (which'll have a
	  configurator after porting updfstab)
  o service :
	* only do the job at startup
	* add "please wait" message
	* really don't cry when no previous config

* Mon Jul 08 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.8-1mdk
- snapshot
- new entries: 
	o harddrake2 : new hardware detection && configuration tool
	o drakbugreport: bug reporting tool a la Kde (not working!)
	o drakTermServ : configuration tool for diskless stations.
- updated programs :
	o drakxtv: if runned by root, offer to configure bttv for most tv cards
	o disdrake:
		* enhanced raid & lvm support,
		* check if programs (ie jfsprogs) are installed
		* cleanups
	o Xconfigurator: bug fix
- general : better supermout support, use new libldetect, various bug fixes

* Tue Jun 18 2002 Frederic Lepied <flepied@mandrakesoft.com> 1.1.7-99mdk
- added new draksec from Christian and a new way to build the packages (make rpm)

* Mon Apr 15 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.7-98mdk
- snapshot
- add drakxtv description
- drakxtv : now auto guess the country and the freq table

* Fri Mar 15 2002 dam's <damien@mandrakesoft.com> 1.1.7-97mdk
- snapshot. final release 1

* Tue Mar 12 2002 dam's <damien@mandrakesoft.com> 1.1.7-96mdk
- added onboot options foreach network cards
- resolv.conf and domain name bug fixed

* Tue Mar 12 2002 dam's <damien@mandrakesoft.com> 1.1.7-95mdk
- included drakproxy
- corrected various timeout (net_monitor, internet connection tests)
- snapshot

* Mon Mar 11 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-94mdk
- various

* Fri Mar  8 2002 dam's <damien@mandrakesoft.com> 1.1.7-93mdk
- drakfont GUI corrected
- new drakproxy

* Fri Mar 08 2002 François Pons <fpons@mandrakesoft.com> 1.1.7-92mdk
- fixes for NVIDIA drivers support in XFdrake.

* Thu Mar  7 2002 dam's <damien@mandrakesoft.com> 1.1.7-91mdk
- lot of bugfixes
- (dams)
	* standalone/net_monitor: make gc happy
	* modparm.pm, share/po/fr.po: corrected
	* standalone/draknet: corrected network/internet restart when already
	connected
	* standalone/drakfont: corrected bad system command
	* standalone/drakautoinst: corrected HASH and ARRAY label
- (gc)
	* standalone/drakgw: 
	  - call net_monitor to disable internet connection before
	    network-restart
	  - user return value when status'ing the
	  initscripts rather than grepping their text output
- (pixel)
	* standalone/fileshareset (nfs_exports::update_server): ensure portmap
	is running

* Wed Mar  6 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-90mdk
- corrected font in wizard (dams)
- localedrake: (pixel)
  * fix dummy entries in .i18n for chineese
  * take sysconfig/i18n into account when no .i18n
  * when called by kcontrol with --apply, don't modify kde config files,
    kcontrol takes care of it more nicely
- diskdrake: translate actions in text mode (pixel)
- drakxtv fixed (titi)

* Sun Mar  3 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-89mdk
- (gtkicons_labels_widget): pass the widget instead of directly passing the font
  (for drakconf)

* Sun Mar  3 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-88mdk
- (gtkicons_labels_widget): pass the style instead of directly passing the font
  (for drakconf)

* Fri Mar  1 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-87mdk
- new snapshot (including a modified localedrake)

* Thu Feb 28 2002 dam's <damien@mandrakesoft.com> 1.1.7-86mdk
- corrected modinfo path. isa modules options should now work.

* Thu Feb 28 2002 dam's <damien@mandrakesoft.com> 1.1.7-85mdk
- corrected spec so that net_monitor.real get included too.

* Thu Feb 28 2002 dam's <damien@mandrakesoft.com> 1.1.7-84mdk
- snapshot

* Wed Feb 27 2002 dam's <damien@mandrakesoft.com> 1.1.7-83mdk
- snapshot

* Tue Feb 26 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-82mdk
- move XFdrake to drakxtools from drakxtools-newt 
(otherwise it doesn't work, since it needs perl-GTK & xtest)

* Tue Feb 26 2002 dam's <damien@mandrakesoft.com> 1.1.7-81mdk
- added groff require

* Tue Feb 26 2002 dam's <damien@mandrakesoft.com> 1.1.7-80mdk
- isa card modules correction. Should work in post install
- drakfont correction

* Sat Feb 23 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-79mdk
- require latest perl-MDK-Common
- corrected icon paths (thanks to garrick)
- don't create devices when /dev is devfs mounted (thanks to Andrej Borsenkow)

* Fri Feb 22 2002 dam's <damien@mandrakesoft.com> 1.1.7-78mdk
- corrected icon paths

* Thu Feb 21 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.7-77mdk
- now we can live without kdesu ; and drakxtools-newt only requires
  usermode-consoleonly

* Tue Feb 19 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-76mdk
- fix diskdrake --nfs & --smb

* Tue Feb 19 2002 dam's <damien@mandrakesoft.com> 1.1.7-75mdk
- required specific version of perl MDK Common

* Tue Feb 19 2002 dam's <damien@mandrakesoft.com> 1.1.7-74mdk
- various things not described by the last packager
- new png/wpm search policy in my_gtk

* Mon Feb 18 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-73mdk
- snapshot

* Sat Feb 16 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-72mdk
- localedrake now handles KDE
- diskdrake now handles XFS on LVM live resizing (growing only)

* Fri Feb 15 2002 dam's <damien@mandrakesoft.com> 1.1.7-71mdk
- snapshot

* Thu Feb 14 2002 dam's <damien@mandrakesoft.com> 1.1.7-70mdk
- snapshot

* Mon Feb 11 2002 dam's <damien@mandrakesoft.com> 1.1.7-69mdk
- fixed bad stuff.so in drakxtools

* Fri Feb  8 2002 dam's <damien@mandrakesoft.com> 1.1.7-68mdk
- new gfx
- various fix
- major printerdrake updates

* Thu Feb 07 2002 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.7-67mdk
- add drakxtv

* Thu Feb  7 2002 dam's <damien@mandrakesoft.com> 1.1.7-66mdk
- new package, various wizard, mygtk, disdrake improvment.

* Wed Feb  6 2002 dam's <damien@mandrakesoft.com> 1.1.7-65mdk
- logdrake updates
- wizard fix

* Tue Jan 29 2002 dam's <damien@mandrakesoft.com> 1.1.7-64mdk
- last mygtk, drakbackup...
- disdrake fixed
- snapshot

* Sun Jan 27 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-63mdk
- cleanup drakxtools-newt (move all gtk stuff to drakxtools)
- reworked and split diskdrake
- add logdrake

* Fri Jan 25 2002 dam's <damien@mandrakesoft.com> 1.1.7-62mdk
- bug corrections, improvements
- new advertising engine
- new gtkicons_labels_widget

* Tue Jan 22 2002 dam's <damien@mandrakesoft.com> 1.1.7-61mdk
- new gtkicons_labels_widget for new mcc.

* Fri Jan 18 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.7-60mdk
- first support for 'Explanations'

* Fri Jan 18 2002 Sebastien Dupont <sdupont@mandrakesoft.com>  1.1.7-59mdk
- Drakbackup without unstable options for qa. 
- DrakFont update warning message (qa).

* Wed Jan 16 2002 Pixel <pixel@mandrakesoft.com> 1.1.7-58mdk
- ensure lsnetdrake is included

* Tue Jan 15 2002 Sebastien Dupont <sdupont@mandrakesoft.com>  1.1.7-57mdk
- Drakbackup daemon, backend mode (-show-conf -daemon -debug -help -version) and report mail corrections.
- DrakFont gi and progress bar problems.

* Tue Jan 14 2002 Sebastien Dupont <sdupont@mandrakesoft.com>  1.1.7-56mdk
- New drakbackup version, ftp backup work, new pixmaps.
- DrakFont with new pixmaps. 

* Mon Jan 14 2002 Stefan van der Eijk <stefan@eijk.nu> 1.1.7-55mdk
- BuildRequires

* Fri Jan 11 2002 dam's <damien@mandrakesoft.com> 1.1.7-54mdk
- snapshot

* Wed Jan  9 2002 dam's <damien@mandrakesoft.com> 1.1.7-53mdk
- snapshot
- new code in my_gtk

* Tue Jan  8 2002 Sebastien Dupont <sdupont@mandrakesoft.com>  1.1.7-52mdk
- New drakbackup version, incremental backup and restore should work. 

* Sat Dec 22 2001 Sebastien Dupont <sdupont@mandrakesoft.com> 1.1.7-51mdk
- fix  conflicts in drakbackup cvs version.

* Sat Dec 22 2001 Sebastien Dupont <sdupont@mandrakesoft.com> 1.1.7-50mdk
- new drakbackup version.

* Mon Dec 10 2001 Sebastien Dupont <sdupont@mandrakesoft.com> 1.1.7-49mdk
- fix drakfont path problem.
- new version of drakbakup

* Wed Dec  5 2001 dam's <damien@mandrakesoft.com> 1.1.7-48mdk
- corrected syntax error

* Tue Dec  4 2001 dam's <damien@mandrakesoft.com> 1.1.7-47mdk
- avoid network test freeze
- added drackbackup
- snapshot

* Fri Nov 30 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-46mdk
- add diskdrake --fileshare

* Thu Nov 29 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-45mdk
- new diskdrake including fileshareset/filesharelist stuff

* Mon Nov 26 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-44mdk
- use the CVS, not my devel (instable) version

* Fri Nov 23 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-43mdk
- any.pm fixed

* Mon Nov 19 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.7-42mdk
- scannerdrake update to add dynamic support

* Mon Nov 12 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.7-41mdk
- scannerdrake update with new fat ScannerDB

* Mon Nov  5 2001 dam's <damien@mandrakesoft.com> 1.1.7-40mdk
- corrected typo in drakautoinst

* Fri Nov  2 2001 dam's <damien@mandrakesoft.com> 1.1.7-39mdk
- release

* Fri Oct 26 2001 dam's <damien@mandrakesoft.com> 1.1.7-38mdk
- drakautoinst & drakfont updated

* Thu Oct 25 2001 dam's <damien@mandrakesoft.com> 1.1.7-37mdk
- big improvement on drakautoinst
- draknet : connection script updated 

* Thu Oct 18 2001 dam's <damien@mandrakesoft.com> 1.1.7-36mdk
- draknet/net_monitor corrected
- corrected bad stuff.so

* Tue Oct 16 2001 dam's <damien@mandrakesoft.com> 1.1.7-35mdk
- make rplint happier

* Wed Oct 10 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.7-34mdk
- snapshot with scanner stuff

* Mon Sep 24 2001 dam's <damien@mandrakesoft.com> 1.1.7-33mdk
- snapshot

* Mon Sep 24 2001 dam's <damien@mandrakesoft.com> 1.1.7-32mdk
- Last translations.

* Mon Sep 24 2001 dam's <damien@mandrakesoft.com> 1.1.7-31mdk
- snapshot. draknet bugfix.

* Sun Sep 23 2001 dam's <damien@mandrakesoft.com> 1.1.7-30mdk
- snapshot. Included last printer and draknet corrections.

* Fri Sep 21 2001 dam's <damien@mandrakesoft.com> 1.1.7-29mdk
- typo in adsl.pm, Xconfigurator fix.

* Thu Sep 20 2001 dam's <damien@mandrakesoft.com> 1.1.7-28mdk
- snapshot. draknet works now. 

* Wed Sep 19 2001 dam's <damien@mandrakesoft.com> 1.1.7-27mdk
- snapshot

* Mon Sep 17 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-26mdk
- snapshot

* Mon Sep 17 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-25mdk
- snapshot

* Sat Sep 15 2001 dam's <damien@mandrakesoft.com> 1.1.7-24mdk
- snapshot with printer, draknet & install fixes

* Fri Sep 14 2001 François Pons <fpons@mandrakesoft.com> 1.1.7-23mdk
- snapshot with latest XFdrake fixes.

* Fri Sep 14 2001 dam's <damien@mandrakesoft.com> 1.1.7-22mdk
- snapshot

* Thu Sep 13 2001 François Pons <fpons@mandrakesoft.com> 1.1.7-21mdk
- fix Xinerama for Matrox cards (restore XFree86 4.1.0 without DRI).
- removed Modeline 1024x768 in 97.6 Hz which troubles XF4 a lot.

* Thu Sep 13 2001 François Pons <fpons@mandrakesoft.com> 1.1.7-20mdk
- snapshot with XFdrake fixes (G550 support, no DRI with Xinerama,
  no XFree86 3.3.6 proposed wiht dual head).

* Wed Sep 12 2001 dam's <damien@mandrakesoft.com> 1.1.7-19mdk
- snapshot

* Wed Sep 12 2001 dam's <damien@mandrakesoft.com> 1.1.7-18mdk
- snapshot.

* Mon Sep 10 2001 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.7-17mdk
- remove dependency on "perl" since pixel added Data::Dumper in perl-base

* Mon Sep 10 2001 dam's <damien@mandrakesoft.com> 1.1.7-16mdk
- new snapshot, bug corrections.

* Thu Sep  6 2001 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.7-15mdk
- drakgw should be working now

* Tue Sep 04 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.7-14mdk
- snaphsot, better interaction with mcc (diskdrake printerdrake).

* Tue Sep  4 2001 dam's <damien@mandrakesoft.com> 1.1.7-13mdk
- snapshot.

* Thu Aug 30 2001 dam's <damien@mandrakesoft.com> 1.1.7-12mdk
- snapshot. locales corected, nicer wizards.

* Thu Aug 30 2001 François Pons <fpons@mandrakesoft.com> 1.1.7-11mdk
- new snapshot, mousedrake fixes again.

* Wed Aug 29 2001 François Pons <fpons@mandrakesoft.com> 1.1.7-10mdk
- new snapshot, mousedrake fixes.

* Fri Aug 24 2001 dam's <damien@mandrakesoft.com> 1.1.7-9mdk
- snapshot for 8.1 beta2.

* Fri Aug 24 2001 dam's <damien@mandrakesoft.com> 1.1.7-8mdk
- bugfix.
- new snapshot. mousedrake experimental.

* Thu Aug 23 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.7-7mdk
- fix drakboot bug
- macros to fix some rpmlint warnings

* Wed Aug 22 2001 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.7-6mdk
- put a require on "perl" which is needed for Data::Dumper in drakautoinst

* Wed Aug 22 2001 dam's <damien@mandrakesoft.com> 1.1.7-5mdk
- snapshot. draknet improvments, bug fixes.

* Mon Aug 20 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-4mdk
- new fstab munching code

* Sat Aug 18 2001 Pixel <pixel@mandrakesoft.com> 1.1.7-3mdk
- new diskdrake (with interactive version => newt)
- drakxtools-http fix

* Tue Aug 14 2001 dam's <damien@mandrakesoft.com> 1.1.7-2mdk
- added doc (it's a shame...)

* Tue Aug 14 2001 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.7-1mdk
- add drakautoinst

* Mon Aug 13 2001 dam's <damien@mandrakesoft.com> 1.1.6-3mdk
- snapshot

* Tue Aug  7 2001 dam's <damien@mandrakesoft.com> 1.1.6-2mdk
- added draknet_splash pixmap

* Tue Aug  7 2001 Pixel <pixel@mandrakesoft.com> 1.1.6-1mdk
- add drakxtools_http

* Fri Aug  3 2001 dam's <damien@mandrakesoft.com> 1.1.5-106mdk
- added network/*.pm

* Tue Jul 31 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-105mdk
- add require perl-MDK-Common
- fix for cp -rf (fuck FreeBSD (c))

* Tue Jul 31 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-104mdk
- fix my error: %%files with 2 times "-f <file>" doesn't work :-(

* Mon Jul 30 2001 dam's <damien@mandrakesoft.com> 1.1.5-103mdk
- updated with cooker install.
- added require on XFree86-75dpi-fonts
- merged with pixel specfile to handle mo.

* Mon May  7 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-102mdk
- updated bootloader.pm according to new lilo package (lilo-{menu,graphic,text})

* Wed Apr 25 2001 François Pons <fpons@mandrakesoft.com> 1.1.5-101mdk
- updated with oem update for DrakX.
- minor bug correction on printerdrake.
- added minor features to XFdrake.

* Wed Apr 18 2001 dam's <damien@mandrakesoft.com> 1.1.5-100mdk
- added require on usermode.
- added source 2 and 3.
- snapshot. netconnect corrections. final package

* Tue Apr 17 2001 dam's <damien@mandrakesoft.com> 1.1.5-99mdk
- snapshot. mousedrake corrected. RC6

* Tue Apr 17 2001 dam's <damien@mandrakesoft.com> 1.1.5-98mdk
- snapshot. autologin corrected. RC5

* Tue Apr 17 2001 dam's <damien@mandrakesoft.com> 1.1.5-97mdk
- snapshot. RC4

* Tue Apr 17 2001 dam's <damien@mandrakesoft.com> 1.1.5-96mdk
- snapshot. RC3

* Mon Apr 16 2001 dam's <damien@mandrakesoft.com> 1.1.5-95mdk
- snapshot. RC2

* Mon Apr 16 2001 dam's <damien@mandrakesoft.com> 1.1.5-94mdk
- snapshot. RC

* Mon Apr 16 2001 dam's <damien@mandrakesoft.com> 1.1.5-93mdk
- draknet and tinyfirewall fixes

* Sun Apr 15 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-92mdk
- bootlook fix & layout

* Fri Apr 13 2001 dam's <damien@mandrakesoft.com> 1.1.5-91mdk
- snapshot

* Fri Apr 13 2001 dam's <damien@mandrakesoft.com> 1.1.5-90mdk
- snapshot

* Thu Apr 12 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-89mdk
- snapshot

* Thu Apr 12 2001 dam's <damien@mandrakesoft.com> 1.1.5-88mdk
- snapshot. pcmcia network corrected

* Thu Apr 12 2001 dam's <damien@mandrakesoft.com> 1.1.5-87mdk
- snapshot. Better network configuration

* Thu Apr 12 2001 dam's <damien@mandrakesoft.com> 1.1.5-86mdk
- snapshot.

* Wed Apr 11 2001 François Pons <fpons@mandrakesoft.com> 1.1.5-85mdk
- really fix printerdrake and snap.

* Wed Apr 11 2001 François Pons <fpons@mandrakesoft.com> 1.1.5-84mdk
- fix printerdrake and snap.

* Tue Apr 10 2001 dam's <damien@mandrakesoft.com> 1.1.5-83mdk
- bug correction.

* Mon Apr  9 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-82mdk
- snap as always

* Mon Apr  9 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-81mdk
- snaphshot again and again

* Mon Apr  9 2001 dam's <damien@mandrakesoft.com> 1.1.5-80mdk
- snapshot. bug fix

* Sun Apr  8 2001 dam's <damien@mandrakesoft.com> 1.1.5-79mdk
- snapshot. bug fix.

* Sun Apr  8 2001 dam's <damien@mandrakesoft.com> 1.1.5-78mdk
- added require on XFree86-100dpi-fonts
- various debugging
- new tinyfirewall

* Sun Apr  8 2001 dam's <damien@mandrakesoft.com> 1.1.5-77mdk
- snapshot
- net_monitor added.

* Fri Apr  6 2001 dam's <damien@mandrakesoft.com> 1.1.5-76mdk
- corrected compilation error.

* Fri Apr  6 2001 yves <yduret@mandrakesoft.com> 1.1.5-75mdk
- snapshot : drakgw updated, boot config fix

* Thu Apr  5 2001 dam's <damien@mandrakesoft.com> 1.1.5-74mdk
- snapshot.

* Mon Apr  2 2001 dam's <damien@mandrakesoft.com> 1.1.5-73mdk
- snapshot.

* Mon Apr  2 2001 dam's <damien@mandrakesoft.com> 1.1.5-72mdk
- snapshot, typo fixs.

* Fri Mar 30 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-71mdk
- snapshot & fixes

* Fri Mar 30 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-70mdk
- snapshot : boot coonfig updated

* Thu Mar 29 2001 dam's <damien@mandrakesoft.com> 1.1.5-69mdk
- snapshot

* Thu Mar 29 2001 dam's <damien@mandrakesoft.com> 1.1.5-68mdk
- snapshot.

* Thu Mar 29 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-67mdk
- new snapshot (XFdrake should be working)

* Wed Mar 28 2001 dam's <damien@mandrakesoft.com> 1.1.5-66mdk
- corrected tinyfirewall last step

* Wed Mar 28 2001 François Pons <fpons@mandrakesoft.com> 1.1.5-65mdk
- fixed wrong generation of second mouse support

* Wed Mar 28 2001 François Pons <fpons@mandrakesoft.com> 1.1.5-64mdk
- fixed multi-mouse support for XF3
- fixed XFdrake (read old config file before so probe overwrite)

* Wed Mar 28 2001 dam's <damien@mandrakesoft.com> 1.1.5-63mdk
- added draksec embedded mode
- corrected tinyfirewall for 2.4 kernels
- corrected bad translations in draknet

* Tue Mar 27 2001 dam's <damien@mandrakesoft.com> 1.1.5-62mdk
- idem.

* Sat Mar 24 2001 dam's <damien@mandrakesoft.com> 1.1.5-61mdk
- corrected tinyfirewall

* Fri Mar 23 2001 dam's <damien@mandrakesoft.com> 1.1.5-60mdk
- snapshot
- corrected require.

* Fri Mar 23 2001 dam's <damien@mandrakesoft.com> 1.1.5-59mdk
- added ldetect in require.
- tinyfirewall included.

* Thu Mar 22 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-58mdk
- updated drakboot, new snapshot

* Thu Mar 22 2001 dam's <damien@mandrakesoft.com> 1.1.5-57mdk
- draknet without mail conf, new snapshot.

* Thu Mar 22 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-56mdk
- new version that will work with perl-base (at least XFdrake)

* Thu Mar 22 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-55mdk
- require perl-base not perl, it should be enough

* Thu Mar 22 2001 dam's <damien@mandrakesoft.com> 1.1.5-54mdk
- first release with tinyfirewall. Not stable.
- corrected gmon pb, I suck.

* Tue Mar 20 2001 dam's <damien@mandrakesoft.com> 1.1.5-53mdk
- corrected bad links.

* Tue Mar 20 2001 dam's <damien@mandrakesoft.com> 1.1.5-52mdk
- no crash anymore.

* Tue Mar 20 2001 dam's <damien@mandrakesoft.com> 1.1.5-51mdk
- updated draknet. new snapshot.

* Wed Mar 14 2001 dam's <damien@mandrakesoft.com> 1.1.5-50mdk
- some minor label improvements.

* Tue Mar 13 2001 Yves Duret <yduret@mandrakesoft.com> 1.1.5-49mdk
- updated bootlook
- macros

* Mon Mar 12 2001 dam's <damien@mandrakesoft.com> 1.1.5-48mdk
- correted wizard pixmaps name

* Mon Mar 12 2001 dam's <damien@mandrakesoft.com> 1.1.5-47mdk
- new and shinny drakxservices

* Tue Mar  6 2001 dam's <damien@mandrakesoft.com> 1.1.5-46mdk
- XFdrake works + other improvements

* Thu Mar  1 2001 dam's <damien@mandrakesoft.com> 1.1.5-45mdk
- updated embedded mode.

* Wed Feb 28 2001 dam's <damien@mandrakesoft.com> 1.1.5-44mdk
- XFdrake : new look.
- draknet : some corrections.
- install : some improvements

* Mon Feb 26 2001 dam's <damien@mandrakesoft.com> 1.1.5-43mdk
- corrected draknet, and some other stuff

* Mon Feb 26 2001 dam's <damien@mandrakesoft.com> 1.1.5-42mdk
- new draknet, with wizard and profiles.
- drakboot short-circuited.
- new pixmaps policy.

* Fri Feb 23 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-41mdk
- require perl-GTK-GdkImlib, fix XFdrake and draknet with no perl-GTK

* Fri Feb 23 2001 Pixel <pixel@mandrakesoft.com> 1.1.5-40mdk
- split in drakxtools and drakxtools-newt

* Thu Feb  8 2001 dam's <damien@mandrakesoft.com> 1.1.5-39mdk
- install() and SHAR_PATH bug fixed in standalone.pm

* Thu Feb  8 2001 dam's <damien@mandrakesoft.com> 1.1.5-38mdk
- bug fix.

* Thu Feb  8 2001 dam's <damien@mandrakesoft.com> 1.1.5-37mdk
- bug correction inclusion.

* Wed Feb  7 2001 dam's <damien@mandrakesoft.com> 1.1.5-36mdk
- snapshot. Included embedded mode (for control-center), and wizard mode.

* Mon Dec 18 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-35mdk
- new version (lspcidrake not here anymore, requires ldetect-lst => don't
include pcitable/... anymore)


* Tue Nov 14 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-34mdk
- snapshot
- get rid of the rpmlib dependency

* Sat Oct 21 2000 dam's <damien@mandrakesoft.com> 1.1.5-33mdk
- RC1_fixed tagged cvs version.
- Video cards handling enhanced
- isa isdn-cards and non detected isdn pci-cards spported.

* Thu Oct 19 2000 dam's <damien@mandrakesoft.com> 1.1.5-32mdk
- snapshot.

* Mon Oct  9 2000 dam's <damien@mandrakesoft.com> 1.1.5-31mdk
- snapshot.

* Fri Oct  6 2000 dam's <damien@mandrakesoft.com> 1.1.5-30mdk
- snapshot.

* Fri Oct  6 2000 dam's <damien@mandrakesoft.com> 1.1.5-29.1mdk
- snapshot. not fully stable.

* Thu Oct  5 2000 dam's <damien@mandrakesoft.com> 1.1.5-29mdk
- snapshot.

* Thu Oct 05 2000 François Pons <fpons@mandrakesoft.com> 1.1.5-28mdk
- snapshot.

* Tue Oct 03 2000 François Pons <fpons@mandrakesoft.com> 1.1.5-27mdk
- snapshot.

* Sun Oct  1 2000 dam's <damien@mandrakesoft.com> 1.1.5-26mdk
- snapshot.

* Sat Sep 30 2000 dam's <damien@mandrakesoft.com> 1.1.5-25mdk
- snapshot.

* Sat Sep 30 2000 dam's <damien@mandrakesoft.com> 1.1.5-24mdk
- snapshot. draknet frozen.

* Fri Sep 29 2000 dam's <damien@mandrakesoft.com> 1.1.5-23mdk
- snapshot.

* Thu Sep 28 2000 dam's <damien@mandrakesoft.com> 1.1.5-22mdk
- modified spec.
- snapshot
- liveupdate

* Wed Sep 27 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-21mdk
- snapshot

* Tue Sep 26 2000 dam's <damien@mandrakesoft.com> 1.1.5-20mdk
- snapshot

* Mon Sep 25 2000 dam's <damien@mandrakesoft.com> 1.1.5-19mdk
- snapshot.

* Fri Sep 22 2000 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.5-18mdk
- new snapshot
- remove BuildRequires kudzu-devel, I suck bigtime..

* Thu Sep 21 2000 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.5-17mdk
- new snapshot
- BuildRequires kudzu-devel since ddcprobe/ddcxinfos.c uses /usr/include/vbe.h

* Wed Sep 20 2000 dam's <damien@mandrakesoft.com> 1.1.5-16mdk
- cvs snapshot. See changelog file

* Wed Sep 20 2000 dam's <damien@mandrakesoft.com> 1.1.5-15mdk
- cvs snapshot. See changelog file

* Fri Sep 15 2000 dam's <damien@mandrakesoft.com> 1.1.5-14mdk
- cvs snapshot.
- draknet : better dsl configuration.

* Thu Sep 14 2000 dam's <damien@mandrakesoft.com> 1.1.5-13mdk
- cvs snapshot.
- draknet : wizard mode. isdn_db.txt moved to /usr/share. No makedev.sh any more

* Mon Sep 11 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-12mdk
- add handling for gnome and kde2 in Xdrakres

* Thu Sep  7 2000 dam's <damien@mandrakesoft.com> 1.1.5-11mdk
- corrected draknet launch error.

* Thu Sep  7 2000 dam's <damien@mandrakesoft.com> 1.1.5-10mdk
- ISDN connection should work. test it!

* Tue Sep  5 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-9mdk
- setAutologin fixed in XFdrake

* Tue Sep  5 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-8mdk
- adduserdrake fixed

* Sat Sep  2 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-7mdk
- fix some typos in standalone/keyboarddrake
- add require perl

* Sat Sep  2 2000 Pixel <pixel@mandrakesoft.com> 1.1.5-6mdk
- add %%lang tags

* Tue Aug 29 2000 dam's <damien@mandrakesoft.com> 1.1.5-5mdk
- draknet : isa cards better recognized.

* Mon Aug 28 2000 dam's <damien@mandrakesoft.com> 1.1.5-4mdk
- corrected draknet. Please test it!

* Sun Aug 27 2000 dam's <damien@mandrakesoft.com> 1.1.5-3mdk
- Added draknet in standalone

* Fri Aug 18 2000 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.5-2mdk
- add requires to modutils >= 2.3.11 because drakgw is reading
  /etc/modules.conf which has been introduced in 2.3.11

* Fri Aug 18 2000 Guillaume Cottenceau <gc@mandrakesoft.com> 1.1.5-1mdk
- added `drakgw' in standalone (Internet Connection Sharing tool)

* Fri Aug 11 2000 Pixel <pixel@mandrakesoft.com> 1.1.4-3mdk
- new snapshot

* Thu Aug 10 2000 Pixel <pixel@mandrakesoft.com> 1.1.4-2mdk
- add noreplace for diskdrake.rc

* Thu Aug 10 2000 Pixel <pixel@mandrakesoft.com> 1.1.4-1mdk
- new snapshot

* Mon Aug 07 2000 Frederic Lepied <flepied@mandrakesoft.com> 1.1.3-2mdk
- automatically added BuildRequires

* Fri Jul 21 2000 Pixel <pixel@mandrakesoft.com> 1.1.3-1mdk
- new version, BM

* Wed Jul 05 2000 Thierry Vignaud <tvignaud@mandrakesoft.com> 1.1.2-2mdk
- build against new libbz2

* Mon Jun 26 2000 Pixel <pixel@mandrakesoft.com> 1.1.2-1mdk
- new version

* Tue Jun 13 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-13mdk
- hopefully fix XFdrake and DDR nvidia cards (silly xfree that is)

* Mon Jun  5 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-12mdk
- fix sbus missing

* Sat Jun  3 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-10mdk
- fix draksec calling init.sh instead of msec

* Thu May 25 2000 Chmouel Boudjnah <chmouel@mandrakesoft.com> 1.1.1-9mdk
- Don't display x86 stuff on drakboot when we are on others arch.

* Thu May 25 2000 François Pons <fpons@mandrakesoft.com> 1.1.1-8mdk
- update with first version for sparc and sparc64.
- fix for printer configuration for SAMBA and NCP (security issue).

* Tue May  9 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-7mdk
- many small fixes (bis)

* Tue May  2 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-6mdk
- many small fixes

* Wed Apr 26 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-5mdk
- new version (fix in adduserdrake, enhance interactive_newt)

* Wed Apr 19 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-4mdk
- llseek works, not lseek64 :(  (need more testing)

* Wed Apr 19 2000 François Pons <fpons@mandrakesoft.com> 1.1.1-3mdk
- updated with CVS of DrakX.

* Fri Mar 31 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-2mdk
- obsoletes setuptool, link setuptool to drakxconf

* Fri Mar 31 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-1mdk
- new version (added drakboot for lilo/grub, XFdrake -xf4 for XFree4)

* Sat Mar 25 2000 Pixel <pixel@mandrakesoft.com> 1.1-1mdk
- new group
- new version

* Wed Jan 12 2000 François PONS <fpons@mandrakesoft.com>
- complete update with DrakX, small fixe on printerdrake again.

* Wed Jan 12 2000 François PONS <fpons@mandrakesoft.com>
- corrected missing generic postscript and text driver for
  printderdrake.

* Wed Jan 12 2000 François PONS <fpons@mandrakesoft.com>
- corrected bad resolution setting in printerdrake.

* Wed Jan 12 2000 François PONS <fpons@mandrakesoft.com>
- fixed print on STDOUT in printerdrake.
- corrected printerdrake against not available drivers in gs.

* Mon Jan 10 2000 Pixel <pixel@mandrakesoft.com>
- new version (bis)
- printerdrake install rhs-printfilters via urpmi if needed

* Fri Jan 07 2000 François PONS <fpons@mandrakesoft.com>
- updated XFdrake and PrinterDrake.

* Fri Jan  7 2000 Pixel <pixel@mandrakesoft.com>
- fixed a bug causing no i18n for rpmdrake
- add require urpmi

* Thu Jan  6 2000 Pixel <pixel@mandrakesoft.com>
- fix an error case in XFdrake

* Tue Jan  4 2000 Pixel <pixel@mandrakesoft.com>
- adduserdrake accept user names on command line
- minor fixes

* Fri Dec 31 1999 Pixel <pixel@mandrakesoft.com>
- 32mdk

* Wed Dec 29 1999 Pixel <pixel@mandrakesoft.com>
- make rpmlint happier
- minor fixes

* Mon Dec 27 1999 Pixel <pixel@mandrakesoft.com>
- better XFdrake and minor fixes

* Fri Dec 24 1999 Pixel <pixel@mandrakesoft.com>
- new version (better adduserdrake and more)
- add /usr/bin/* (for lspcidrake)

* Wed Dec 22 1999 Pixel <pixel@mandrakesoft.com>
- do not try display :0 if DISPLAY is unset

* Mon Dec 20 1999 Pixel <pixel@mandrakesoft.com>
- fixed a bug in drakxservices
- XFdrake now install XFree86 and XFree86-75dpi-fonts if needed
- XFdrake now calls /etc/rc.d/init.d/xfs start if needed
- minor fix

* Sat Dec 18 1999 Pixel <pixel@mandrakesoft.com>
- added kpackage's icons for rpmdrake

* Thu Dec 16 1999 Pixel <pixel@mandrakesoft.com>
- bzip2 .po's
- mount /proc in XFdrake to avoid freeze when called by kudzu
- added Xdrakres

* Thu Dec 16 1999 Chmouel Boudjnah <chmouel@mandrakesoft.com>
- Remove the netdrake ghost.

* Thu Dec 16 1999 Pixel <pixel@mandrakesoft.com>
- fix draksec
- many changes in libDrakX

* Sat Dec 11 1999 Pixel <pixel@mandrakesoft.com>
- adduserdrake added and some more

* Thu Dec  9 1999 Pixel <pixel@linux-mandrake.com>
- added drakxconf, drakxservices
- handle non root via kdesu if X
- warning go to syslog

* Wed Dec  8 1999 Chmouel Boudjnah <chmouel@mandrakesoft.com>
- Add %post and %postun to link redhat tools to our tools.
- Obsoletes: Xconfigurator mouseconfig kbdconfig printtool
- A lots of changes/fix.

* Thu Dec  2 1999 Pixel <pixel@linux-mandrake.com>
- keyboarddrake added, and many changes
- fixed typos

* Fri Nov 26 1999 Pixel <pixel@linux-mandrake.com>
- new version (printerdrake) (did i say lspcidrake was there too?)

* Wed Nov 24 1999 Pixel <pixel@linux-mandrake.com>
- new version
- fixed *.o bundled in the %source

* Sun Nov 21 1999 Pixel <pixel@mandrakesoft.com>
- removed %config for diskdrake.rc (should i?)
- removed xtest from the requires
- added %config for diskdrake.rc (should i?)
- strip .so and ddcxinfos (nice rpmlint :)

* Sat Nov 20 1999 Pixel <pixel@mandrakesoft.com>
- added MonitorsDB to %files (silly me:-!)

* Thu Nov 18 1999 Pixel <pixel@mandrakesoft.com>
- precised the required version for perl-GTK

* Thu Nov 18 1999 Pixel <pixel@mandrakesoft.com>
- First version


# end of file
