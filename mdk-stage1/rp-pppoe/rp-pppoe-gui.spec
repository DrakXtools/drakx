Summary: PPP Over Ethernet (xDSL support)
Name: rp-pppoe-gui
Version: 3.0
%if %(%{expand:test %{_vendor} != mandriva ; echo $?})
Release: 1mdk
%else
Release: 1
%endif
Copyright: GPL
Group: System Environment/Daemons
Source: http://www.roaringpenguin.com/pppoe/rp-pppoe-3.0.tar.gz
Url: http://www.roaringpenguin.com/pppoe/
Packager: David F. Skoll <dfs@roaringpenguin.com>
BuildRoot: /tmp/pppoe-build
Vendor: Roaring Penguin Software Inc.
Requires: ppp >= 2.3.7
Requires: rp-pppoe >= 3.0

%description
This is a graphical wrapper around the rp-pppoe PPPoE client.  PPPoE is
a protocol used by many DSL Internet Service Providers.

%prep
umask 022
mkdir -p $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT
rm -rf $RPM_BUILD_ROOT/rp-pppoe-%{version}
zcat $RPM_SOURCE_DIR/rp-pppoe-%{version}.tar.gz | tar xvf -
cd $RPM_BUILD_ROOT/rp-pppoe-%{version}/src
./configure --mandir=%{_mandir}

%build
cd $RPM_BUILD_ROOT/rp-pppoe-%{version}/gui
make

%install
cd $RPM_BUILD_ROOT/rp-pppoe-%{version}/gui
make install RPM_INSTALL_ROOT=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%post
# Install entry in KDE menu
if test -n "$KDEDIR" ; then
    mkdir -p "$KDEDIR/share/applnk/Internet"
    cat <<EOF > "$KDEDIR/share/applnk/Internet/tkpppoe.kdelnk"
# KDE Config File
[KDE Desktop Entry]
Name=TkPPPoE
Comment=Start/Stop ADSL connections
Exec=tkpppoe
Terminal=0
Type=Application
EOF
fi

# Install entry in GNOME menus
GNOMEDIR=`gnome-config --datadir 2>/dev/null`
if test -n "$GNOMEDIR" ; then
    mkdir -p "$GNOMEDIR/gnome/apps/Internet"
cat <<EOF > "$GNOMEDIR/gnome/apps/Internet/tkpppoe.desktop"
[Desktop Entry]
Name=TkPPPoE
Comment=Start/Stop ADSL connections
Exec=tkpppoe
Terminal=0
Type=Application
EOF
fi

%postun
# Remove KDE menu entry
if test -n "$KDEDIR" ; then
    rm -f "$KDEDIR/share/applnk/Internet/tkpppoe.kdelnk"
fi

# Remove GNOME menu entry
GNOMEDIR=`gnome-config --datadir 2>/dev/null`
if test -n "$GNOMEDIR" ; then
    rm -f "$GNOMEDIR/gnome/apps/Internet/tkpppoe.desktop"
fi

%files
%defattr(-,root,root)
%dir /etc/ppp/rp-pppoe-gui
/usr/sbin/pppoe-wrapper
/usr/bin/tkpppoe
%{_mandir}/man1/tkpppoe.1*
%{_mandir}/man1/pppoe-wrapper.1*
/usr/share/rp-pppoe-gui/tkpppoe.html
/usr/share/rp-pppoe-gui/mainwin-busy.png
/usr/share/rp-pppoe-gui/mainwin-nonroot.png
/usr/share/rp-pppoe-gui/mainwin.png
/usr/share/rp-pppoe-gui/props-advanced.png
/usr/share/rp-pppoe-gui/props-basic.png
/usr/share/rp-pppoe-gui/props-nic.png
/usr/share/rp-pppoe-gui/props-options.png
