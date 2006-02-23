%define name draklive-install
%define version 0.1
%define release %mkrel 2
%define iconname MandrivaOne-install-icon.png
%define imgname MandrivaOne-install.png

Summary:	Live installer
Name:		%{name}
Version:	%{version}
Release:	%{release}
Source0:	%{name}-%{version}.tar.bz2
License:	GPL
Group:		System/Configuration/Other
Url:		http://qa.mandriva.com/twiki/bin/view/Main/DrakLive
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-buildroot
BuildArch:      noarch

%description
This tool allows to install Mandriva from a running live system.

%prep
%setup -q

%build
%make -C po

%install
rm -rf $RPM_BUILD_ROOT

%makeinstall -C po

for d in %_datadir/nautilus/default-desktop %_datadir/apps/kdesktop/DesktopLinks; do
  install -D -m 0644 %name.desktop %buildroot/$d/%name.desktop
done
install -D -m 0755 %name %buildroot/%_datadir/%name/%name
install -m 0644 install_interactive.pm %buildroot/%_datadir/%name

install -d -m 0755 %buildroot/%_sbindir
cat > %buildroot/%_sbindir/%name <<EOF
#!/bin/sh
cd %_datadir/%name
./%name
EOF
chmod 0755 %buildroot/%_sbindir/%name

mkdir -p %buildroot{%_miconsdir,%_iconsdir,%_liconsdir,%_menudir,%_datadir/libDrakX/pixmaps/}
install theme/IC-installone-48.png %buildroot%_liconsdir/%iconname
install theme/IC-installone-32.png %buildroot%_iconsdir/%iconname
install theme/IC-installone-32.png %buildroot%_miconsdir/%iconname
install theme/IM-INSTALLCDONE2.png %buildroot%_datadir/libDrakX/pixmaps/%imgname

%find_lang %name

%clean
rm -rf $RPM_BUILD_ROOT

%post
%update_menus

%postun
%clean_menus

%files -f %name.lang
%defattr(-,root,root)
%_sbindir/%name
%_datadir/%name
%_datadir/apps/kdesktop/DesktopLinks/*.desktop
%_datadir/nautilus/default-desktop/*.desktop
%_iconsdir/%iconname
%_liconsdir/%iconname
%_miconsdir/%iconname
%_datadir/libDrakX/pixmaps/%imgname

%changelog
* Thu Feb 23 2006 Olivier Blin <oblin@mandriva.com> 0.1-2mdk
- update po files

* Fri Dec 16 2005 Olivier Blin <oblin@mandriva.com> 0.1-1mdk
- initial release
