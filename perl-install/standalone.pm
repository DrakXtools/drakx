package standalone; # $Id$

use c;
use strict;
use common qw(N N_ if_ backtrace);
use Config;

BEGIN { unshift @::textdomains, 'libDrakX-standalone' }

#- for sanity (if a use standalone is made during install, MANY problems will happen)
require 'log.pm'; #- "require log" causes some pb, perl thinking that "log" is the log() function
if ($::isInstall) {
    log::l('ERROR: use standalone made during install :-(');
    log::l('backtrace: ' . backtrace());
}
$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

eval { #- allow standalone.pm to be used in drakxtools-backend without perl-Locale-gettext
    c::init_setlocale();
    Locale::gettext::bindtextdomain('libDrakX', "/usr/share/locale");
};

$::license = N_("This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
");

my $progname = common::basename($0);

my %usages = (
           'diskdrake' => "[--{" . join(",", qw(hd nfs smb dav removable fileshare)) . "}]",
           'drakbackup' => N_("[--config-info] [--daemon] [--debug] [--default] [--show-conf]
Backup and Restore application

--default             : save default directories.
--debug               : show all debug messages.
--show-conf           : list of files or directories to backup.
--config-info         : explain configuration file options (for non-X users).
--daemon              : use daemon configuration. 
--help                : show this message.
--version             : show version number.
"),

           'drakboot' => N_("[--boot]
OPTIONS:
  --boot            - enable to configure boot loader
default mode: offer to configure autologin feature"),
           'drakbug' => N_("[OPTIONS] [PROGRAM_NAME]

OPTIONS:
  --help            - print this help message.
  --report          - program should be one of Mandriva Linux tools
  --incident        - program should be one of Mandriva Linux tools"),
           'drakconnect' => N_("[--add]
  --add             - \"add a network interface\" wizard
  --del             - \"delete a network interface\" wizard
  --skip-wizard     - manage connections
  --internet        - configure internet
  --wizard          - like --add"),
           'drakfont' => N_("
Font Importation and monitoring application

OPTIONS:
--windows_import : import from all available windows partitions.
--xls_fonts      : show all fonts that already exist from xls
--install        : accept any font file and any directory.
--uninstall      : uninstall any font or any directory of font.
--replace        : replace all font if already exist
--application    : 0 none application.
                 : 1 all application available supported.
                 : name_of_application like  so for staroffice 
                 : and gs for ghostscript for only this one."),
           'draksec' => "[--debug]
--debug: print debugging information",
           'drakTermServ' => N_("[OPTIONS]...
Mandriva Linux Terminal Server Configurator
--enable         : enable MTS
--disable        : disable MTS
--start          : start MTS
--stop           : stop MTS
--adduser        : add an existing system user to MTS (requires username)
--deluser        : delete an existing system user from MTS (requires username)
--addclient      : add a client machine to MTS (requires MAC address, IP, nbi image name)
--delclient      : delete a client machine from MTS (requires MAC address, IP, nbi image name)"),
	      'drakxtv' => "[--no-guess]",
	      'drakupdate_fstab' => " [--add | --del] <device>\n",
	      'keyboardrake' => N_("[keyboard]"),
           'logdrake' => N_("[--file=myfile] [--word=myword] [--explain=regexp] [--alert]"),
           'net_monitor' => N_("[OPTIONS]
Network & Internet connection and monitoring application

--defaultintf interface : show this interface by default
--connect : connect to internet if not already connected
--disconnect : disconnect to internet if already connected
--force : used with (dis)connect : force (dis)connection.
--status : returns 1 if connected 0 otherwise, then exit.
--quiet : do not be interactive. To be used with (dis)connect."),
	      'printerdrake' => " [--skiptest] [--cups] [--lprng] [--lpd] [--pdq]",
	      'rpmdrake' => N_("[OPTION]...
  --no-confirmation      do not ask first confirmation question in Mandriva Update mode
  --no-verify-rpm        do not verify packages signatures
  --changelog-first      display changelog before filelist in the description window
  --merge-all-rpmnew     propose to merge all .rpmnew/.rpmsave files found"),
           'scannerdrake' => N_("[--manual] [--device=dev] [--update-sane=sane_source_dir] [--update-usbtable] [--dynamic=dev]"),
	      'XFdrake' => N_(" [everything]
       XFdrake [--noauto] monitor
       XFdrake resolution"),
	      );

$usages{$_} = $usages{rpmdrake} foreach qw(rpmdrake-remove MandrivaUpdate);
$usages{Xdrakres} = $usages{XFdrake};


sub exit {
    explanations('### Program is exiting ###');
    CORE::exit(@_);
}

sub __exit {
    explanations('### Program is exiting ###');
    c::_exit(@_);
}


sub real_version {
    return "VER"; # version automatically set from Makefile
}

sub version() {
    print 'Drakxtools version ' . real_version() . '
Copyright (C) 1999-2008 Mandriva by <install@mandriva.com>
',  $::license, "\n";
}

if (!$::no_global_argv_parsing) {
my ($i, @new_ARGV);
foreach (@ARGV) {
    $i++;
    if (/^-(-help|h)$/) {
	version();
	print N("\nUsage: %s  [--auto] [--beginner] [--expert] [-h|--help] [--noauto] [--testing] [-v|--version] ", $progname),
       if_($usages{$progname}, common::translate($usages{$progname})), "\n";
#    print N("\nUsage: "), $::usage, "\n" if $::usage;
	CORE::exit(0);
    } elsif (/^-(-version|v)$/) {
	version();
	CORE::exit(0);
    } elsif (/^--embedded$/) {
	$::XID = splice @ARGV, $i, 1;
	$::isEmbedded = 1;
    } elsif (/^--expert$/) {
	$::expert = 1;
    } elsif (/^--noauto$/) {
	$::noauto = /-noauto/;
    } elsif (/^--auto$/) {
	$::auto = 1;
    } elsif (/^--testing$/) {
	$::testing = 1;
    } elsif (/^--beginner$/) {
	$::expert = 0;
    } else {
	push @new_ARGV, $_;
    }
}

@ARGV = @new_ARGV;
}

################################################################################

#- stuff will go to special /var/log/explanations file
my $standalone_name;
sub explanations { log::explanations("@_") }

our @common_functs = qw(renamef linkf symlinkf output substInFile mkdir_p rm_rf cp_af cp_afx touch setVarsInSh setExportedVarsInSh setExportedVarsInCsh update_gnomekderc);
our @builtin_functs = qw(chmod chown __exit exit unlink link symlink rename system);
our @drakx_modules = qw(Xconfig::card Xconfig::default Xconfig::main Xconfig::monitor Xconfig::parse Xconfig::proprietary Xconfig::resolution_and_depth Xconfig::screen Xconfig::test Xconfig::various Xconfig::xfree any bootloader bootlook c commands crypto detect_devices devices diskdrake diskdrake::hd_gtk diskdrake::interactive diskdrake::removable diskdrake::removable_gtk diskdrake::smbnfs_gtk fs fsedit http keyboard lang log loopback lvm modules::parameters modules mouse my_gtk network network::adsl network::ethernet network::connection network::isdn_consts network::isdn network::modem network::netconnect network::network fs::remote::nfs fs::remote::smb network::tools partition_table partition_table_bsd partition_table::dos partition_table::empty partition_table::gpt partition_table::mac partition_table::raw partition_table::sun printer printerdrake proxy raid run_program scanner services steps swap timezone network::drakfirewall network::shorewall);

sub bug_handler {
    my ($error, $is_signal) = @_;

    # exceptions in eval are OK:
    return if $error && $^S ne '0' && !$is_signal;

    # exceptions with "\n" are normal ways to quit:
    if (!$is_signal && eval { $error eq MDK::Common::String::formatError($error) }) {
        warn $error;
        exit(255);
    }

    # we want the full backtrace:
    $error .= "\n" if $is_signal;
    $error .= common::backtrace() if $error;

    my $progname = $0;

    # do not loop if drakbug crashes and do not complain about wizcancel:
    if ($progname =~ /drakbug/ || $error =~ /wizcancel/ || !-x '/usr/bin/drakbug') {
    	warn $error;
    	exit(1);
    }
    $progname =~ s|.*/||;
    system('drakbug',  if_($error, '--error', $error), '--incident', $progname);
    c::_exit(1);
}

if (!$ENV{DISABLE_DRAKBUG}) {
    $SIG{SEGV} = sub { bug_handler(@_, 1) };
    $SIG{__DIE__} = \&bug_handler;
}

sub import() {
    ($standalone_name = $0) =~ s|.*/||;
    c::openlog($standalone_name . "[$$]");
    explanations('### Program is starting ###');

    eval "*common::$_ = *$_" foreach @common_functs;

    foreach my $f (@builtin_functs) {
	eval "*$_" . "::$f = *$f" foreach @drakx_modules;
	eval "*" . caller() . "::$f = *$f";
    }
}


sub renamef {
    explanations "moved file $_[0] to $_[1]";
    goto &MDK::Common::File::renamef;
}

sub linkf {
    explanations "hard linked file $_[0] to $_[1]";
    goto &MDK::Common::File::linkf;
}

sub symlinkf {
    explanations "symlinked file $_[0] to $_[1]";
    goto &MDK::Common::File::symlinkf;
}

sub output {
    explanations "created file $_[0]";
    goto &MDK::Common::File::output;
}

sub substInFile(&@) {
    explanations "modified file $_[1]";
    goto &MDK::Common::File::substInFile;
}

sub mkdir_p {
    explanations "created directory $_[0] (and parents if necessary)";
    goto &MDK::Common::File::mkdir_p;
}

sub rm_rf {
    explanations "removed files/directories (recursively) @_";
    goto &MDK::Common::File::rm_rf;
}

sub cp_af {
    my $retval = MDK::Common::File::cp_af(@_);
    my $dest = pop @_;
    explanations "copied recursively @_ to $dest";
    return $retval;
}

sub cp_afx {
    my $retval = MDK::Common::File::cp_afx(@_);
    my $dest = pop @_;
    explanations "copied recursively @_ to $dest, staying on same partition";
    return $retval;
}

sub touch {
    explanations "touched file @_";
    goto &MDK::Common::File::touch;
}

sub setVarsInSh {
    explanations "modified file $_[0]";
    goto &MDK::Common::System::setVarsInSh;
}

sub setExportedVarsInSh {
    explanations "modified file $_[0]";
    goto &MDK::Common::System::setExportedVarsInSh;
}

sub setExportedVarsInCsh {
    explanations "modified file $_[0]";
    goto &MDK::Common::System::setExportedVarsInCsh;
}

sub update_gnomekderc {
    explanations "modified file $_[0]";
    goto &MDK::Common::System::update_gnomekderc;
}


sub chmod {
    my $retval = CORE::chmod(@_);
    my $mode = shift @_;
    explanations sprintf("changed mode of %s to %o", $_, $mode) foreach @_;
    return $retval;
}

sub chown {
    my $retval = CORE::chown(@_);
    my $uid = shift @_;
    my $gid = shift @_;
    explanations sprintf("changed owner of $_ to $uid.$gid") foreach @_;
    return $retval;
}

sub unlink {
    explanations "removed files/directories @_";
    CORE::unlink(@_);
}

sub link {
    explanations "hard linked file $_[0] to $_[1]";
    CORE::link($_[0], $_[1]);
}

sub symlink {
    explanations "symlinked file $_[0] to $_[1]";
    CORE::symlink($_[0], $_[1]);
}

sub rename {
    explanations "renamed file $_[0] to $_[1]" if -r $_[0];
    CORE::rename($_[0], $_[1]);
}

sub system {
    explanations "launched command: @_";
    CORE::system(@_);
}

1;
