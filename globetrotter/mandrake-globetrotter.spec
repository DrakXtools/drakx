Summary: Mandrakelinux Globetrotter tools
Name:    mandrake-globetrotter
Version: 10
Release: 1mdk
Url: http://www.mandrakelinux.com/en/drakx.php3
Source0: %name-%version.tar.bz2
License: GPL
Group: System/Configuration/Other
Requires: drakxtools netprofile
BuildRoot: %_tmppath/%name-buildroot


%description
Contains many Mandrakelinux tools needed for Mandrakelinux Globetrotter.

%prep
%setup -q

%build
%make

%install
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/{%_initrddir,%_datadir/harddrake}
%makeinstall_std PREFIX=$RPM_BUILD_ROOT
install -m 755 hwprofile $RPM_BUILD_ROOT/%_datadir/harddrake/hwprofile

%find_lang libDrakX2


%clean
rm -rf $RPM_BUILD_ROOT


%files -f libDrakX2.lang
%defattr(-,root,root)
%_datadir/harddrake/*
%_sbindir/*
/usr/lib/libDrakX/*pm
/usr/share/libDrakX/pixmaps/lang*

%changelog
* Wed Apr 28 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 10-1mdk
- initial release
