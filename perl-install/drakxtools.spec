Summary: The drakxtools (XFdrake, diskdrake, keyboarddrake, mousedrake...)
Name:    drakxtools
Version: 9.3
Release: 16mdk
Url: http://www.mandrakelinux.com/en/drakx.php3
Source0: %name-%version.tar.bz2
License: GPL
Group: System/Configuration/Other
Requires: %{name}-newt = %version-%release, perl-Gtk2 >= 0.95-6mdk, /usr/X11R6/bin/xtest, font-tools, usermode >= 1.63-5mdk, perl-MDK-Common >= 1.1.10, gurpmi
Requires: foomatic-db-engine, mkbootdisk
Conflicts: drakconf < 9.3-21mdk
Conflicts: rpmdrake < 2.1-29mdk
Conflicts: mandrake_doc-drakxtools-en < 9.2, mandrake_doc-drakxtools-es < 9.2, mandrake_doc-drakxtools-fr < 9.2
BuildRequires: gettext, gtk+2-devel, ldetect-devel >= 0.5.1-2mdk, ncurses-devel, newt-devel, perl-devel >= 1:5.8.0-20mdk, libext2fs-devel, perl-MDK-Common-devel >= 1.1.8-3mdk
BuildRoot: %_tmppath/%name-buildroot
Provides: draksec
Obsoletes: draksec
%define _requires_exceptions perl(Net::FTP)\\|perl(Time::localtime)

%package newt
Summary: The drakxtools (XFdrake, diskdrake, keyboarddrake, mousedrake...)
Group: System/Configuration/Other
Requires: perl-base >= 1:5.8.0-20mdk, urpmi >= 4.4-23mdk, modutils >= 2.3.11, ldetect-lst >= 0.1.7-3mdk, usermode-consoleonly >= 1.44-4mdk, msec >= 0.38-5mdk
Requires: netprofile
Obsoletes: diskdrake kbdconfig mouseconfig printtool setuptool drakfloppy
Provides: diskdrake, kbdconfig mouseconfig printtool setuptool, drakfloppy = %version-%release
Provides: perl(Newt::Newt)
Provides: perl(network::isdn_consts)
%define _requires_exceptions perl(interactive::gtk)\\|perl(ugtk2)

%package http
Summary: The drakxtools via http
Group: System/Configuration/Other
Requires: %{name}-newt = %version-%release, perl-Net_SSLeay >= 1.22-1mdk, perl-Authen-PAM >= 0.14-1mdk, perl-CGI >= 2.91-1mdk
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

drakauth: configure authentification (LDAP/NIS/...)

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
%make CFLAGS="$RPM_OPT_FLAGS" rpcinfo-flushed
%make ddcprobe serial_probe 
%make

%install
rm -rf $RPM_BUILD_ROOT

%make PREFIX=$RPM_BUILD_ROOT install
mkdir -p $RPM_BUILD_ROOT/{%_initrddir,%_sysconfdir/{X11/xinit.d,sysconfig/harddrake2}}
touch $RPM_BUILD_ROOT/etc/sysconfig/harddrake2/previous_hw

mkdir -p $RPM_BUILD_ROOT%_sysconfdir/{pam.d,security/console.apps}
cp pam.net_monitor $RPM_BUILD_ROOT%_sysconfdir/pam.d/net_monitor
cp apps.net_monitor $RPM_BUILD_ROOT%_sysconfdir/security/console.apps/net_monitor

dirs1="usr/lib/libDrakX usr/share/libDrakX"
(cd $RPM_BUILD_ROOT ; find $dirs1 usr/bin usr/sbin ! -type d -printf "/%%p\n")|egrep -v 'bin/.*harddrake' > %{name}.list
(cd $RPM_BUILD_ROOT ; find $dirs1 -type d -printf "%%%%dir /%%p\n") >> %{name}.list

perl -ni -e '/drakbackup|drakfont|drakfloppy|gtk|icons|logdrake|net_monitor|pixmaps|printer|XFdrake/ ? print STDERR $_ : print' %{name}.list 2> %{name}-gtk.list
perl -ni -e '/http/ ? print STDERR $_ : print' %{name}.list 2> %{name}-http.list

#mdk menu entry
mkdir -p $RPM_BUILD_ROOT/%_menudir

cat > $RPM_BUILD_ROOT%_menudir/drakxtools-newt <<EOF
?package(drakxtools-newt):\
	needs="X11"\
	section="Configuration/Other"\
	title="LocaleDrake"\
	longtitle="Language configurator"\
	command="/usr/bin/localedrake"\

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
# temporary fix until we reenable this feature
rm -f $RPM_BUILD_ROOT%_sysconfdir/X11/xinit.d/harddrake2

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

%files newt -f %name.list
%defattr(-,root,root)
%config(noreplace) /etc/security/fileshare.conf
%_menudir/drakxtools-newt
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


%files http -f %{name}-http.list
%defattr(-,root,root)
%dir %_sysconfdir/drakxtools_http
%config(noreplace) %_sysconfdir/pam.d/miniserv
%config(noreplace) %_sysconfdir/init.d/drakxtools_http
%config(noreplace) %_sysconfdir/drakxtools_http/conf
%config(noreplace) %_sysconfdir/drakxtools_http/authorised_progs
%config(noreplace) %_sysconfdir/logrotate.d/drakxtools-http

%changelog
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
- drakconnect: fix sagem800 configuratio (poulpy)
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
  o add a separator below buttons on fredc request
  o really pack the two button sets at edges
  o try to have a better layout when embedded): let's have only one
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
  o fix user cron misbehavior (Keld J�rn Simonsen)
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

* Fri Mar 08 2002 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.7-92mdk
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

* Fri Sep 14 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.7-23mdk
- snapshot with latest XFdrake fixes.

* Fri Sep 14 2001 dam's <damien@mandrakesoft.com> 1.1.7-22mdk
- snapshot

* Thu Sep 13 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.7-21mdk
- fix Xinerama for Matrox cards (restore XFree86 4.1.0 without DRI).
- removed Modeline 1024x768 in 97.6 Hz which troubles XF4 a lot.

* Thu Sep 13 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.7-20mdk
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

* Thu Aug 30 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.7-11mdk
- new snapshot, mousedrake fixes again.

* Wed Aug 29 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.7-10mdk
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

* Wed Apr 25 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-101mdk
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

* Wed Apr 11 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-85mdk
- really fix printerdrake and snap.

* Wed Apr 11 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-84mdk
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

* Wed Mar 28 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-65mdk
- fixed wrong generation of second mouse support

* Wed Mar 28 2001 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-64mdk
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

* Thu Oct 05 2000 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-28mdk
- snapshot.

* Tue Oct 03 2000 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.5-27mdk
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

* Thu May 25 2000 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.1-8mdk
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

* Wed Apr 19 2000 Fran�ois Pons <fpons@mandrakesoft.com> 1.1.1-3mdk
- updated with CVS of DrakX.

* Fri Mar 31 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-2mdk
- obsoletes setuptool, link setuptool to drakxconf

* Fri Mar 31 2000 Pixel <pixel@mandrakesoft.com> 1.1.1-1mdk
- new version (added drakboot for lilo/grub, XFdrake -xf4 for XFree4)

* Sat Mar 25 2000 Pixel <pixel@mandrakesoft.com> 1.1-1mdk
- new group
- new version

* Wed Jan 12 2000 Fran�ois PONS <fpons@mandrakesoft.com>
- complete update with DrakX, small fixe on printerdrake again.

* Wed Jan 12 2000 Fran�ois PONS <fpons@mandrakesoft.com>
- corrected missing generic postscript and text driver for
  printderdrake.

* Wed Jan 12 2000 Fran�ois PONS <fpons@mandrakesoft.com>
- corrected bad resolution setting in printerdrake.

* Wed Jan 12 2000 Fran�ois PONS <fpons@mandrakesoft.com>
- fixed print on STDOUT in printerdrake.
- corrected printerdrake against not available drivers in gs.

* Mon Jan 10 2000 Pixel <pixel@mandrakesoft.com>
- new version (bis)
- printerdrake install rhs-printfilters via urpmi if needed

* Fri Jan 07 2000 Fran�ois PONS <fpons@mandrakesoft.com>
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
