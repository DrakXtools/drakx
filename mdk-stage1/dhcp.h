/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * View the homepage: http://us.mandrakesoft.com/~gc/html/stage1.html
 *
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
 *  Portions from GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2000  Free Software Foundation, Inc.
 *
 *  Itself based on etherboot-4.6.4 by Martin Renters.
 *
 */

#ifndef _DHCP_H_
#define _DHCP_H_

#include <net/if.h>
#include "stage1.h"
#include "network.h"

enum return_type setup_network_intf_as_dhcp(struct interface_info * intf);


/* -=-=-- */

#define BOOTP_REQUEST	1
#define BOOTP_REPLY	2
#define MAX_BOOTP_RETRIES	20

#define ETHER_ADDR_SIZE		6	/* Size of Ethernet address */
#define ETHER_HDR_SIZE		14	/* Size of ethernet header */
#define ETH_MIN_PACKET		64
#define ETH_MAX_PACKET		1518

#define TAG_LEN(p)		(*((p)+1))
#define RFC1533_COOKIE		99, 130, 83, 99
#define RFC1533_PAD		0
#define RFC1533_NETMASK		1
#define RFC1533_TIMEOFFSET	2
#define RFC1533_GATEWAY		3
#define RFC1533_TIMESERVER	4
#define RFC1533_IEN116NS	5
#define RFC1533_DNS		6
#define RFC1533_LOGSERVER	7
#define RFC1533_COOKIESERVER	8
#define RFC1533_LPRSERVER	9
#define RFC1533_IMPRESSSERVER	10
#define RFC1533_RESOURCESERVER	11
#define RFC1533_HOSTNAME	12
#define RFC1533_BOOTFILESIZE	13
#define RFC1533_MERITDUMPFILE	14
#define RFC1533_DOMAINNAME	15
#define RFC1533_SWAPSERVER	16
#define RFC1533_ROOTPATH	17
#define RFC1533_EXTENSIONPATH	18
#define RFC1533_IPFORWARDING	19
#define RFC1533_IPSOURCEROUTING	20
#define RFC1533_IPPOLICYFILTER	21
#define RFC1533_IPMAXREASSEMBLY	22
#define RFC1533_IPTTL		23
#define RFC1533_IPMTU		24
#define RFC1533_IPMTUPLATEAU	25
#define RFC1533_INTMTU		26
#define RFC1533_INTLOCALSUBNETS	27
#define RFC1533_INTBROADCAST	28
#define RFC1533_INTICMPDISCOVER	29
#define RFC1533_INTICMPRESPOND	30
#define RFC1533_INTROUTEDISCOVER 31
#define RFC1533_INTROUTESOLICIT	32
#define RFC1533_INTSTATICROUTES	33
#define RFC1533_LLTRAILERENCAP	34
#define RFC1533_LLARPCACHETMO	35
#define RFC1533_LLETHERNETENCAP	36
#define RFC1533_TCPTTL		37
#define RFC1533_TCPKEEPALIVETMO	38
#define RFC1533_TCPKEEPALIVEGB	39
#define RFC1533_NISDOMAIN	40
#define RFC1533_NISSERVER	41
#define RFC1533_NTPSERVER	42
#define RFC1533_VENDOR		43
#define RFC1533_NBNS		44
#define RFC1533_NBDD		45
#define RFC1533_NBNT		46
#define RFC1533_NBSCOPE		47
#define RFC1533_XFS		48
#define RFC1533_XDM		49
#define RFC2132_REQ_ADDR	50
#define RFC2132_MSG_TYPE	53
#define RFC2132_SRV_ID		54
#define RFC2132_PARAM_LIST	55
#define RFC2132_MAX_SIZE	57

#define DHCPDISCOVER		1
#define DHCPOFFER		2
#define DHCPREQUEST		3
#define DHCPACK			5

#define DHCP_OPT_LEN		312


#define	TICKS_PER_SEC		18

/* Inter-packet retry in ticks */
#define TIMEOUT			(10*TICKS_PER_SEC)


struct arprequest {
	unsigned short hwtype;
	unsigned short protocol;
	char hwlen;
	char protolen;
	unsigned short opcode;
	char shwaddr[6];
	char sipaddr[4];
	char thwaddr[6];
	char tipaddr[4];
};

struct iphdr_ {
	char verhdrlen;
	char service;
	unsigned short len;
	unsigned short ident;
	unsigned short frags;
	char ttl;
	char protocol;
	unsigned short chksum;
	struct in_addr src;
	struct in_addr dest;
};

struct udphdr {
	unsigned short src;
	unsigned short dest;
	unsigned short len;
	unsigned short chksum;
};

struct bootp_t {
	struct iphdr_ ip;
	struct udphdr udp;
	char bp_op;
	char bp_htype;
	char bp_hlen;
	char bp_hops;
	unsigned long bp_xid;
	unsigned short bp_secs;
	unsigned short unused;
	struct in_addr bp_ciaddr;
	struct in_addr bp_yiaddr;
	struct in_addr bp_siaddr;
	struct in_addr bp_giaddr;
	char bp_hwaddr[16];
	char bp_sname[64];
	char bp_file[128];
	char bp_vend[DHCP_OPT_LEN];
};


#endif
