Summary: The drakxtools (XFdrake, diskdrake, keyboarddrake, mousedrake...)
Name:    drakxtools
Version: 1.1.11
Release: 2mdk
Url: http://www.linux-mandrake.com/en/drakx.php3
Source0: %name-%version.tar.bz2
License: GPL
Group: System/Configuration/Other
Requires: %{name}-newt = %version-%release, perl-GTK >= 0.6123, perl-GTK-GdkImlib, perl-GTK-GdkPixbuf, XFree86-100dpi-fonts, XFree86-75dpi-fonts, /usr/X11R6/bin/xtest, font-tools, usermode >= 1.44-4mdk, perl-MDK-Common >= 1.0.3-12mdk
Conflicts: drakconf < 0.96-10mdk 
BuildRequires: gettext, gtk+-devel, ldetect-devel, ncurses-devel, newt-devel, perl-devel, libext2fs-devel
BuildRoot: %_tmppath/%name-buildroot
Provides: draksec
Obsoletes: draksec

%package newt
Summary: The drakxtools (XFdrake, diskdrake, keyboarddrake, mousedrake...)
Group: System/Configuration/Other
Requires: perl-base >= 1:5.8.0-10mdk, urpmi, modutils >= 2.3.11, ldetect-lst >= 0.1.4-1mdk, usermode-consoleonly >= 1.44-4mdk
Obsoletes: diskdrake setuptool
Obsoletes: mouseconfig kbdconfig printtool drakfloppy
Provides: diskdrake setuptool mouseconfig kbdconfig printtool

%package http
Summary: The drakxtools via http
Group: System/Configuration/Other
Requires: %{name}-newt = %version-%release, perl-Net_SSLeay, perl-Authen-PAM, perl-CGI
PreReq: rpm-helper

%package -n harddrake
Summary: Main Hardware Configuration/Information Tool
Group: System/Configuration/Hardware
Requires: %{name}-newt = %version-%release
Obsoletes: kudzu, kudzu-devel, libdetect0, libdetect0-devel, libdetect-lst, libdetect-lst-devel, detect, detect-lst
Provides: kudzu, kudzu-devel, libdetect0, libdetect0-devel, libdetect-lst, libdetect-lst-devel, detect, detect-lst
Prereq: rpm-helper

%package -n harddrake-ui
Summary: Main Hardware Configuration/Information Tool
Group: System/Configuration/Hardware
Requires: %name = %version-%release

%description
Contains many Mandrake applications simplifying users and
administrators life on a Mandrake Linux machine. Nearly all of
them work both under XFree (graphical environment) and in console
(text environment), allowing easy distant work.

adduserdrake: help you adding a user

ddcxinfos: get infos from the graphic card and print XF86Config
modlines

diskdrake: DiskDrake makes hard disk partitioning easier. It is
graphical, simple and powerful. Different skill levels are available
(newbie, advanced user, expert). It's written entirely in Perl and
Perl/Gtk. It uses resize_fat which is a perl rewrite of the work of
Andrew Clausen (libresize).

drakautoinst: help you configure an automatic installation replay

drakbackup: backup and restore your system

drakboot: configures your boot configuration (Lilo/GRUB,
Bootsplash, X, autologin)

drakbug: interactive bug report tool

drakbug_report: help find bugs in DrakX

drakconnect: LAN/Internet connection configuration. It handles
ethernet, ISDN, DSL, cable, modem.

drakfloppy: boot disk creator

drakfont: import fonts in the system

drakgw: internet connection sharing

drakproxy: proxies configuration

draksec: security options managment / msec frontend

draksound: sound card configuration

draksplash: bootsplash themes creation

drakTermServ: mandrake terminal server configurator

drakxservices: SysV service and dameaons configurator

drakxtv: auto configure tv card for xawtv grabber

keyboarddrake: configure your keyboard (both console and X)

liveupdate: live update software

logdrake: show extracted information from the system logs

lsnetdrake: display available nfs and smb shares

lspcidrake: display your pci information, *and* the corresponding
kernel module

localedrake: language configurator, available both for root
(system wide) and users (user only)

mousedrake: autodetect and configure your mouse

printerdrake: detect and configure your printer

scannerdrake: scanner configurator

drakfirewall: simple firewall configurator

XFdrake: menu-driven program which walks you through setting up
your X server; it autodetects both monitor and video card if
possible


%description newt
See package %name

%description http
This add the capability to be runned behind a web server to the drakx tools.
See package %name


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
%make rpcinfo-flushed ddcprobe serial_probe 
%make

%install
rm -rf $RPM_BUILD_ROOT

%make PREFIX=$RPM_BUILD_ROOT install
mkdir -p $RPM_BUILD_ROOT/{%_initrddir,%_sysconfdir/{X11/xinit.d,sysconfig/harddrake2}}
touch $RPM_BUILD_ROOT/etc/sysconfig/harddrake2/previous_hw

mv $RPM_BUILD_ROOT%_sbindir/net_monitor \
   $RPM_BUILD_ROOT%_sbindir/net_monitor.real
ln -sf %_bindir/consolehelper $RPM_BUILD_ROOT%_sbindir/net_monitor
mkdir -p $RPM_BUILD_ROOT%_sysconfdir/{pam.d,security/console.apps}
cp pam.net_monitor $RPM_BUILD_ROOT%_sysconfdir/pam.d/net_monitor
cp apps.net_monitor $RPM_BUILD_ROOT%_sysconfdir/security/console.apps/net_monitor

dirs1="usr/lib/libDrakX usr/share/libDrakX"
(cd $RPM_BUILD_ROOT ; find $dirs1 usr/bin usr/sbin ! -type d -printf "/%%p\n")|egrep -v 'bin/.*harddrake' > %{name}.list
(cd $RPM_BUILD_ROOT ; find $dirs1 -type d -printf "%%%%dir /%%p\n") >> %{name}.list

perl -ni -e '/XFdrake|bootlook|drakbackup|drakfont|gtk|icons|logdrake|net_monitor|pixmaps/ ? print STDERR $_ : print' %{name}.list 2> %{name}-gtk.list
perl -ni -e '/http/ ? print STDERR $_ : print' %{name}.list 2> %{name}-http.list

#mdk menu entry
mkdir -p $RPM_BUILD_ROOT/%_menudir
cat > $RPM_BUILD_ROOT%_menudir/harddrake-ui <<EOF
?package(harddrake-ui):\
	needs="X11"\
	section="Configuration/Hardware"\
	title="HardDrake"\
	longtitle="Hardware Central Configuration/information tool"\
	command="/usr/sbin/harddrake2"\
	icon="harddrake.png"
EOF

cat > $RPM_BUILD_ROOT%_datadir/harddrake/convert <<EOF
#!/usr/bin/perl
use Storable;
 
my \$last_boot_config = "/etc/sysconfig/harddrake2/previous_hw";
 
my \$config = do \$last_boot_config;
store \$config, \$last_boot_config;
EOF

cat > $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/harddrake2 <<EOF
#!/bin/sh
exec /usr/share/harddrake/service_harddrake X11
EOF

cat > $RPM_BUILD_ROOT%_datadir/harddrake/confirm <<EOF
#!/usr/bin/perl
use lib qw(/usr/lib/libDrakX);
use interactive;

my \$in = interactive->vnew;
my \$res = \$in->ask_okcancel(\$ARGV[0], \$ARGV[1], 1);
\$in->exit(\$res);
EOF

chmod +x $RPM_BUILD_ROOT{%_datadir/harddrake/*,%_sysconfdir/X11/xinit.d/harddrake2}

%find_lang libDrakX
cat libDrakX.lang >> %name.list

%clean
rm -rf $RPM_BUILD_ROOT

%post
[[ ! -e %_sbindir/kbdconfig ]] && %__ln_s -f keyboarddrake %_sbindir/kbdconfig
[[ ! -e %_sbindir/mouseconfig ]] && %__ln_s -f mousedrake %_sbindir/mouseconfig
[[ ! -e %_bindir/printtool ]] && %__ln_s -f ../sbin/printerdrake %_bindir/printtool
:

%postun
for i in %_sbindir/kbdconfig %_sbindir/mouseconfig %_bindir/printtool;do
    [[ -L $i ]] && %__rm -f $i
done

%post http
%_post_service drakxtools_http

%preun http
%_preun_service drakxtools_http

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

%files newt -f %name.list
%defattr(-,root,root)
%config(noreplace) /etc/security/fileshare.conf
%doc diskdrake/diskdrake.html
%attr(4755,root,root) %_sbindir/fileshareset

%files -f %{name}-gtk.list
%defattr(-,root,root)
%config(noreplace) %_sysconfdir/pam.d/net_monitor
%config(noreplace) %_sysconfdir/security/console.apps/net_monitor
/usr/X11R6/bin/*

%files -n harddrake
%defattr(-,root,root)
%config(noreplace) %_initrddir/harddrake
%dir /etc/sysconfig/harddrake2/
%config(noreplace) /etc/sysconfig/harddrake2/previous_hw
%_datadir/harddrake/*
#%_sysconfdir/X11/xinit.d/harddrake2

%files -n harddrake-ui
%defattr(-,root,root)
%_sbindir/harddrake2
%_datadir/pixmaps/harddrake2
%_menudir/harddrake-ui
%_iconsdir/large/harddrake.png
%_iconsdir/mini/harddrake.png
%_iconsdir/harddrake.png


%files http -f %{name}-http.list
%defattr(-,root,root)
%dir %_sysconfdir/drakxtools_http
%config(noreplace) %_sysconfdir/pam.d/miniserv
%config(noreplace) %_sysconfdir/init.d/drakxtools_http
%config(noreplace) %_sysconfdir/drakxtools_http/conf
%config(noreplace) %_sysconfdir/drakxtools_http/authorised_progs
%config(noreplace) %_sysconfdir/logrotate.d/drakxtools-http

%changelog 
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
		* read & parse modules.conf only when configuring the
            module, not on each click in the tree
		* don't display ranges, we cannot really know when a range
       	  is needed and so display them in wrong cases (kill code,
       	  enable us to simplify modparm::parameters after

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
