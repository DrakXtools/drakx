Name:		meta-task
Summary:	Meta task listing packages by group
Version:	2012.0
Release:	3
License:	GPLv2+
Group:		System/Configuration/Other
Source0:	rpmsrate-raw
Source1:	check-rpmsrate
Source2:	compssUsers.pl
Source3:	prefer.vendor.list
Source4:	README
BuildArch:	noarch
BuildRequires:	drakxtools-backend

# https://qa.mandriva.com/show_bug.cgi?id=64814 (texlive update crashes system)
# Need to remove these packages first, because texlive packages were reworked
# to match upstream layout, and this causes rpm/urpmi to use several GB of
# memory, but by removing the large monolithic packages and restarting urpmi
# it updates only the texlive package, and uses far less memory.
# FIXME this probably should be in a proper "cleanup" package that also causes
# urpmi to restart.
# So we can clean these packages
Obsoletes:	texlive-doc texlive-fontsextra texlive-source texlive-texmf

%description
prefer.vendor.list is used by urpmi, rpmdrake and installer to prefer some
packages when there is a choice.

"rpmsrate" and "compsUsers.pl" are used by installer and rpmdrake to choose
packages to install.

%build
cp %{SOURCE1} .
cp %{SOURCE4} .

%install
install -d %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE0} %{buildroot}%{_datadir}/%{name}
install -m644 %{SOURCE2} %{buildroot}%{_datadir}/%{name}
install -d %{buildroot}%{_sysconfdir}/urpmi
install -m644 %{SOURCE3} %{buildroot}%{_sysconfdir}/urpmi

%check
ERR=`perl ./check-rpmsrate %{buildroot}%{_datadir}/%{name}/rpmsrate-raw 2>&1`
[ -z "$ERR" ]

%files
%doc README
%config(noreplace) %{_sysconfdir}/urpmi/prefer.vendor.list
%{_datadir}/%{name}
