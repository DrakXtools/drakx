package security::help;
# !! THIS FILE WAS AUTO-GENERATED BY draksec_help.py !!
# !! DO NOT MODIFY HERE, MODIFY IN THE *MSEC* CVS !!

use strict;
use common;

our %help = (

'accept_bogus_error_responses' => N("Arguments: (arg)

Accept/Refuse bogus IPv4 error messages."),

'accept_broadcasted_icmp_echo' => N("Arguments: (arg)

 Accept/Refuse broadcasted icmp echo."),

'accept_icmp_echo' => N("Arguments: (arg)

 Accept/Refuse icmp echo."),

'allow_autologin' => N("Arguments: (arg)

Allow/Forbid autologin."),

'allow_issues' => N("Arguments: (arg)

If \fIarg\fP = ALL allow /etc/issue and /etc/issue.net to exist. If \fIarg\fP = NONE no issues are
allowed else only /etc/issue is allowed."),

'allow_reboot' => N("Arguments: (arg)

Allow/Forbid reboot by the console user."),

'allow_remote_root_login' => N("Arguments: (arg)

Allow/Forbid remote root login."),

'allow_root_login' => N("Arguments: (arg)

Allow/Forbid direct root login."),

'allow_user_list' => N("Arguments: (arg)

Allow/Forbid the list of users on the system on display managers (kdm and gdm)."),

'allow_x_connections' => N("Arguments: (arg, listen_tcp=None)

Allow/Forbid X connections. First arg specifies what is done
on the client side: ALL (all connections are allowed), LOCAL (only
local connection) and NONE (no connection)."),

'allow_xserver_to_listen' => N("Arguments: (arg)

The argument specifies if clients are authorized to connect
to the X server on the tcp port 6000 or not."),

'authorize_services' => N("Arguments: (arg)

Authorize all services controlled by tcp_wrappers (see hosts.deny(5)) if \fIarg\fP = ALL. Only local ones
if \fIarg\fP = LOCAL and none if \fIarg\fP = NONE. To authorize the services you need, use /etc/hosts.allow
(see hosts.allow(5))."),

'create_server_link' => N("Arguments: ()

If SERVER_LEVEL (or SECURE_LEVEL if absent) is greater than 3
in /etc/security/msec/security.conf, creates the symlink /etc/security/msec/server
to point to /etc/security/msec/server.<SERVER_LEVEL>. The /etc/security/msec/server
is used by chkconfig --add to decide to add a service if it is present in the file
during the installation of packages."),

'enable_at_crontab' => N("Arguments: (arg)

Enable/Disable crontab and at for users. Put allowed users in /etc/cron.allow and /etc/at.allow
(see man at(1) and crontab(1))."),

'enable_console_log' => N("Arguments: (arg, expr='*.*', dev='tty12')

Enable/Disable syslog reports to console 12. \fIexpr\fP is the
expression describing what to log (see syslog.conf(5) for more details) and
dev the device to report the log."),

'enable_dns_spoofing_protection' => N("Arguments: (arg, alert=1)

Enable/Disable name resolution spoofing protection.  If
\fIalert\fP is true, also reports to syslog."),

'enable_ip_spoofing_protection' => N("Arguments: (arg, alert=1)

Enable/Disable IP spoofing protection."),

'enable_libsafe' => N("Arguments: (arg)

Enable/Disable libsafe if libsafe is found on the system."),

'enable_log_strange_packets' => N("Arguments: (arg)

Enable/Disable the logging of IPv4 strange packets."),

'enable_msec_cron' => N("Arguments: (arg)

Enable/Disable msec hourly security check."),

'enable_pam_wheel_for_su' => N("Arguments: (arg)

 Enabling su only from members of the wheel group or allow su from any user."),

'enable_password' => N("Arguments: (arg)

Use password to authenticate users."),

'enable_promisc_check' => N("Arguments: (arg)

Activate/Disable ethernet cards promiscuity check."),

'enable_security_check' => N("Arguments: (arg)

 Activate/Disable daily security check."),

'enable_sulogin' => N("Arguments: (arg)

 Enable/Disable sulogin(8) in single user level."),

'no_password_aging_for' => N("Arguments: (name)

Add the name as an exception to the handling of password aging by msec."),

'password_aging' => N("Arguments: (max, inactive=-1)

Set password aging to \fImax\fP days and delay to change to \fIinactive\fP."),

'password_history' => N("Arguments: (arg)

Set the password history length to prevent password reuse."),

'password_length' => N("Arguments: (length, ndigits=0, nupper=0)

Set the password minimum length and minimum number of digit and minimum number of capitalized letters."),

'set_root_umask' => N("Arguments: (umask)

Set the root umask."),
CHECK_UNOWNED => N("if set to yes, report unowned files."),
CHECK_SHADOW => N("if set to yes, check empty password in /etc/shadow."),
CHECK_SUID_MD5 => N("if set to yes, verify checksum of the suid/sgid files."),
CHECK_SECURITY => N("if set to yes, run the daily security checks."),
CHECK_PASSWD => N("if set to yes, check for empty passwords, for no password in /etc/shadow and for"),
SYSLOG_WARN => N("if set to yes, report check result to syslog."),
CHECK_SUID_ROOT => N("if set to yes, check additions/removals of suid root files."),
CHECK_PERMS => N("if set to yes, check permissions of files in the users' home."),
CHKROOTKIT_CHECK => N("if set to yes, run chkrootkit checks."),
CHECK_PROMISC => N("if set to yes, check if the network devices are in promiscuous mode."),
RPM_CHECK => N("if set to yes, run some checks against the rpm database."),
TTY_WARN => N("if set to yes, reports check result to tty."),
CHECK_WRITABLE => N("if set to yes, check files/directories writable by everybody."),
MAIL_WARN => N("if set to yes, report check result by mail."),
MAIL_USER => N("if set, send the mail report to this email address else send it to root."),
CHECK_OPEN_PORT => N("if set to yes, check open ports."),
CHECK_SGID => N("if set to yes, check additions/removals of sgid files."),

'set_shell_history_size' => N("Arguments: (size)

Set shell commands history size. A value of -1 means unlimited."),

'set_shell_timeout' => N("Arguments: (val)

Set the shell timeout. A value of zero means no timeout."),

'set_user_umask' => N("Arguments: (umask)

Set the user umask."),
);
