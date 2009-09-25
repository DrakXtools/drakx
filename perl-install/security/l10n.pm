package security::l10n;
# This help was build from stripped from python description of msec functions
# soft/msec/share/libmsec.py
#
# It's used in draksec option labels

use common;

sub fields() {
    return (
            'accept_bogus_error_responses' => N("Accept bogus IPv4 error messages"),
            'accept_broadcasted_icmp_echo' => N("Accept broadcasted icmp echo"),
            'accept_icmp_echo' => N("Accept icmp echo"),
            'allow_autologin' => N("Autologin"),
            'allow_issues' => N("/etc/issue* exist"),
            'allow_reboot' => N("Reboot by the console user"),
            'allow_remote_root_login' => N("Allow remote root login"),
            'allow_root_login' => N("Direct root login"),
            'allow_user_list' => N("List users on display managers (kdm and gdm)"),
            'allow_xauth_from_root' => N("Export display when passing from root to the other users"),
            'allow_x_connections' => N("Allow X Window connections"),
            'allow_xserver_to_listen' => N("Authorize TCP connections to X Window"),
            'authorize_services' => N("Authorize all services controlled by tcp_wrappers"),
            'create_server_link' => N("Chkconfig obey msec rules"),
            'enable_at_crontab' => N("Enable \"crontab\" and \"at\" for users"),
            'enable_console_log' => N("Syslog reports to console 12"),
            'enable_dns_spoofing_protection' => N("Name resolution spoofing protection"),
            'enable_ip_spoofing_protection' => N("Enable IP spoofing protection"),
            'enable_libsafe' => N("Enable libsafe if libsafe is found on the system"),
            'enable_log_strange_packets' => N("Enable the logging of IPv4 strange packets"),
            'enable_msec_cron' => N("Enable msec hourly security check"),
            'enable_pam_wheel_for_su' => N("Enable su only from the wheel group members"),
            'enable_password' => N("Use password to authenticate users"),
            'enable_promisc_check' => N("Ethernet cards promiscuity check"),
            'enable_security_check' => N("Daily security check"),
            'enable_sulogin' => N("Sulogin(8) in single user level"),
            'no_password_aging_for' => N("No password aging for"),
            'password_aging' => N("Set password expiration and account inactivation delays"),
            'password_history' => N("Password history length"),
            'password_length' => N("Password minimum length and number of digits and upcase letters"),
            'set_root_umask' => N("Root umask"),
            'set_shell_history_size' => N("Shell history size"),
            'set_shell_timeout' => N("Shell timeout"),
            'set_user_umask' => N("User umask"),
            CHECK_OPEN_PORT => N("Check open ports"),
            CHECK_PASSWD => N("Check for unsecured accounts"),
            CHECK_PERMS => N("Check permissions of files in the users' home"),
            CHECK_PROMISC => N("Check if the network devices are in promiscuous mode"),
            CHECK_SECURITY => N("Run the daily security checks"),
            CHECK_SGID => N("Check additions/removals of sgid files"),
            CHECK_SHADOW => N("Check empty password in /etc/shadow"),
            CHECK_SUID_MD5 => N("Verify checksum of the suid/sgid files"),
            CHECK_SUID_ROOT => N("Check additions/removals of suid root files"),
            CHECK_UNOWNED => N("Report unowned files"),
            CHECK_WRITABLE => N("Check files/directories writable by everybody"),
            CHKROOTKIT_CHECK => N("Run chkrootkit checks"),
            MAIL_EMPTY_CONTENT => N("Do not send empty mail reports"),
            MAIL_USER => N("If set, send the mail report to this email address else send it to root"),
            MAIL_WARN => N("Report check result by mail"),
            RPM_CHECK => N("Run some checks against the rpm database"),
            SYSLOG_WARN => N("Report check result to syslog"),
            TTY_WARN => N("Reports check result to tty"),
           );
}

1;
