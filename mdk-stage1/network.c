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

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <net/route.h>
#include <resolv.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <stdio.h>

#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "dns.h"
#include "mount.h"
#include "automatic.h"
#include "dhcp.h"

#include "network.h"


static void error_message_net(void)  /* reduce code size */
{
	error_message("Could not configure network");
}


static int configure_net_device(struct interface_info * intf)
{
	struct ifreq req;
	struct rtentry route;
	int s;
	struct sockaddr_in addr;
	struct in_addr ia;
	char ip[20], nm[20], nw[20], bc[20];
	
	addr.sin_family = AF_INET;
	addr.sin_port = 0;
	
	memcpy(&ia, &intf->ip, sizeof(intf->ip));
	strcpy(ip, inet_ntoa(ia));
	
	memcpy(&ia, &intf->netmask, sizeof(intf->netmask));
	strcpy(nm, inet_ntoa(ia));
	
	memcpy(&ia, &intf->broadcast, sizeof(intf->broadcast));
	strcpy(bc, inet_ntoa(ia));
	
	memcpy(&ia, &intf->network, sizeof(intf->network));
	strcpy(nw, inet_ntoa(ia));

	log_message("configuring device %s ip: %s nm: %s nw: %s bc: %s", intf->device, ip, nm, nw, bc);

	if (IS_TESTING)
		return 0;

	s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s < 0) {
		log_perror("socket");
		error_message_net();
		return 1;
	}

	strcpy(req.ifr_name, intf->device);

	if (intf->is_up == 1) {
		log_message("interface already up, downing");

		req.ifr_flags = 0;
		if (ioctl(s, SIOCSIFFLAGS, &req)) {
			close(s);
			log_perror("SIOCSIFFLAGS (downing)");
			error_message_net();
			return 1;
		}
	}
		
	/* sets IP address */
	addr.sin_port = 0;
	memcpy(&addr.sin_addr, &intf->ip, sizeof(intf->ip));
	memcpy(&req.ifr_addr, &addr, sizeof(addr));
	if (ioctl(s, SIOCSIFADDR, &req)) {
		close(s);
		log_perror("SIOCSIFADDR");
		error_message_net();
		return 1;
	}

	/* sets broadcast */
	memcpy(&addr.sin_addr, &intf->broadcast, sizeof(intf->broadcast));
	memcpy(&req.ifr_broadaddr, &addr, sizeof(addr));
	if (ioctl(s, SIOCSIFBRDADDR, &req)) {
		close(s);
		log_perror("SIOCSIFBRDADDR");
		error_message_net();
		return 1;
	}

	/* sets netmask */
	memcpy(&addr.sin_addr, &intf->netmask, sizeof(intf->netmask));
	memcpy(&req.ifr_netmask, &addr, sizeof(addr));
	if (ioctl(s, SIOCSIFNETMASK, &req)) {
		close(s);
		log_perror("SIOCSIFNETMASK");
		error_message_net();
		return 1;
	}

	if (intf->is_ptp)
		req.ifr_flags = IFF_UP | IFF_RUNNING | IFF_POINTOPOINT | IFF_NOARP;
	else
		req.ifr_flags = IFF_UP | IFF_RUNNING | IFF_BROADCAST;

	/* brings up networking! */
	if (ioctl(s, SIOCSIFFLAGS, &req)) {
		close(s);
		log_perror("SIOCSIFFLAGS (upping)");
		error_message_net();
		return 1;
	}

	memset(&route, 0, sizeof(route));
	route.rt_dev = intf->device;
	route.rt_flags = RTF_UP;
	
	memcpy(&addr.sin_addr, &intf->network, sizeof(intf->network));
	memcpy(&route.rt_dst, &addr, sizeof(addr));
	
	memcpy(&addr.sin_addr, &intf->netmask, sizeof(intf->netmask));
	memcpy(&route.rt_genmask, &addr, sizeof(addr));

	/* adds route */
	if (ioctl(s, SIOCADDRT, &route)) {
		close(s);
		log_perror("SIOCADDRT");
		error_message_net();
		return 1;
	}

	close(s);

	intf->is_up = 1;
	
	return 0;
}

/* host network informations */ 
static char * hostname = NULL;
static char * domain = NULL;
static struct in_addr gateway = { 0 };
static struct in_addr dns_server = { 0 };

static int add_default_route(void)
{
	int s;
	struct rtentry route;
	struct sockaddr_in addr;

	if (IS_TESTING)
		return 0;

	if (gateway.s_addr == 0) {
		log_message("no gateway provided, can't add default route");
		return 0;
	}

	s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s < 0) {
		close(s);
		log_perror("socket");
		error_message_net();
		return 1;
	}

	memset(&route, 0, sizeof(route));

	addr.sin_family = AF_INET;
	addr.sin_port = 0;
	addr.sin_addr = gateway;
	memcpy(&route.rt_gateway, &addr, sizeof(addr));

	addr.sin_addr.s_addr = INADDR_ANY;
	memcpy(&route.rt_dst, &addr, sizeof(addr));
	memcpy(&route.rt_genmask, &addr, sizeof(addr));

	route.rt_flags = RTF_UP | RTF_GATEWAY;
	route.rt_metric = 0;

	if (ioctl(s, SIOCADDRT, &route)) {
		close(s);
		log_perror("SIOCADDRT");
		error_message_net();
		return 1;
	}

	close(s);
	
	return 0;
}


static int write_resolvconf(void) {
	char * filename = "/etc/resolv.conf";
	FILE * f;
	
	if (IS_TESTING)
		return 1;

	if (dns_server.s_addr == 0) {
		log_message("resolvconf needs a dns server");
		return -1;
	}

	f = fopen(filename, "w");
	if (!f) {
		log_perror(filename);
		return -1;
	}

	if (domain)
		fprintf(f, "search %s\n", domain); /* we can live without the domain search (user will have to enter fully-qualified names) */
	fprintf(f, "nameserver %s\n", inet_ntoa(dns_server));

	fclose(f);
	res_init();		/* reinit the resolver so DNS changes take affect */

	return 0;
}


static void guess_netmask(struct interface_info * intf, struct in_addr * addr)
{
	unsigned long int tmp = ntohl(intf->ip.s_addr);
	if (((tmp & 0xFF000000) >> 24) <= 127)
		inet_aton("255.0.0.0", addr);
	else if (((tmp & 0xFF000000) >> 24) <= 191)
		inet_aton("255.255.0.0", addr);
	else 
		inet_aton("255.255.255.0", addr);
	log_message("netmask guess: %s", inet_ntoa(*addr));
}


static enum return_type setup_network_interface(struct interface_info * intf)
{
	enum return_type results;
	char * bootprotos[] = { "Static", "DHCP", NULL };
	char * bootprotos_auto[] = { "static", "dhcp" };
	char * choice;

	results = ask_from_list_auto("Please choose the desired IP attribution.", bootprotos, &choice, "network", bootprotos_auto);
	if (results != RETURN_OK)
		return results;

	if (!strcmp(choice, "Static")) {
		char * questions[] = { "IP of this machine", "IP of Domain Name Server", "IP of default gateway", NULL };
		char * questions_auto[] = { "ip", "dns", "gateway" };
		char ** answers;
		struct in_addr addr;

		results = ask_from_entries_auto("Please enter the network information.", questions, &answers, 16, questions_auto);
		if (results != RETURN_OK)
			return setup_network_interface(intf);

		if (!inet_aton(answers[0], &addr)) {
			error_message("Invalid IP address");
			return setup_network_interface(intf);
		}
		memcpy(&intf->ip, &addr, sizeof(addr));

		if (!inet_aton(answers[1], &dns_server)) {
			log_message("invalid DNS");
			dns_server.s_addr = 0; /* keep an understandable state */
		}

		if (!inet_aton(answers[2], &gateway)) {
			log_message("invalid gateway");
			gateway.s_addr = 0; /* keep an understandable state */
		}

		if (IS_EXPERT) {
			char * questions_expert[] = { "Netmask", NULL };
			char ** answers_expert;
			results = ask_from_entries("Please enter additional network information.", questions_expert, &answers_expert, 16);
			if (results != RETURN_OK)
				return results;

			if (!inet_aton(answers_expert[0], &addr)) {
				error_message("Invalid netmask");
				return setup_network_interface(intf);
			}
		}
		else
			guess_netmask(intf, &addr);
		memcpy(&intf->netmask, &addr, sizeof(addr));

		*((uint32_t *) &intf->broadcast) = (*((uint32_t *) &intf->ip) &
						    *((uint32_t *) &intf->netmask)) | ~(*((uint32_t *) &intf->netmask));

		inet_aton("255.255.255.255", &addr);
		if (!memcmp(&addr, &intf->netmask, sizeof(addr))) {
			log_message("netmask is 255.255.255.255 -> point to point device");
			intf->network = gateway;
			intf->is_ptp = 1;
		} else {
			*((uint32_t *) &intf->network) = *((uint32_t *) &intf->ip) & *((uint32_t *) &intf->netmask);
			intf->is_ptp = 0;
		}
		intf->boot_proto = BOOTPROTO_STATIC;
	} else {
		error_message("Currently unsupported");
		return RETURN_ERROR;

		results = RETURN_ERROR; //setup_network_intf_as_dhcp(intf);
		if (results == RETURN_BACK)
			return setup_network_interface(intf);
		if (results == RETURN_ERROR)
			return results;
		intf->boot_proto = BOOTPROTO_DHCP;
		return RETURN_OK;
	}
	
	if (configure_net_device(intf))
		return RETURN_ERROR;
	return add_default_route();
}


static enum return_type configure_network(struct interface_info * intf)
{
	char ips[50];
	char * name;

	wait_message("Trying to guess hostname and domain...");
	strcpy(ips, inet_ntoa(intf->ip));
	name = mygethostbyaddr(ips);
	remove_wait_message();

	if (!name) {
		enum return_type results;
		char * questions[] = { "Host name", "Domain name", NULL };
		char * questions_auto[] = { "hostname", "domain" };
		char ** answers;
		char * boulet;

		log_message("reverse name lookup on self failed");

		results = ask_from_entries_auto("I could not guess hostname and domain name; please fill in this information. "
						"Valid answers are for example: `mybox' for hostname and `mynetwork.com' for domain name, "
						"for a machine called `mybox.mynetwork.com' on the Internet.",
						questions, &answers, 32, questions_auto);
		if (results != RETURN_OK)
			return results;

		hostname = answers[0];
		if ((boulet = strchr(hostname, '.')) != NULL)
			boulet[0] = '\0';
		domain = answers[1];
	}
	else {
		hostname = strdup(name);
		domain = strchr(strdup(name), '.') + 1;
	}

	return RETURN_OK;
}


static enum return_type bringup_networking(struct interface_info * intf)
{
	static struct interface_info loopback;
	enum { BRINGUP_NET, BRINGUP_CONF, BRINGUP_DONE } step = BRINGUP_NET;
	
	my_insmod("af_packet", ANY_DRIVER_TYPE, NULL);

//	if (intf->is_up == 1)
//		log_message("interface already up (with IP %s)", inet_ntoa(intf->ip));

	while (step != BRINGUP_DONE) {
		enum return_type results = RETURN_ERROR;
		switch (step) {
		case BRINGUP_NET:
			results = setup_network_interface(intf);
			if (results != RETURN_OK)
				return results;
			step = BRINGUP_CONF;
			break;
			
		case BRINGUP_CONF:
			write_resolvconf();
			results = configure_network(intf);
			if (results != RETURN_OK)
				step = BRINGUP_NET;
			else
				step = BRINGUP_DONE;
			break;
			
		case BRINGUP_DONE:
			break;
		}
	}

	write_resolvconf(); /* maybe we have now domain to write also */

	if (loopback.is_up == 0) {
		int rc;
		strcpy(loopback.device, "lo");
		loopback.is_ptp = 0;
		loopback.is_up = 0;
		loopback.ip.s_addr = htonl(0x7f000001);
		loopback.netmask.s_addr = htonl(0xff000000);
		loopback.broadcast.s_addr = htonl(0x7fffffff);
		loopback.network.s_addr = htonl(0x7f000000);
		rc = configure_net_device(&loopback);
		if (rc)
			return RETURN_ERROR;
	}

	return RETURN_OK;
}


static char * interface_select(void)
{
	char ** interfaces, ** ptr;
	char * choice;
	int i, count = 0;
	enum return_type results;

	interfaces = get_net_devices();

	ptr = interfaces;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

	if (count == 0) {
		error_message("No NET device found.");
		i = ask_insmod(NETWORK_DEVICES);
		if (i == RETURN_BACK)
			return NULL;
		return interface_select();
	}

	if (count == 1)
		return *interfaces;

	results = ask_from_list("Please choose the NET device to use for the installation.", interfaces, &choice);

	if (results != RETURN_OK)
		return NULL;

	return choice;
}



/* -=-=-- */


static enum return_type intf_select_and_up(void)
{
	static struct interface_info intf[20];
	static int num_interfaces = 0;
	struct interface_info * sel_intf = NULL;
	int i;
	char * iface = interface_select();
	
	if (iface == NULL)
		return RETURN_BACK;
	
	for (i = 0; i < num_interfaces ; i++)
		if (!strcmp(intf[i].device, iface))
			sel_intf = &(intf[i]);
	
	if (sel_intf == NULL) {
		sel_intf = &(intf[num_interfaces]);
		strcpy(sel_intf->device, iface);
		sel_intf->is_up = 0;
		num_interfaces++;
	}
	
	return bringup_networking(sel_intf);
}



enum return_type nfs_prepare(void)
{
	char * questions[] = { "NFS server name", DISTRIB_NAME " directory", NULL };
	char * questions_auto[] = { "server", "directory", NULL };
	char ** answers;
	char * nfsmount_location;
	enum return_type results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

	do {
		results = ask_from_entries_auto("Please enter the name or IP address of your NFS server, "
						"and the directory containing the " DISTRIB_NAME " installation.",
						questions, &answers, 40, questions_auto);
		if (results != RETURN_OK)
			return nfs_prepare();
		
		nfsmount_location = malloc(strlen(answers[0]) + strlen(answers[1]) + 2);
		strcpy(nfsmount_location, answers[0]);
		strcat(nfsmount_location, ":");
		strcat(nfsmount_location, answers[1]);
		
		if (my_mount(nfsmount_location, "/tmp/image", "nfs") == -1) {
			error_message("I can't mount the directory from the NFS server.");
			results = RETURN_BACK;
			continue;
		}

		if (access("/tmp/image/Mandrake/mdkinst", R_OK)) {
			error_message("That NFS volume does not seem to contain the " DISTRIB_NAME " Installation.");
			umount("/tmp/image");
			results = RETURN_BACK;
		}
	}
	while (results == RETURN_BACK);

	log_message("found the " DISTRIB_NAME " Installation, good news!");

	if (IS_SPECIAL_STAGE2) {
		if (load_ramdisk() != RETURN_OK) {
			error_message("Could not load program into memory");
			return nfs_prepare();
		}
	}

	if (IS_RESCUE)
		umount("/tmp/image"); /* TOCHECK */

	method_name = strdup("nfs");
	return RETURN_OK;
}


enum return_type ftp_prepare(void)
{
	error_message("Currently unsupported");
	return RETURN_ERROR;
}

enum return_type http_prepare(void)
{
	error_message("Currently unsupported");
	return RETURN_ERROR;
}
