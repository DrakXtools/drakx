package standalone; # $Id$

use c;
use strict;
use common;
use Config;

#- for sanity (if a use standalone is made during install, MANY problems will happen)
if ($::isInstall) {
    require 'log.pm';
    log::l('ERROR: use standalone made during install :-(');
    require common;
    log::l('backtrace: ' . common::backtrace());
}
$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

c::setlocale();
c::bindtextdomain('libDrakX', "/usr/share/locale");

$::license = N("This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
");

my $progname = basename $0;
print "Running $progname\n";

my %usages = (
	      'draksec' => N(" [OPTIONS]...
	      --debug         print debugging information"),
	      'drakxtv' => "[--no-guess]",
	      'drakupdate_fstab' => " [--add | --del] <device>\n",
	      'keyboardrake' => N("[keyboard]"),
	      'printerdrake' => N(" [--skiptest] [--cups] [--lprng] [--lpd] [--pdq]"),
	      'rpmdrake' => N("[OPTION]...
  --no-confirmation      don't ask first confirmation question in MandrakeUpdate mode
  --no-verify-rpm        don't verify packages signatures
  --changelog-first      display changelog before filelist in the description window
  --merge-all-rpmnew     propose to merge all .rpmnew/.rpmsave files found"),
	      'XFdrake' => N(" [everything]
       XFdrake [--noauto] monitor
       XFdrake resolution"),
	      );

$usages{$_} = $usages{rpmdrake} foreach (qw(rpmdrake-remove MandrakeUpdate));
$usages{Xdrakres} = $usages{XFdrake};


my ($i, @new_ARGV);
foreach my $opt (@ARGV) {
    $i++;
    if ($opt eq '--help' || $opt eq '-h') {
	version();
	print STDERR N("\nUsage: %s  [--auto] [--beginner] [--expert] [-h|--help] [--noauto] [--testing] [-v|--version] ", $progname),  if_($usages{$progname}, $usages{$progname}), "\n";
#    print N("\nUsage: "), $::usage, "\n" if $::usage;
	exit(0);
    } elsif ($opt eq '--version' || $opt eq '-v') {
	version();
	exit(0);
    } elsif ($opt eq '--embedded') {
	(undef, $::XID, $::CCPID) = splice @ARGV, ($i-1), 3;
	$::isEmbedded = 1;
    } elsif ($opt eq '--expert') {
	$::expert = 1;
    } elsif ($opt eq '--noauto') {
	$::noauto = /-noauto/;
    } elsif ($opt eq '--auto') {
	$::auto = 1;
    } elsif ($opt eq '--testing') {
	$::testing = 1;
    } elsif ($opt eq '--beginner') {
	$::expert = 0;
    } else {
	push @new_ARGV, $opt;
    }
}

@ARGV = @new_ARGV;


sub version {
    print STDERR "Drakxtools version 9.1.0
Copyright (C) 1999-2002 MandrakeSoft by <install\@mandrakesoft.com>
",  $::license, "\n";
}

################################################################################
package pkgs_interactive;

use run_program;
use common;


sub interactive::do_pkgs {
    my ($in) = @_;
    bless { in => $in }, 'pkgs_interactive';
}

sub install {
    my ($o, @l) = @_;

    return 1 if is_installed($o, @l);

    my $wait;
    if ($o->{in}->isa('interactive::newt')) {
	$o->{in}->suspend;
    } else {
	$wait = $o->{in}->wait_message('', N("Installing packages..."));
    }
    standalone::explanations("installed packages @l");
    my $ret = system('urpmi', '--allow-medium-change', '--auto', '--best-output', @l) == 0;

    if ($o->{in}->isa('interactive::newt')) {
	$o->{in}->resume;
    } else {
	undef $wait;
    }
    $ret;
}

sub ensure_is_installed {
    my ($o, $pkg, $file, $auto) = @_;

    if (! -e $file) {
	$o->{in}->ask_okcancel('', N("The package %s needs to be installed. Do you want to install it?", $pkg), 1) 
	  or return if !$auto;
	$o->{in}->do_pkgs->install($pkg);
    }
    if (! -e $file) {
	$o->{in}->ask_warn('', N("Mandatory package %s is missing", $pkg));
	return;
    }
    1;
}

sub what_provides {
    my ($o, $name) = @_;
    my ($what) = split '\n', `urpmq '$name' 2>/dev/null`;
    split '\|', $what;
}

sub is_installed {
    my ($o, @l) = @_;
    run_program::run('rpm', '>', '/dev/null', '-q', @l);
}

sub are_installed {
    my ($o, @l) = @_;
    my @l2;
    run_program::run('rpm', '>', \@l2, '-q', '--qf', "%{name}\n", @l);
    intersection(\@l, [ map { chomp_($_) } @l2 ]);
}

sub remove {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    standalone::explanations("removed packages @l");
    my $ret = system('rpm', '-e', @l) == 0;
    $o->{in}->resume;
    $ret;
}

sub remove_nodeps {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    standalone::explanations("removed (with --nodeps) packages @l");
    my $ret = system('rpm', '-e', '--nodeps', @l) == 0;
    $o->{in}->resume;
    $ret;
}
################################################################################


package standalone;

#- stuff will go to special /var/log/explanations file
my $standalone_name;
sub explanations { c::syslog(c::LOG_INFO()|c::LOG_LOCAL1(), "@_") }

our @common_functs = qw(renamef linkf symlinkf output substInFile mkdir_p rm_rf cp_af touch setVarsInSh setExportedVarsInSh setExportedVarsInCsh update_gnomekderc);
our @builtin_functs = qw(chmod chown unlink link symlink rename system);
our @drakx_modules = qw(Xconfig::card Xconfig::default Xconfig::main Xconfig::monitor Xconfig::parse Xconfig::proprietary Xconfig::resolution_and_depth Xconfig::screen Xconfig::test Xconfig::various Xconfig::xfree Xconfig::xfree3 Xconfig::xfree4 Xconfig::xfreeX any bootloader bootlook c class_discard commands crypto detect_devices devices diskdrake diskdrake::hd_gtk diskdrake::interactive diskdrake::removable diskdrake::removable_gtk diskdrake::smbnfs_gtk fs fsedit http keyboard lang log loopback lvm modparm modules mouse my_gtk network network::adsl network::ethernet network::isdn_consts network::isdn network::modem network::netconnect network::network network::nfs network::smb network::tools partition_table partition_table_bsd partition_table::dos partition_table::empty partition_table::gpt partition_table::mac partition_table::raw partition_table::sun printer printerdrake proxy raid run_program scanner services steps swap timezone network::drakfirewall network::shorewall);

$SIG{SEGV} = sub { my $progname = $0; $progname =~ s|.*/||; exec("drakbug --incident $progname") };

sub import {
    ($standalone_name = $0) =~ s|.*/||;
    c::openlog("$standalone_name"."[$$]");
    explanations('### Program is starting ###');

    eval "*MDK::Common::$_ = *$_" foreach @common_functs;

    foreach my $f (@builtin_functs) {
	eval "*$_"."::$f = *$f" foreach @drakx_modules;
	eval "*".caller()."::$f = *$f";
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
    my $retval = MDK::Common::File::cp_af @_;
    my $dest = pop @_;
    explanations "copied recursively @_ to $dest";
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
    my $retval = CORE::chmod @_;
    my $mode = shift @_;
    explanations sprintf("changed mode of %s to %o", $_, $mode) foreach @_;
    return $retval;
}

sub chown {
    my $retval = CORE::chown @_;
    my $uid = shift @_;
    my $gid = shift @_;
    explanations sprintf("changed owner of $_ to $uid.$gid") foreach @_;
    return $retval;
}

sub unlink {
    explanations "removed files/directories @_";
    CORE::unlink @_;
}

sub link {
    explanations "hard linked file $_[0] to $_[1]";
    CORE::link $_[0], $_[1];
}

sub symlink {
    explanations "symlinked file $_[0] to $_[1]";
    CORE::symlink $_[0], $_[1];
}

sub rename {
    explanations "renamed file $_[0] to $_[1]";
    CORE::rename $_[0], $_[1];
}

sub system {
    explanations "launched command: @_";
    CORE::system @_;
}

1;
