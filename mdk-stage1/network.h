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


enum return_type nfs_prepare(void);
enum return_type ftp_prepare(void);
enum return_type http_prepare(void);


enum boot_proto_type { BOOTPROTO_STATIC, BOOTPROTO_DHCP };

/* all of these in_addr things are in network byte order! */
struct interface_info {
    char device[10];
    int is_ptp, is_up;
    int set, manually_set;
    struct in_addr ip, netmask, broadcast, network;
    struct in_addr boot_server;
    char * boot_file;
    enum boot_proto_type boot_proto;
};

struct net_info {
    int set, manually_set;
    char * hostname, * domain;		/* dynamically allocated */
    struct in_addr gateway;
    struct in_addr dns_server;
    int numDns;
};



#endif
