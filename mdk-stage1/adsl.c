/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include <errno.h>

#include "stage1.h"
#include "log.h"
#include "network.h"
#include "modules.h"
#include "tools.h"
#include "frontend.h"

#include "adsl.h"

enum return_type perform_adsl(struct interface_info * intf)
{
	char * pppd_launch[] = { "/sbin/pppd", "pty", "/sbin/pppoe -p /var/run/pppoe.conf-adsl.pid.pppoe -I eth0 -T 80 -U  -m 1412",
				 "noipdefault", "noauth", "default-asyncmap", "defaultroute", "hide-password", "nodetach", "usepeerdns",
				 "local", "mtu", "1492", "mru", "1492", "noaccomp", "noccp", "nobsdcomp", "nodeflate", "nopcomp", 
				 "novj", "novjccomp", "user", "netissimo@netissimo", "lcp-echo-interval", "20", "lcp-echo-failure",
				 "3", NULL };
	int fd;
	
	struct in_addr addr;

	if (strncmp(intf->device, "eth", 3)) {
		stg1_error_message("ADSL available only for Ethernet networking (through PPPoE).");
		return RETURN_ERROR;
	}

	inet_aton("10.0.0.10", &addr);
	memcpy(&intf->ip, &addr, sizeof(addr));

	inet_aton("255.255.255.0", &addr);
	memcpy(&intf->netmask, &addr, sizeof(addr));

	*((uint32_t *) &intf->broadcast) = (*((uint32_t *) &intf->ip) &
					    *((uint32_t *) &intf->netmask)) | ~(*((uint32_t *) &intf->netmask));

	intf->is_ptp = 0;

	if (configure_net_device(intf)) {
		stg1_error_message("Could not configure..");
		return RETURN_ERROR;
	}

	my_insmod("ppp_generic", ANY_DRIVER_TYPE, NULL);
	my_insmod("ppp_async", ANY_DRIVER_TYPE, NULL);
	my_insmod("ppp_synctty", ANY_DRIVER_TYPE, NULL);
	my_insmod("ppp", ANY_DRIVER_TYPE, NULL);

	stg1_info_message("Interface %s seems ready.", intf->device);

	
	fd = open("/dev/tty6", O_RDWR);
	if (fd == -1) {
		log_message("cannot open /dev/tty6 -- no pppd");
		return RETURN_ERROR;
	}
	else if (access(pppd_launch[0], X_OK)) {
		log_message("cannot open pppd - %s doesn't exist", pppd_launch[0]);
		return RETURN_ERROR;
	}

	if (!fork()) {
		dup2(fd, 0);
		dup2(fd, 1);
		dup2(fd, 2);
		
		close(fd);
		setsid();
		if (ioctl(0, TIOCSCTTY, NULL))
			log_perror("could not set new controlling tty");
	
		execve(pppd_launch[0], pppd_launch, grab_env());
		log_message("execve of %s failed: %s", pppd_launch[0], strerror(errno));
	}

	close(fd);

	stg1_info_message("Forked for %s.", intf->device);

	return RETURN_OK;

}
