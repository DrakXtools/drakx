%define name meta-task
%define version 2012.0
%define release %mkrel 1

Summary: Meta task listing packages by group
Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Group: System/Configuration/Other
Source: rpmsrate-raw
Source1: check-rpmsrate
Source2: compssUsers.pl
Source3: prefer.vendor.list
Source4: README
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
BuildArch: noarch
BuildRequires: drakxtools-backend

# https://qa.mandriva.com/show_bug.cgi?id=64814 (texlive update crashes system)
# Need to remove these packages first, because texlive packages were reworked
# to match upstream layout, and this causes rpm/urpmi to use several GB of
# memory, but by removing the large monolithic packages and restarting urpmi
# it updates only the texlive package, and uses far less memory.
# FIXME this probably should be in a proper "cleanup" package that also causes
# urpmi to restart.
Conflicts:	texlive-doc, texlive-fontsextra, texlive-source, texlive-texmf

%description
prefer.vendor.list is used by urpmi, rpmdrake and installer to prefer some
packages when there is a choice.

"rpmsrate" and "compsUsers.pl" are used by installer and rpmdrake to choose
packages to install.

%build
cp %{SOURCE1} .
cp %{SOURCE4} .

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE0} %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE2} %{buildroot}%{_datadir}/%{name}
install -d %{buildroot}%{_sysconfdir}/urpmi
install -m644 %{SOURCE3} %{buildroot}%{_sysconfdir}/urpmi

%check
ERR=`./check-rpmsrate %{buildroot}%{_datadir}/%{name}/rpmsrate-raw 2>&1`
[ -z "$ERR" ]

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%doc README
%config(noreplace) %{_sysconfdir}/urpmi/prefer.vendor.list
%{_datadir}/%{name}
