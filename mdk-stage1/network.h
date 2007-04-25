/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#ifndef _NETWORK_H_
#define _NETWORK_H_

#include <netinet/in.h>
#include <netinet/ip.h>
#include <arpa/inet.h>

enum return_type intf_select_and_up();

enum return_type nfs_prepare(void);
enum return_type ftp_prepare(void);
enum return_type http_prepare(void);
#ifndef DISABLE_KA
enum return_type ka_prepare(void);
#endif


enum boot_proto_type { BOOTPROTO_STATIC, BOOTPROTO_DHCP, BOOTPROTO_ADSL_PPPOE };
enum auto_detection_type { AUTO_DETECTION_NONE, AUTO_DETECTION_ALL, AUTO_DETECTION_WIRED };

/* all of these in_addr things are in network byte order! */
struct interface_info {
	char device[10];
	int is_ptp, is_up;
	struct in_addr ip, netmask, broadcast, network;
	enum boot_proto_type boot_proto;
	char *user, *pass, *acname; /* for ADSL connection */
};


/* these are to be used only by dhcp.c */

char * guess_netmask(char * ip_addr);

int configure_net_device(struct interface_info * intf);

extern char * hostname;
extern char * domain;
extern struct in_addr gateway;
extern struct in_addr dns_server;
extern struct in_addr dns_server2;



#endif
