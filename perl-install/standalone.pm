package standalone; # $Id$

use c;

$::isStandalone = 1;

$ENV{SHARE_PATH} ||= "/usr/share";

c::setlocale();
c::bindtextdomain('libDrakX', "/usr/share/locale");



################################################################################
package pkgs_interactive;

sub interactive::do_pkgs {
    my ($in) = @_;
    bless { in => $in }, 'pkgs_interactive';
}

sub install {
    my ($o, @l) = @_;
    $o->{in}->suspend;
    my $wait = $o->{in}->wait_message('', _("Installing packages..."));
    standalone::explanations("installed packages @l");
    my $ret = system('urpmi', '--allow-medium-change', '--auto', '--best-output', @l) == 0;
    undef $wait;
    $o->{in}->resume;
    $ret;
}

sub what_provides {
    my ($o, $name) = @_;
    my ($what) = split '\n', `urpmq '$name' 2>/dev/null`;
    split '\|', $what;
}

sub is_installed {
    my ($o, @l) = @_;
    system('rpm', '-q', @l) == 0;
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

@common_functs = qw(renamef linkf symlinkf output substInFile mkdir_p rm_rf cp_af touch setVarsInSh setVarsInCsh update_gnomekderc);
@builtin_functs = qw(chmod chown unlink link symlink rename system);
@drakx_modules = qw(Xconfig Xconfigurator Xconfigurator_consts any bootloader bootlook c class_discard commands crypto detect_devices devices diskdrake diskdrake::hd_gtk diskdrake::interactive diskdrake::removable diskdrake::removable_gtk diskdrake::smbnfs_gtk fs fsedit http keyboard lang log loopback lvm modparm modules mouse my_gtk network network::adsl network::ethernet network::isdn_consts network::isdn network::modem network::netconnect network::network network::nfs network::smb network::tools partition_table partition_table_bsd partition_table::dos partition_table::empty partition_table::gpt partition_table::mac partition_table::raw partition_table::sun printer printerdrake proxy raid run_program scanner services steps swap timezone tinyfirewall);


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

sub setVarsInCsh {
    explanations "modified file $_[0]";
    goto &MDK::Common::System::setVarsInCsh;
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
