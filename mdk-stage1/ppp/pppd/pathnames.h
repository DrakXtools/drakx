/*
 * define path names
 *
 * $Id$
 */

#define _PATH_VARRUN 	"/var/run/"
#define _PATH_DEVNULL	"/dev/null"
#define _ROOT_PATH

#define _PATH_UPAPFILE 	 _ROOT_PATH "/etc/ppp/pap-secrets"
#define _PATH_CHAPFILE 	 _ROOT_PATH "/etc/ppp/chap-secrets"
#define _PATH_SYSOPTIONS _ROOT_PATH "/etc/ppp/options"
#define _PATH_IPUP	 _ROOT_PATH "/etc/ppp/ip-up"
#define _PATH_IPDOWN	 _ROOT_PATH "/etc/ppp/ip-down"
#define _PATH_AUTHUP	 _ROOT_PATH "/etc/ppp/auth-up"
#define _PATH_AUTHDOWN	 _ROOT_PATH "/etc/ppp/auth-down"
#define _PATH_TTYOPT	 _ROOT_PATH "/etc/ppp/options."
#define _PATH_CONNERRS	 _ROOT_PATH "/etc/ppp/connect-errors"
#define _PATH_PEERFILES	 _ROOT_PATH "/etc/ppp/peers/"
#define _PATH_RESOLV	 _ROOT_PATH "/etc/resolv.conf"

#define _PATH_USEROPT	 ".ppprc"

#define _PATH_PPPDB	_ROOT_PATH _PATH_VARRUN "pppd.tdb"
