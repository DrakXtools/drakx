/*
 * Olivier Blin (oblin@mandriva.com)
 *
 * Copyright 2005 Mandriva
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <linux/wireless.h>

#include "automatic.h"
#include "stage1.h"
#include "log.h"
#include "wireless.h"

static int wireless_ioctl(int socket, const char *ifname, int request, struct iwreq *wrq);
static int wireless_set_mode_managed(int socket, const char *ifname);
static int wireless_disable_key(int socket, const char *ifname);
static int wireless_set_restricted_key(int socket, const char *ifname, const char *key);
static int wireless_set_essid(int socket, const char *ifname, const char *essid);

int wireless_open_socket()
{
	return socket(AF_INET, SOCK_DGRAM, 0);
}

int wireless_close_socket(int socket)
{
	return close(socket);
}

static int wireless_ioctl(int socket, const char *ifname, int request, struct iwreq *wrq)
{
	strncpy(wrq->ifr_name, ifname, IFNAMSIZ);
	return ioctl(socket, request, wrq);
}

int wireless_is_aware(int socket, const char *ifname)
{
	struct iwreq wrq;
	return wireless_ioctl(socket, ifname, SIOCGIWNAME, &wrq) == 0;
}

static int wireless_set_mode_managed(int socket, const char *ifname)
{
	struct iwreq wrq;

	wrq.u.mode = IW_MODE_INFRA; /* managed */

	return wireless_ioctl(socket, ifname, SIOCSIWMODE, &wrq) == 0;
}

static int wireless_set_essid(int socket, const char *ifname, const char *essid)
{
	struct iwreq wrq;

	wrq.u.essid.flags = 1;
	wrq.u.essid.pointer = (void *) essid;
	wrq.u.essid.length = strlen(essid) + 1;

	return wireless_ioctl(socket, ifname, SIOCSIWESSID, &wrq) == 0;
}

static int wireless_disable_key(int socket, const char *ifname)
{
	struct iwreq wrq;

	wrq.u.data.flags = IW_ENCODE_DISABLED;
	wrq.u.data.pointer = NULL;
	wrq.u.data.length = 0;

	return wireless_ioctl(socket, ifname, SIOCSIWENCODE, &wrq) == 0;
}

static int wireless_set_restricted_key(int socket, const char *ifname, const char *key)
{
	struct iwreq wrq;
	char real_key[IW_ENCODING_TOKEN_MAX];
	int key_len = 0;
	unsigned int tmp;

	while (sscanf(key + 2*key_len, "%2X", &tmp) == 1)
		real_key[key_len++] = (char) tmp;

	wrq.u.data.flags = IW_ENCODE_RESTRICTED;
	wrq.u.data.pointer = (char *) real_key;
	wrq.u.data.length = key_len;

	return wireless_ioctl(socket, ifname, SIOCSIWENCODE, &wrq) == 0;
}

enum return_type configure_wireless(const char *ifname)
{
	enum return_type results;
	char * questions[] = { "ESSID", "WEP key", NULL };
	char * questions_auto[] = { "essid", "wep_key" };
	static char ** answers = NULL;
	int wsock = wireless_open_socket();

	if (!wireless_is_aware(wsock, ifname)) {
		log_message("interface %s doesn't support wireless", ifname);
		wireless_close_socket(wsock);
		return RETURN_OK;
	}

	results = ask_from_entries_auto("Please enter your wireless settings. "
                                        "The ESSID is your wireless network identifier. "
                                        "The WEP key must be entered in hexadecimal, without any separator.",
					questions, &answers, 32, questions_auto, NULL);
	if (results != RETURN_OK) {
		wireless_close_socket(wsock);
		return RETURN_BACK;
	}

	if (!wireless_set_mode_managed(wsock, ifname)) {
		stg1_error_message("unable to set mode Managed on device \"%s\": %s", ifname, strerror(errno));
		wireless_close_socket(wsock);
		return RETURN_ERROR;
	}

	if (answers[1] && !streq(answers[1], "")) {
		log_message("setting WEP key \"%s\" on device \"%s\"", answers[1], ifname);
		if (!wireless_set_restricted_key(wsock, ifname, answers[1])) {
			stg1_error_message("unable to set WEP key \"%s\" on device \"%s\": %s", answers[1], ifname, strerror(errno));
			return RETURN_ERROR;
		}
	} else {
		log_message("disabling WEP key on device \"%s\"", ifname);
		if (!wireless_disable_key(wsock, ifname)) {
			stg1_error_message("unable to disable WEP key on device \"%s\": %s", ifname, strerror(errno));
			return RETURN_ERROR;
		}
	}

        /* most devices perform discovery when ESSID is set, it needs to be last */
	log_message("setting ESSID \"%s\" on device \"%s\"", answers[0], ifname);
	if (!wireless_set_essid(wsock, ifname, answers[0])) {
		stg1_error_message("unable to set ESSID \"%s\" on device \"%s\": %s", answers[0], ifname, strerror(errno));
		return RETURN_ERROR;
	}

	wireless_close_socket(wsock);
	return RETURN_OK;
}
