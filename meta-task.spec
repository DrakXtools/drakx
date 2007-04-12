%define name meta-task
%define version 2007.1
%define release %mkrel 3

Summary: Meta task listing packages by group
Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Group: System/Configuration/Other
Source: rpmsrate-raw
Source2: compssUsers.pl
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
BuildArch: noarch

%description
"rpmsrate" and "compsUsers.pl" are used by installer and rpmdrake to choose
packages to install.

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE0} %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE2} %{buildroot}%{_datadir}/%{name}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%{_datadir}/%name


