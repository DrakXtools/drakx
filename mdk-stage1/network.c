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
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <stdio.h>
#include <netdb.h>
#include <resolv.h>

#include "stage1.h"
#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "mount.h"
#include "automatic.h"
#include "dhcp.h"
#include "adsl.h"
#include "url.h"
#include "dns.h"

#include "network.h"


static void error_message_net(void)  /* reduce code size */
{
	stg1_error_message("Could not configure network.");
}


int configure_net_device(struct interface_info * intf)
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
		log_message("interface already up, downing before reconfigure");

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

	if (intf->boot_proto != BOOTPROTO_DHCP && !streq(intf->device, "lo")) {
		/* I need to sleep a bit in order for kernel to finish
		   init of the network device; if not, first sendto() for
		   gethostbyaddr will get an EINVAL. */
		wait_message("Bringing up networking...");
		sleep(2);
		remove_wait_message();
	}

	return 0;
}

/* host network informations */ 
char * hostname = NULL;
char * domain = NULL;
struct in_addr gateway = { 0 };
struct in_addr dns_server = { 0 };
struct in_addr dns_server2 = { 0 };

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
	if (dns_server2.s_addr != 0)
		fprintf(f, "nameserver %s\n", inet_ntoa(dns_server2));

	fclose(f);
	res_init();		/* reinit the resolver so DNS changes take affect */

	return 0;
}


static int save_netinfo(struct interface_info * intf) {
	char * file_network = "/tmp/network";
	char file_intf[500];
	FILE * f;
	
	f = fopen(file_network, "w");
	if (!f) {
		log_perror(file_network);
		return -1;
	}

	fprintf(f, "NETWORKING=yes\n");
	fprintf(f, "FORWARD_IPV4=false\n");

	if (hostname)
		fprintf(f, "HOSTNAME=%s\n", hostname);
	if (domain)
		fprintf(f, "DOMAINNAME=%s\n", domain);
	if (dhcp_hostname)
		fprintf(f, "DHCP_HOSTNAME=%s\n", dhcp_hostname);
	
	if (gateway.s_addr != 0)
		fprintf(f, "GATEWAY=%s\n", inet_ntoa(gateway));

	fclose(f);

	
	strcpy(file_intf, "/tmp/ifcfg-");
	strcat(file_intf, intf->device);

	f = fopen(file_intf, "w");
	if (!f) {
		log_perror(file_intf);
		return -1;
	}

	fprintf(f, "DEVICE=%s\n", intf->device);

	if (intf->boot_proto == BOOTPROTO_DHCP)
		fprintf(f, "BOOTPROTO=dhcp\n");
	else if (intf->boot_proto == BOOTPROTO_STATIC) {
		fprintf(f, "BOOTPROTO=static\n");
		fprintf(f, "IPADDR=%s\n", inet_ntoa(intf->ip));
		fprintf(f, "NETMASK=%s\n", inet_ntoa(intf->netmask));
		fprintf(f, "NETWORK=%s\n", inet_ntoa(intf->network));
		fprintf(f, "BROADCAST=%s\n", inet_ntoa(intf->broadcast));
	} else if (intf->boot_proto == BOOTPROTO_ADSL_PPPOE) {
		fprintf(f, "BOOTPROTO=adsl_pppoe\n");
		fprintf(f, "USER=%s\n", intf->user);
		fprintf(f, "PASS=%s\n", intf->pass);
	}

	fclose(f);

	return 0;
}


char * guess_netmask(char * ip_addr)
{
	struct in_addr addr;
	unsigned long int tmp;

	if (streq(ip_addr, "") || !inet_aton(ip_addr, &addr))
		return "";

	log_message("guessing netmask");

	tmp = ntohl(addr.s_addr);
	
	if (((tmp & 0xFF000000) >> 24) <= 127)
		return "255.0.0.0";
	else if (((tmp & 0xFF000000) >> 24) <= 191)
		return "255.255.0.0";
	else 
		return "255.255.255.0";
}


static void static_ip_callback(char ** strings)
{
	struct in_addr addr;

	if (!inet_aton(strings[0], &addr))
		return;

	if (!strcmp(strings[1], "")) {
		char * ptr;
		strings[1] = strdup(strings[0]);
		ptr = strrchr(strings[1], '.');
		if (ptr)
			*(ptr+1) = '\0';
	}

	if (!strcmp(strings[2], ""))
		strings[2] = strdup(strings[1]);

	if (!strcmp(strings[3], ""))
		strings[3] = strdup(guess_netmask(strings[0]));
}


static enum return_type setup_network_interface(struct interface_info * intf)
{
	enum return_type results;
	char * bootprotos[] = { "Static", "DHCP", "ADSL", NULL };
	char * bootprotos_auto[] = { "static", "dhcp", "adsl" };
	char * choice;

	results = ask_from_list_auto("Please choose the desired IP attribution.", bootprotos, &choice, "network", bootprotos_auto);
	if (results != RETURN_OK)
		return results;

	if (!strcmp(choice, "Static")) {
		char * questions[] = { "IP of this machine", "IP of DNS", "IP of default gateway", "Netmask", NULL };
		char * questions_auto[] = { "ip", "dns", "gateway", "netmask" };
		static char ** answers = NULL;
		struct in_addr addr;

		results = ask_from_entries_auto("Please enter the network information. (leave netmask void for Internet standard)",
						questions, &answers, 16, questions_auto, static_ip_callback);
		if (results != RETURN_OK)
			return setup_network_interface(intf);

		if (streq(answers[0], "") || !inet_aton(answers[0], &addr)) {
			stg1_error_message("Invalid IP address.");
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

		if ((streq(answers[3], "") && inet_aton(guess_netmask(answers[0]), &addr))
		    || inet_aton(answers[3], &addr))
			memcpy(&intf->netmask, &addr, sizeof(addr));
		else {
			stg1_error_message("Invalid netmask.");
			return setup_network_interface(intf);
		}

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

		if (configure_net_device(intf))
			return RETURN_ERROR;

	} else if (streq(choice, "DHCP")) {
		results = perform_dhcp(intf);

		if (results == RETURN_BACK)
			return setup_network_interface(intf);
		if (results == RETURN_ERROR)
			return results;
		intf->boot_proto = BOOTPROTO_DHCP;

		if (configure_net_device(intf))
			return RETURN_ERROR;

	} else if (streq(choice, "ADSL")) {
		results = perform_adsl(intf);

		if (results == RETURN_BACK)
			return setup_network_interface(intf);
		if (results == RETURN_ERROR)
			return results;
	} else
		return RETURN_ERROR;
	
	return add_default_route();
}


static enum return_type configure_network(struct interface_info * intf)
{
	char * dnshostname;

	if (hostname && domain)
		return RETURN_OK;

	dnshostname = mygethostbyaddr(inet_ntoa(intf->ip));

	if (dnshostname) {
		hostname = strdup(dnshostname);
		domain = strchr(strdup(hostname), '.') + 1;
		log_message("got hostname and domain from dns entry, %s and %s", hostname, domain);
		return RETURN_OK;
	}

	log_message("reverse name lookup on self failed");

	if (domain)
		return RETURN_OK;

	if (dns_server.s_addr != 0) {
		wait_message("Trying to resolve dns...");
		dnshostname = mygethostbyaddr(inet_ntoa(dns_server));
		remove_wait_message();
	}

	if (dnshostname) {
		domain = strchr(strdup(dnshostname), '.') + 1;
		log_message("got domain from DNS fullname, %s", domain);
	} else {
		enum return_type results;
		char * questions[] = { "Host name", "Domain name", NULL };
		char * questions_auto[] = { "hostname", "domain" };
		static char ** answers = NULL;
		char * boulet;
		
		log_message("reverse name lookup on DNS failed");
		
		results = ask_from_entries_auto("I could not guess hostname and domain name; please fill in this information. "
						"Valid answers are for example: `mybox' for hostname and `mynetwork.com' for "
						"domain name, for a machine called `mybox.mynetwork.com' on the Internet.",
						questions, &answers, 32, questions_auto, NULL);
		if (results != RETURN_OK)
			return results;
		
		hostname = answers[0];
		if ((boulet = strchr(hostname, '.')) != NULL)
			boulet[0] = '\0';
		domain = answers[1];
	}

	return RETURN_OK;
}


static enum return_type bringup_networking(struct interface_info * intf)
{
	static struct interface_info loopback;
	enum return_type results = RETURN_ERROR;
	
	my_insmod("af_packet", ANY_DRIVER_TYPE, NULL);

	while (results != RETURN_OK) {
		results = setup_network_interface(intf);
		if (results != RETURN_OK)
			return results;
		write_resolvconf();
		results = configure_network(intf);
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
	char * descriptions[50];
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
		stg1_error_message("No NET device found.\n"
				   "Hint: if you're using a Laptop, note that PCMCIA Network adapters are now supported either with `pcmcia.img' or `network.img', please try both these bootdisks.");
		i = ask_insmod(NETWORK_DEVICES);
		if (i == RETURN_BACK)
			return NULL;
		return interface_select();
	}

	if (count == 1)
		return *interfaces;

	i = 0;
	while (interfaces[i]) {
		descriptions[i] = get_net_intf_description(interfaces[i]);
		i++;
	}

	results = ask_from_list_comments_auto("Please choose the NET device to use for the installation.",
					      interfaces, descriptions, &choice, "interface", interfaces);

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
	enum return_type results;
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
	
	results = bringup_networking(sel_intf);

	if (results == RETURN_OK)
		save_netinfo(sel_intf);
	
	return results;
}



enum return_type nfs_prepare(void)
{
	char * questions[] = { "NFS server name", DISTRIB_NAME " directory", NULL };
	char * questions_auto[] = { "server", "directory", NULL };
	static char ** answers = NULL;
	char * nfsmount_location;
	enum return_type results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

	do {
		results = ask_from_entries_auto("Please enter the name or IP address of your NFS server, "
						"and the directory containing the " DISTRIB_NAME " Distribution.",
						questions, &answers, 40, questions_auto, NULL);
		if (results != RETURN_OK || streq(answers[0], "")) {
			unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */
			return nfs_prepare();
		}
		
		nfsmount_location = malloc(strlen(answers[0]) + strlen(answers[1]) + 2);
		strcpy(nfsmount_location, answers[0]);
		strcat(nfsmount_location, ":");
		strcat(nfsmount_location, answers[1]);
		
		if (my_mount(nfsmount_location, IMAGE_LOCATION, "nfs", 0) == -1) {
			stg1_error_message("I can't mount the directory from the NFS server.");
			results = RETURN_BACK;
			continue;
		}

		if (access(IMAGE_LOCATION LIVE_LOCATION, R_OK)) {
			stg1_error_message("That NFS volume does not seem to contain the " DISTRIB_NAME " Distribution.");
			umount(IMAGE_LOCATION);
			results = RETURN_BACK;
		}
	}
	while (results == RETURN_BACK);

	log_message("found the " DISTRIB_NAME " Installation, good news!");

	if (IS_SPECIAL_STAGE2) {
		if (load_ramdisk() != RETURN_OK) {
			stg1_error_message("Could not load program into memory.");
			return nfs_prepare();
		}
	}

	if (IS_RESCUE)
		umount(IMAGE_LOCATION);

	method_name = strdup("nfs");
	return RETURN_OK;
}


enum return_type ftp_prepare(void)
{
	char * questions[] = { "FTP server", DISTRIB_NAME " directory", "Login", "Password", NULL };
	char * questions_auto[] = { "server", "directory", "user", "pass", NULL };
	static char ** answers = NULL;
	enum return_type results;

	if (!ramdisk_possible()) {
		stg1_error_message("FTP install needs more than %d Mbytes of memory (detected %d Mbytes).",
			      MEM_LIMIT_RAMDISK, total_memory());
		return RETURN_ERROR;
	}

	results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

	do {
		char location_full[500];
		int ftp_serv_response;
		int fd, size;

		results = ask_from_entries_auto("Please enter the name or IP address of the FTP server, "
						"the directory containing the " DISTRIB_NAME " Distribution, "
						"and the login/pass if necessary (leave login blank for anonymous).",
						questions, &answers, 40, questions_auto, NULL);
		if (results != RETURN_OK || streq(answers[0], "")) {
			unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */
			return ftp_prepare();
		}

		log_message("FTP: trying to connect to %s", answers[0]);

		ftp_serv_response = ftp_open_connection(answers[0], answers[2], answers[3], "");
		if (ftp_serv_response < 0) {
			log_message("FTP: error connect %d", ftp_serv_response);
			if (ftp_serv_response == FTPERR_BAD_HOSTNAME)
				stg1_error_message("Error: bad hostname.");
			else if (ftp_serv_response == FTPERR_FAILED_CONNECT)
				stg1_error_message("Error: failed to connect to remote host.");
			else
				stg1_error_message("Error: couldn't connect.");
			results = RETURN_BACK;
			continue;
		}
		strcpy(location_full, answers[1]);
		strcat(location_full, get_ramdisk_realname());

		log_message("FTP: trying to retrieve %s", location_full);

		fd = ftp_start_download(ftp_serv_response, location_full, &size);
		if (fd < 0) {
			log_message("FTP: error get %d", fd);
			if (fd == FTPERR_PASSIVE_ERROR)
				stg1_error_message("Error: error with passive connection.");
			else if (fd == FTPERR_FILE_NOT_FOUND)
				stg1_error_message("Error: file not found (%s).", location_full);
			else if (fd == FTPERR_BAD_SERVER_RESPONSE)
				stg1_error_message("Error: bad server response (server too busy?).");
			else
				stg1_error_message("Error: couldn't retrieve Installation program.");
			results = RETURN_BACK;
			continue;
		}

		log_message("FTP: size of download %d bytes", size);
		
		results = load_ramdisk_fd(fd, size);
		if (results == RETURN_OK)
			ftp_end_data_command(ftp_serv_response);
		else
			return results;

		method_name = strdup("ftp");
		add_to_env("HOST", answers[0]);
		add_to_env("PREFIX", answers[1]);
		if (strcmp(answers[2], "")) {
			add_to_env("LOGIN", answers[2]);
			add_to_env("PASSWORD", answers[3]);
		}
	}
	while (results == RETURN_BACK);

	return RETURN_OK;
}

enum return_type http_prepare(void)
{
	char * questions[] = { "HTTP server", DISTRIB_NAME " directory", NULL };
	char * questions_auto[] = { "server", "directory", NULL };
	static char ** answers = NULL;
	enum return_type results;

	if (!ramdisk_possible()) {
		stg1_error_message("HTTP install needs more than %d Mbytes of memory (detected %d Mbytes).",
			      MEM_LIMIT_RAMDISK, total_memory());
		return RETURN_ERROR;
	}

	results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

	do {
		char location_full[500];
		int fd, size;

		results = ask_from_entries_auto("Please enter the name or IP address of the HTTP server, "
						"and the directory containing the " DISTRIB_NAME " Distribution.",
						questions, &answers, 40, questions_auto, NULL);
		if (results != RETURN_OK || streq(answers[0], "")) {
			unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */
			return http_prepare();
		}

		strcpy(location_full, answers[1]);
		strcat(location_full, get_ramdisk_realname());

		log_message("HTTP: trying to retrieve %s from %s", location_full, answers[0]);
		
		fd = http_download_file(answers[0], location_full, &size);
		if (fd < 0) {
			log_message("HTTP: error %d", fd);
			if (fd == FTPERR_FAILED_CONNECT)
				stg1_error_message("Error: couldn't connect to server.");
			else
				stg1_error_message("Error: couldn't get file (%s).", location_full);
			results = RETURN_BACK;
			continue;
		}

		log_message("HTTP: size of download %d bytes", size);
		
		if (load_ramdisk_fd(fd, size) != RETURN_OK)
			return RETURN_ERROR;

		method_name = strdup("http");
		sprintf(location_full, "http://%s/%s", answers[0], answers[1]);
		add_to_env("URLPREFIX", location_full);
	}
	while (results == RETURN_BACK);

	return RETURN_OK;

}
