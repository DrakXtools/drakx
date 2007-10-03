%define name meta-task
%define version 2008.0
%define release %mkrel 18

Summary: Meta task listing packages by group
Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Group: System/Configuration/Other
Source: rpmsrate-raw
Source2: compssUsers.pl
Source3: prefer.vendor.list
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
BuildArch: noarch

%description
prefer.vendor.list is used by urpmi, rpmdrake and installer to prefer some
packages when there is a choice.

"rpmsrate" and "compsUsers.pl" are used by installer and rpmdrake to choose
packages to install.

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE0} %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE2} %{buildroot}%{_datadir}/%{name}
install -d %{buildroot}%{_sysconfdir}/urpmi
install -m644 %{SOURCE3} %{buildroot}%{_sysconfdir}/urpmi

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%config(noreplace) %{_sysconfdir}/urpmi/prefer.vendor.list
%{_datadir}/%name


