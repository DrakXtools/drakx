package security::help;
# This help was forked from msec internal function descriptions
# They were then reworked in order to be targeted for end users, not msec developpers


use strict;
use common;

our %help = (

'accept_bogus_error_responses' => N("Accept/Refuse bogus IPv4 error messages."),

'accept_broadcasted_icmp_echo' => N(" Accept/Refuse broadcasted icmp echo."),

'accept_icmp_echo' => N(" Accept/Refuse icmp echo."),

'allow_autologin' => N("Allow/Forbid autologin."),

'allow_issues' => N("If set to \"ALL\", /etc/issue and /etc/issue.net are allowed to exist.

If set to NONE, no issues are allowed.

Else only /etc/issue is allowed."),

'allow_reboot' => N("Allow/Forbid reboot by the console user."),

'allow_remote_root_login' => N("Allow/Forbid remote root login."),

'allow_root_login' => N("Allow/Forbid direct root login."),

'allow_user_list' => N("Allow/Forbid the list of users on the system on display managers (kdm and gdm)."),

'allow_x_connections' => N("Allow/Forbid X connections:

- ALL (all connections are allowed),

- LOCAL (only connection from local machine),

- NONE (no connection)."),

'allow_xserver_to_listen' => N("The argument specifies if clients are authorized to connect
to the X server from the network on the tcp port 6000 or not."),

'authorize_services' => N("Authorize:

- all services controlled by tcp_wrappers (see hosts.deny(5) man page) if set to \"ALL\",

- only local ones if set to \"LOCAL\"

- none if set to \"NONE\".

To authorize the services you need, use /etc/hosts.allow (see hosts.allow(5))."),

'create_server_link' => N("If SERVER_LEVEL (or SECURE_LEVEL if absent)
is greater than 3 in /etc/security/msec/security.conf, creates the
symlink /etc/security/msec/server to point to
/etc/security/msec/server.<SERVER_LEVEL>.

The /etc/security/msec/server is used by chkconfig --add to decide to
add a service if it is present in the file during the installation of
packages."),

'enable_at_crontab' => N("Enable/Disable crontab and at for users.

Put allowed users in /etc/cron.allow and /etc/at.allow (see man at(1)
and crontab(1))."),

'enable_console_log' => N("Enable/Disable syslog reports to console 12"),

'enable_dns_spoofing_protection' => N("Enable/Disable name resolution spoofing protection.  If
\"alert\" is true, also reports to syslog."),

'enable_ip_spoofing_protection' => N("Enable/Disable IP spoofing protection."),

'enable_libsafe' => N("Enable/Disable libsafe if libsafe is found on the system."),

'enable_log_strange_packets' => N("Enable/Disable the logging of IPv4 strange packets."),

'enable_msec_cron' => N("Enable/Disable msec hourly security check."),

'enable_pam_wheel_for_su' => N(" Enabling su only from members of the wheel group or allow su from any user."),

'enable_password' => N("Use password to authenticate users."),

'enable_promisc_check' => N("Activate/Disable ethernet cards promiscuity check."),

'enable_security_check' => N(" Activate/Disable daily security check."),

'enable_sulogin' => N(" Enable/Disable sulogin(8) in single user level."),

'no_password_aging_for' => N("Add the name as an exception to the handling of password aging by msec."),

'password_aging' => N("Set password aging to \"max\" days and delay to change to \"inactive\"."),

'password_history' => N("Set the password history length to prevent password reuse."),

'password_length' => N("Set the password minimum length and minimum number of digit and minimum number of capitalized letters."),

'set_root_umask' => N("Set the root umask."),
CHECK_OPEN_PORT => N("if set to yes, check open ports."),
CHECK_PASSWD => N("if set to yes, check for :

- empty passwords,

- no password in /etc/shadow

- for users with the 0 id other than root."),
CHECK_PERMS => N("if set to yes, check permissions of files in the users' home."),
CHECK_PROMISC => N("if set to yes, check if the network devices are in promiscuous mode."),
CHECK_SECURITY => N("if set to yes, run the daily security checks."),
CHECK_SGID => N("if set to yes, check additions/removals of sgid files."),
CHECK_SHADOW => N("if set to yes, check empty password in /etc/shadow."),
CHECK_SUID_MD5 => N("if set to yes, verify checksum of the suid/sgid files."),
CHECK_SUID_ROOT => N("if set to yes, check additions/removals of suid root files."),
CHECK_UNOWNED => N("if set to yes, report unowned files."),
CHECK_WRITABLE => N("if set to yes, check files/directories writable by everybody."),
CHKROOTKIT_CHECK => N("if set to yes, run chkrootkit checks."),
MAIL_USER => N("if set, send the mail report to this email address else send it to root."),
MAIL_WARN => N("if set to yes, report check result by mail."),
RPM_CHECK => N("if set to yes, run some checks against the rpm database."),
SYSLOG_WARN => N("if set to yes, report check result to syslog."),
TTY_WARN => N("if set to yes, reports check result to tty."),

'set_shell_history_size' => N("Set shell commands history size. A value of -1 means unlimited."),

'set_shell_timeout' => N("Set the shell timeout. A value of zero means no timeout."),

'set_user_umask' => N("Set the user umask."),
);
