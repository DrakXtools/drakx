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

/*
 * Portions from GRUB  --  GRand Unified Bootloader
 * Copyright (C) 2000  Free Software Foundation, Inc.
 */


#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <net/route.h>
#include <errno.h>
#include <net/ethernet.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <sys/time.h>
#include <fcntl.h>

#include "stage1.h"
#include "log.h"
#include "network.h"
#include "frontend.h"

#include "dhcp.h"


#define NUM_RETRIES	5


typedef int bp_int32;
typedef short bp_int16;

#define BOOTP_OPTION_NETMASK		1
#define BOOTP_OPTION_GATEWAY		3
#define BOOTP_OPTION_DNS		6
#define BOOTP_OPTION_HOSTNAME		12
#define BOOTP_OPTION_DOMAIN		15
#define BOOTP_OPTION_BROADCAST		28

#define DHCP_OPTION_REQADDR		50
#define DHCP_OPTION_LEASE		51
#define DHCP_OPTION_TYPE		53
#define DHCP_OPTION_SERVER		54
#define DHCP_OPTION_OPTIONREQ		55
#define DHCP_OPTION_MAXSIZE		57

#define BOOTP_CLIENT_PORT	68
#define BOOTP_SERVER_PORT	67

#define BOOTP_OPCODE_REQUEST	1
#define BOOTP_OPCODE_REPLY	2

#define DHCP_TYPE_DISCOVER	1
#define DHCP_TYPE_OFFER		2
#define DHCP_TYPE_REQUEST	3
#define DHCP_TYPE_ACK		5
#define DHCP_TYPE_RELEASE	7

#define BOOTP_VENDOR_LENGTH	64
#define DHCP_VENDOR_LENGTH	340

struct bootp_request {
	char opcode;
	char hw;
	char hwlength;
	char hopcount;
	bp_int32 id;
	bp_int16 secs;
	bp_int16 flags;
	bp_int32 ciaddr, yiaddr, server_ip, bootp_gw_ip;
	char hwaddr[16];
	char servername[64];
	char bootfile[128];
	char vendor[DHCP_VENDOR_LENGTH];
} ;

static const char vendor_cookie[] = { 99, 130, 83, 99, 255 };


static unsigned int verify_checksum(void * buf2, int length2)
{
	unsigned int csum = 0;
	unsigned short * sp;

	for (sp = (unsigned short *) buf2; length2 > 0; (length2 -= 2), sp++)
		csum += *sp;
	
	while (csum >> 16)
		csum = (csum & 0xffff) + (csum >> 16);

	return (csum == 0xffff);
}


static int initial_setup_interface(char * device, int s) {
	struct sockaddr_in * addrp;
	struct ifreq req;
	struct rtentry route;
	int true = 1;
	
	addrp = (struct sockaddr_in *) &req.ifr_addr;
	
	strcpy(req.ifr_name, device);
	addrp->sin_family = AF_INET;
	addrp->sin_port = 0;
	memset(&addrp->sin_addr, 0, sizeof(addrp->sin_addr));
	
	req.ifr_flags = 0; /* take it down */
	if (ioctl(s, SIOCSIFFLAGS, &req)) {
		log_perror("SIOCSIFFLAGS (downing)");
		return -1;
	}
    
	addrp->sin_family = AF_INET;
	addrp->sin_addr.s_addr = htonl(0);
	if (ioctl(s, SIOCSIFADDR, &req)) {
		log_perror("SIOCSIFADDR");
		return -1;
	}

	req.ifr_flags = IFF_UP | IFF_BROADCAST | IFF_RUNNING;
	if (ioctl(s, SIOCSIFFLAGS, &req)) {
		log_perror("SIOCSIFFLAGS (upping)");
		return -1;
	}

	memset(&route, 0, sizeof(route));
	memcpy(&route.rt_gateway, addrp, sizeof(*addrp));
	
	addrp->sin_family = AF_INET;
	addrp->sin_port = 0;
	addrp->sin_addr.s_addr = INADDR_ANY;
	memcpy(&route.rt_dst, addrp, sizeof(*addrp));
	memcpy(&route.rt_genmask, addrp, sizeof(*addrp));
	
	route.rt_dev = device;
	route.rt_flags = RTF_UP;
	route.rt_metric = 0;
	
	if (ioctl(s, SIOCADDRT, &route)) {
		if (errno != EEXIST) {
			close(s);
			log_perror("SIOCADDRT");
			return -1;
		}
	}
	
	if (setsockopt(s, SOL_SOCKET, SO_BROADCAST, &true, sizeof(true))) {
		close(s);
		log_perror("setsockopt");
		return -1;
	}

	return 0;
}


void set_missing_ip_info(struct interface_info * intf)
{
	bp_int32 ipNum = *((bp_int32 *) &intf->ip);
	bp_int32 nmNum;

	if (intf->netmask.s_addr == 0)
		guess_netmask(intf);

	nmNum = *((bp_int32 *) &intf->netmask);

	if (intf->broadcast.s_addr == 0)
		*((bp_int32 *) &intf->broadcast) = (ipNum & nmNum) | ~(nmNum);

	if (intf->network.s_addr == 0)
		*((bp_int32 *) &intf->network) = ipNum & nmNum;
}

static void parse_reply(struct bootp_request * breq, struct interface_info * intf)
{
	unsigned char * chptr;
	unsigned char option, length;

	memcpy(&intf->ip, &breq->yiaddr, 4);

	chptr = breq->vendor;
	chptr += 4;
	while (*chptr != 0xFF && (void *) chptr < (void *) breq->vendor + DHCP_VENDOR_LENGTH) {
		char tmp_str[500];
		option = *chptr++;
		if (!option)
			continue;
		length = *chptr++;

		switch (option) {
		case BOOTP_OPTION_DNS:
			memcpy(&dns_server, chptr, sizeof(dns_server));
			if (length >= sizeof(dns_server)*2)
				memcpy(&dns_server2, chptr+sizeof(dns_server), sizeof(dns_server2));
			break;

		case BOOTP_OPTION_NETMASK:
			memcpy(&intf->netmask, chptr, 4);
			break;
		    
		case BOOTP_OPTION_DOMAIN:
			memcpy(tmp_str, chptr, length);
			tmp_str[length] = '\0';
			domain = strdup(tmp_str);
			break;

		case BOOTP_OPTION_BROADCAST:
			memcpy(&intf->broadcast, chptr, 4);
			break;

		case BOOTP_OPTION_GATEWAY:
			memcpy(&gateway, chptr, 4);
			break;

		case BOOTP_OPTION_HOSTNAME:
			memcpy(tmp_str, chptr, length);
			tmp_str[length] = '\0';
			hostname = strdup(tmp_str);
			log_message("DHCP: got hostname %s", hostname);
			break;

		}

		chptr += length;
	}

	set_missing_ip_info(intf);
}


static void init_vendor_codes(struct bootp_request * breq) {
	memcpy(breq->vendor, vendor_cookie, sizeof(vendor_cookie));
}

static char gen_hwaddr[16];

static int prepare_request(struct bootp_request * breq, int sock, char * device, time_t startTime)
{
	struct ifreq req;
	
	memset(breq, 0, sizeof(*breq));
	
	breq->opcode = BOOTP_OPCODE_REQUEST;
	
	strcpy(req.ifr_name, device);
	if (ioctl(sock, SIOCGIFHWADDR, &req)) {
		log_perror("SIOCSIFHWADDR");
		return -1;
	}
	
	breq->hw = 1; 		/* ethernet */
	breq->hwlength = IFHWADDRLEN;	
	memcpy(breq->hwaddr, req.ifr_hwaddr.sa_data, IFHWADDRLEN);
	memcpy(gen_hwaddr, req.ifr_hwaddr.sa_data, IFHWADDRLEN);
	
	breq->hopcount = 0;
	
	init_vendor_codes(breq);
	
	return 0;
}

static int get_vendor_code(struct bootp_request * bresp, unsigned char option, void * data)
{
	unsigned char * chptr;
	unsigned int length, theOption;
	
	chptr = bresp->vendor + 4;
	while (*chptr != 0xFF && *chptr != option) {
		theOption = *chptr++;
		if (!theOption)
			continue;
		length = *chptr++;
		chptr += length;
	}
	
	if (*chptr++ == 0xff)
		return 1;
	
	length = *chptr++;
	memcpy(data, chptr, length);
	
	return 0;
}


int
currticks (void)
{
	struct timeval tv;
	long csecs;
	int ticks_per_csec, ticks_per_usec;
	
	/* Note: 18.2 ticks/sec.  */
	
	gettimeofday (&tv, 0);
	csecs = tv.tv_sec / 10;
	ticks_per_csec = csecs * 182;
	ticks_per_usec = (((tv.tv_sec - csecs * 10) * 1000000 + tv.tv_usec) * 182 / 10000000);
	return ticks_per_csec + ticks_per_usec;
}


#define BACKOFF_LIMIT 7
#define	TICKS_PER_SEC 18
#define MAX_ARP_RETRIES	5

void
rfc951_sleep (int exp)
{
	static long seed = 0;
	long q;
	unsigned long tmo;
	
	if (exp > BACKOFF_LIMIT)
		exp = BACKOFF_LIMIT;
	
	if (!seed)
		/* Initialize linear congruential generator.  */
		seed = (currticks () + *(long *) &gen_hwaddr + ((short *) gen_hwaddr)[2]);
  
	/* Simplified version of the LCG given in Bruce Scheier's
	   "Applied Cryptography".  */
	q = seed / 53668;
	if ((seed = 40014 * (seed - 53668 * q) - 12211 * q) < 0)
		seed += 2147483563l;
	
	/* Compute mask.  */
	for (tmo = 63; tmo <= 60 * TICKS_PER_SEC && --exp > 0; tmo = 2 * tmo + 1)
		;
  
	/* Sleep.  */
	log_message("<sleep>");
	
	for (tmo = (tmo & seed) + currticks (); currticks () < tmo;);
}


static int handle_transaction(int s, struct bootp_request * breq, struct bootp_request * bresp,
			      struct sockaddr_in * server_addr, int dhcp_type)
{
	struct timeval tv;
	fd_set readfs;
	int i, j;
	int retry = 1;
	int sin;
	char eth_packet[ETH_FRAME_LEN];
	struct iphdr * ip_hdr;
	struct udphdr * udp_hdr;
	unsigned char type;
	unsigned long starttime;
	int timeout = 1;

	breq->id = starttime = currticks();
	breq->secs = 0;

	sin = socket(AF_PACKET, SOCK_DGRAM, ntohs(ETH_P_IP));

	while (retry <= MAX_ARP_RETRIES) {
		i = sizeof(*breq);

		if (sendto(s, breq, i, 0, (struct sockaddr *) server_addr, sizeof(*server_addr)) != i) {
			close(s);
			log_perror("sendto");
			return -1;
		}
		
		FD_ZERO(&readfs);
		FD_SET(sin, &readfs);
		tv.tv_usec = 0;
		tv.tv_sec = timeout;

		while (select(sin + 1, &readfs, NULL, NULL, &tv) == 1) {

			if ((j = recv(sin, eth_packet, sizeof(eth_packet), 0)) == -1) {
				log_perror("recv");
				continue;
			}
			
			/* We need to do some basic sanity checking of the header */
			if (j < (sizeof(*ip_hdr) + sizeof(*udp_hdr)))
				continue;
			
			ip_hdr = (void *) eth_packet;
			if (!verify_checksum(ip_hdr, sizeof(*ip_hdr)))
				continue;

			if (ntohs(ip_hdr->tot_len) > j)
				continue;

			j = ntohs(ip_hdr->tot_len);
			
			if (ip_hdr->protocol != IPPROTO_UDP)
				continue;
			
			udp_hdr = (void *) (eth_packet + sizeof(*ip_hdr));

			if (ntohs(udp_hdr->source) != BOOTP_SERVER_PORT)
				continue;
			
			if (ntohs(udp_hdr->dest) != BOOTP_CLIENT_PORT)
				continue;
			/* Go on with this packet; it looks sane */
			
			/* Originally copied sizeof (*bresp) - this is a security
			   problem due to a potential underflow of the source
			   buffer.  Also, it trusted that the packet was properly
			   0xFF terminated, which is not true in the case of the
			   DHCP server on Cisco 800 series ISDN router. */
			
			memset (bresp, 0xFF, sizeof (*bresp));
			memcpy (bresp, (char *) udp_hdr + sizeof (*udp_hdr), j - sizeof (*ip_hdr) - sizeof (*udp_hdr));
			
			/* sanity checks */
			if (bresp->id != breq->id)
				continue;
			if (bresp->opcode != BOOTP_OPCODE_REPLY)
				continue;
			if (bresp->hwlength != breq->hwlength)
				continue;
			if (memcmp(bresp->hwaddr, breq->hwaddr, bresp->hwlength))
				continue;
			if (get_vendor_code(bresp, DHCP_OPTION_TYPE, &type) || type != dhcp_type)
				continue;
			if (memcmp(bresp->vendor, vendor_cookie, 4))
				continue;
			return 0;
		}
		rfc951_sleep(retry);
		breq->secs = htons ((currticks () - starttime) / 20);
		retry++;
		timeout *= 2;
		if (timeout > 5)
			timeout = 5;
	}
	
	error_message("No DHCP reply received");
	return -1;
}

static void add_vendor_code(struct bootp_request * breq, unsigned char option, unsigned char length, void * data)
{
	unsigned char * chptr;
	int theOption, theLength;

	chptr = breq->vendor;
	chptr += 4;
	while (*chptr != 0xFF && *chptr != option) {
		theOption = *chptr++;
		if (!theOption) continue;
		theLength = *chptr++;
		chptr += theLength;
	}

	*chptr++ = option;
	*chptr++ = length;
	memcpy(chptr, data, length);
	chptr[length] = 0xff;
}



enum return_type perform_dhcp(struct interface_info * intf)
{
	int s, i;
	struct sockaddr_in server_addr;
	struct sockaddr_in client_addr;
	struct sockaddr_in broadcast_addr;
	struct bootp_request breq, bresp;
	unsigned char messageType;
	unsigned int lease;
	time_t startTime = time(NULL);
	short aShort;
	int num_options;
	char requested_options[50];

	if (strncmp(intf->device, "eth", 3)) {
		error_message("DHCP available only for Ethernet networking");
		return RETURN_ERROR;
	}

	s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s < 0) {
		log_perror("socket");
		return RETURN_ERROR;
	}

	if (initial_setup_interface(intf->device, s) != 0) {
		close(s);
		return RETURN_ERROR;
	}

	if (prepare_request(&breq, s, intf->device, startTime) != 0) {
		close(s);
		return RETURN_ERROR;
	}

	messageType = DHCP_TYPE_DISCOVER;
	add_vendor_code(&breq, DHCP_OPTION_TYPE, 1, &messageType);

	memset(&client_addr.sin_addr, 0, sizeof(&client_addr.sin_addr));
	client_addr.sin_family = AF_INET;
	client_addr.sin_port = htons(BOOTP_CLIENT_PORT);	/* bootp client */

	if (bind(s, (struct sockaddr *) &client_addr, sizeof(client_addr))) {
		log_perror("bind");
		return RETURN_ERROR;
	}

	broadcast_addr.sin_family = AF_INET;
	broadcast_addr.sin_port = htons(BOOTP_SERVER_PORT);	/* bootp server */
	memset(&broadcast_addr.sin_addr, 0xff, sizeof(broadcast_addr.sin_addr));  /* broadcast */

	log_message("DHCP: sending DISCOVER");

	wait_message("Sending DHCP request...");
	i = handle_transaction(s, &breq, &bresp, &broadcast_addr, DHCP_TYPE_OFFER);
	remove_wait_message();

	if (i != 0) {
		close(s);
		return RETURN_ERROR;
	}

	server_addr.sin_family = AF_INET;
	server_addr.sin_port = htons(BOOTP_SERVER_PORT);	/* bootp server */
	if (get_vendor_code(&bresp, DHCP_OPTION_SERVER, &server_addr.sin_addr)) {
		close(s);
		log_message("DHCPOFFER didn't include server address");
		return RETURN_ERROR;
	}

	init_vendor_codes(&breq);
	messageType = DHCP_TYPE_REQUEST;
	add_vendor_code(&breq, DHCP_OPTION_TYPE, 1, &messageType);
	add_vendor_code(&breq, DHCP_OPTION_SERVER, 4, &server_addr.sin_addr);
	add_vendor_code(&breq, DHCP_OPTION_REQADDR, 4, &bresp.yiaddr);

	aShort = ntohs(sizeof(struct bootp_request));
	add_vendor_code(&breq, DHCP_OPTION_MAXSIZE, 2, &aShort);

	num_options = 0;
	requested_options[num_options++] = BOOTP_OPTION_NETMASK;
	requested_options[num_options++] = BOOTP_OPTION_GATEWAY;
	requested_options[num_options++] = BOOTP_OPTION_DNS;
	requested_options[num_options++] = BOOTP_OPTION_DOMAIN;
	requested_options[num_options++] = BOOTP_OPTION_BROADCAST;
	add_vendor_code(&breq, DHCP_OPTION_OPTIONREQ, num_options, requested_options);

	/* request a lease of 1 hour */
	i = htonl(60 * 60);
	add_vendor_code(&breq, DHCP_OPTION_LEASE, 4, &i);

	log_message("DHCP: sending REQUEST");

	i = handle_transaction(s, &breq, &bresp, &broadcast_addr, DHCP_TYPE_ACK);

	if (i != 0) {
		close(s);
		return RETURN_ERROR;
	}

	if (get_vendor_code(&bresp, DHCP_OPTION_LEASE, &lease)) {
		log_message("failed to get lease time\n");
		return RETURN_ERROR;
	}
	lease = ntohl(lease);

	close(s);

	intf->netmask.s_addr = 0;
	intf->broadcast.s_addr = 0;
	intf->network.s_addr = 0;

	parse_reply(&bresp, intf);

	return RETURN_OK;
}
