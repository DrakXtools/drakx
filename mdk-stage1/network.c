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

#include "stage1.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <net/route.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <stdio.h>
#include <netdb.h>
#include <resolv.h>
#include <sys/utsname.h>

#include "frontend.h"
#include "modules.h"
#include "probing.h"
#include "log.h"
#include "tools.h"
#include "utils.h"
#include "mount.h"
#include "automatic.h"
#include "dhcp.h"
#include "adsl.h"
#include "url.h"
#include "dns.h"

#include "network.h"
#include "directory.h"
#include "wireless.h"

#ifndef DISABLE_KA
#include "ka.h"
#endif

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


static int write_resolvconf(void)
{
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


static int save_netinfo(struct interface_info * intf)
{
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

	if (hostname && !intf->boot_proto == BOOTPROTO_DHCP)
		fprintf(f, "HOSTNAME=%s\n", hostname);
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

	if (intf->boot_proto == BOOTPROTO_DHCP) {
		fprintf(f, "BOOTPROTO=dhcp\n");
		if (dhcp_hostname && !streq(dhcp_hostname, ""))
			fprintf(f, "DHCP_HOSTNAME=%s\n", dhcp_hostname);
	} else if (intf->boot_proto == BOOTPROTO_STATIC) {
		fprintf(f, "BOOTPROTO=static\n");
		fprintf(f, "IPADDR=%s\n", inet_ntoa(intf->ip));
		fprintf(f, "NETMASK=%s\n", inet_ntoa(intf->netmask));
		fprintf(f, "NETWORK=%s\n", inet_ntoa(intf->network));
		fprintf(f, "BROADCAST=%s\n", inet_ntoa(intf->broadcast));
		if (domain)
			fprintf(f, "DOMAIN=%s\n", domain);
		if (dns_server.s_addr != 0)
			fprintf(f, "DNS1=%s\n", inet_ntoa(dns_server));
		if (dns_server2.s_addr != 0)
			fprintf(f, "DNS2=%s\n", inet_ntoa(dns_server2));
	} else if (intf->boot_proto == BOOTPROTO_ADSL_PPPOE) {
		fprintf(f, "BOOTPROTO=adsl_pppoe\n");
		fprintf(f, "USER=%s\n", intf->user);
		fprintf(f, "PASS=%s\n", intf->pass);
		fprintf(f, "ACNAME=%s\n", intf->acname);
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


char * guess_domain_from_hostname(char *hostname)
{
	char *domain = strchr(strdup(hostname), '.');
	if (!domain || domain[1] == '\0') {
		log_message("unable to guess domain from hostname: %s", hostname);
		return NULL;
	}
	return domain + 1; /* skip '.' */
}


static void static_ip_callback(char ** strings)
{
	struct in_addr addr;

        static int done = 0;
        if (done)
                return;
	if (streq(strings[0], "") || !inet_aton(strings[0], &addr))
		return;
        done = 1;

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
	char * bootprotos[] = { "DHCP", "Static", "ADSL", NULL };
	char * bootprotos_auto[] = { "dhcp", "static", "adsl" };
	char * choice;

	results = ask_from_list_auto("Please select your network connection type.", bootprotos, &choice, "network", bootprotos_auto);
	if (results != RETURN_OK)
		return results;

	if (!strcmp(choice, "Static")) {
		char * questions[] = { "IP of this machine", "IP of DNS", "IP of default gateway", "Netmask", NULL };
		char * questions_auto[] = { "ip", "dns", "gateway", "netmask" };
		static char ** answers = NULL;
		struct in_addr addr;

		results = ask_from_entries_auto("Please enter the network information. (leave netmask blank for Internet standard)",
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

		if (streq(answers[0], answers[1])) {
			log_message("IP and DNS are the same, guess you don't want a DNS, disabling it");
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
		if (intf->boot_proto == BOOTPROTO_STATIC)
			hostname = strdup(dnshostname);
		domain = guess_domain_from_hostname(dnshostname);
		if (domain) {
			log_message("got hostname and domain from dns entry, %s and %s", dnshostname, domain);
			return RETURN_OK;
		}
	} else
		log_message("reverse name lookup on self failed");

	if (domain)
		return RETURN_OK;

	dnshostname = NULL;
	if (dns_server.s_addr != 0) {
		wait_message("Trying to resolve dns...");
		dnshostname = mygethostbyaddr(inet_ntoa(dns_server));
		remove_wait_message();
		if (dnshostname) {
			log_message("got DNS fullname, %s", dnshostname);
			domain = guess_domain_from_hostname(dnshostname);
		} else
			log_message("reverse name lookup on DNS failed");
	} else
		log_message("no DNS, unable to guess domain");

	if (domain) {
		log_message("got domain from DNS fullname, %s", domain);
	} else {
		enum return_type results;
		char * questions[] = { "Host name", "Domain name", NULL };
		char * questions_auto[] = { "hostname", "domain" };
		static char ** answers = NULL;
		char * boulet;

		if (dhcp_hostname || dhcp_domain) {
		    answers = (char **) malloc(sizeof(questions));
		    answers[0] = strdup(dhcp_hostname);
		    answers[1] = strdup(dhcp_domain);
		}

		if (!dhcp_hostname || !dhcp_domain) {
		    results = ask_from_entries_auto("I could not guess hostname and domain name; please fill in this information. "
						    "Valid answers are for example: `mybox' for hostname and `mynetwork.com' for "
						    "domain name, for a machine called `mybox.mynetwork.com' on the Internet.",
						    questions, &answers, 32, questions_auto, NULL);
		    if (results != RETURN_OK)
			return results;
		}
		
		hostname = answers[0];
		if ((boulet = strchr(hostname, '.')) != NULL)
			boulet[0] = '\0';
		domain = answers[1];
	}

	log_message("using hostname %s", hostname);
	log_message("using domain %s", domain);

	return RETURN_OK;
}


static enum return_type bringup_networking(struct interface_info * intf)
{
	static struct interface_info loopback;
	enum return_type results;
	
	my_insmod("af_packet", ANY_DRIVER_TYPE, NULL, 1);

	do {
		results = configure_wireless(intf->device);
	} while (results == RETURN_ERROR);

	if (results == RETURN_BACK)
		return RETURN_BACK;

	do {
		results = setup_network_interface(intf);
		if (results != RETURN_OK)
			return results;
		write_resolvconf();
		results = configure_network(intf);
	} while (results == RETURN_ERROR);

	if (results == RETURN_BACK)
		return bringup_networking(intf);

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


static char * auto_select_up_intf(int detection_mode)
{
#define SIOCETHTOOL     0x8946
#define ETHTOOL_GLINK           0x0000000a /* Get link status (ethtool_value) */

	struct ethtool_value {
		uint32_t     cmd;
		uint32_t     data;
	};

	char ** interfaces, ** ptr;
	interfaces = get_net_devices();

	int s;
	s = socket(AF_INET, SOCK_DGRAM, 0);
	if (s < 0) {
		return NULL;
	}

	ptr = interfaces;
	while (ptr && *ptr) {
		if (detection_mode != AUTO_DETECTION_WIRED || !wireless_is_aware(s, *interfaces)) {
			struct ifreq ifr;
			struct ethtool_value edata;
			strncpy(ifr.ifr_name, *ptr, IFNAMSIZ);
			edata.cmd = ETHTOOL_GLINK;
			ifr.ifr_data = (caddr_t)&edata;
			if (ioctl(s, SIOCETHTOOL, &ifr) == 0 && edata.data) {
				close(s);
				log_message("NETWORK: choosing interface %s (link beat detected)", *ptr);
				return *ptr;
			}
		}
		ptr++;
	}

	log_message("NETWORK: no interface has a link beat");

	if (detection_mode == AUTO_DETECTION_WIRED) {
		ptr = interfaces;
		while (ptr && *ptr) {
			if (!wireless_is_aware(s, *interfaces)) {
				close(s);
				log_message("NETWORK: choosing interface %s (wired interface)", *ptr);
				return *ptr;
			}
			ptr++;
		}
		log_message("NETWORK: no interface is wired");
	}

	close(s);

	return NULL;
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

	/* this can't be done in ask_from_list_comments_auto because "auto" and "wired" are not in the interfaces list */
	if (IS_AUTOMATIC) {
		enum auto_detection_type auto_detect = AUTO_DETECTION_NONE;
		if (streq(get_auto_value("interface"), "auto"))
			auto_detect = AUTO_DETECTION_ALL;
		else if (streq(get_auto_value("interface"), "wired"))
			auto_detect = AUTO_DETECTION_WIRED;
		if (auto_detect != AUTO_DETECTION_NONE) {
			choice = auto_select_up_intf(auto_detect);
			if (choice)
				return choice;
		}
	}

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

static enum return_type get_http_proxy(char **http_proxy_host, char **http_proxy_port)
{
	char *questions[] = { "HTTP proxy host", "HTTP proxy port", NULL };
	char *questions_auto[] = { "proxy_host", "proxy_port", NULL };
	static char ** answers = NULL;
	enum return_type results;
	
	results = ask_from_entries_auto("Please enter HTTP proxy host and port if you need it, else leave them blank or cancel.",
					questions, &answers, 40, questions_auto, NULL);
	if (results == RETURN_OK) {
		*http_proxy_host = answers[0];
		*http_proxy_port = answers[1];
	} else {
		*http_proxy_host = NULL;
		*http_proxy_port = NULL;
	}

	return results;
}


static int url_split(const char *url, const char *protocol, char **host, char **path)
{
	char *protocol_sep, *host_sep;

	protocol_sep = strstr(url, "://");
	if (!protocol_sep) {
		log_message("NETWORK: no protocol in \"%s\"", url);
		return -1;
	}

	if (strncmp(protocol, url, protocol_sep - url))
		return -1;

	url = protocol_sep + 3;
	host_sep = strchr(url, '/');
	if (!host_sep || host_sep == url) {
		log_message("NETWORK: no hostname in \"%s\"", url);
		return -1;
	}

	*host = strndup(url, host_sep - url);
	*path = strdup(host_sep);

	return 0;
}

#define MIRRORLIST_MAX_ITEMS 500
typedef char *mirrorlist_t[2][MIRRORLIST_MAX_ITEMS+1];

static enum return_type get_mirrorlist(mirrorlist_t mirrorlist, int start, char *version, const char *protocol, char *http_proxy_host, char *http_proxy_port) {
	int fd, size, line_pos = 0;
	char path[1024];
	char line[1024];
	char type[100] = DISTRIB_TYPE;
	int mirror_idx = start;

	int use_http_proxy = http_proxy_host && http_proxy_port && !streq(http_proxy_host, "") && !streq(http_proxy_port, "");
	lowercase(type);
	snprintf(path, sizeof(path), "%s/%s.%s.%s.list", MIRRORLIST_PATH, type, version, ARCH);

	fd = http_download_file(MIRRORLIST_HOST, path, &size, use_http_proxy ? "http" : NULL, http_proxy_host, http_proxy_port);
	if (fd < 0) {
		log_message("HTTP: unable to get mirrors list from %s (%s)", MIRRORLIST_HOST, path);
		return RETURN_ERROR;
	}

	while (read(fd, line + line_pos, 1) > 0) {
		if (line[line_pos] == '\n') {
			char *url;
			line[line_pos] = '\0';
			line_pos = 0;

			/* skip medium if it does not look like a distrib path */
			if (!strstr(line, ",type=distrib,"))
				continue;

			url = strstr(line, ",url=");
			if (!url)
				continue;
			url += 5;

			if (url_split(url, protocol, &mirrorlist[0][mirror_idx], &mirrorlist[1][mirror_idx]) < 0)
				continue;

			mirror_idx++;
		} else {
			line_pos++;
		}

		if (mirror_idx >= MIRRORLIST_MAX_ITEMS)
			break;
	}
	close(fd);

	mirrorlist[0][mirror_idx] = NULL;
	mirrorlist[1][mirror_idx] = NULL;

        return RETURN_OK;
}

static int choose_mirror_from_host_list(mirrorlist_t mirrorlist, char **selected_host, char **filepath)
{
	enum return_type results;
	int mirror_idx = 0;

	do {
		results = ask_from_list_index("Please select a mirror from the list below.",
					      mirrorlist[0], NULL, &mirror_idx);

		if (results == RETURN_BACK) {
			return RETURN_ERROR;
		} else if (results == RETURN_OK) {
			if (mirror_idx == 0) {
				/* enter the mirror manually */
				return RETURN_OK;
			}
			*selected_host = strdup(mirrorlist[0][mirror_idx]);
			*filepath = strdup(mirrorlist[1][mirror_idx]);
			return RETURN_OK;
		}
	} while (results == RETURN_ERROR);

	return RETURN_ERROR;
}


static int choose_mirror_from_list(char *http_proxy_host, char *http_proxy_port, const char *protocol, char **selected_host, char **filepath)
{
	enum return_type results;
	char *versions[] = { "Specify the mirror manually", DISTRIB_VERSION, NULL };
	char *version = DISTRIB_VERSION;

	do {
		results = ask_from_list("Please select a medium from the list below.", versions, &version);

		if (results == RETURN_BACK) {
			return RETURN_BACK;
		} else if (results == RETURN_OK) {
			if (!strcmp(version, versions[0])) {
				/* enter the mirror manually */
				return RETURN_OK;
			} else {
				/* a medium has been selected */
				mirrorlist_t mirrorlist;
				mirrorlist[0][0] = "Specify the mirror manually";
				mirrorlist[1][0] = NULL;

				results = get_mirrorlist(mirrorlist, 1, version, protocol, http_proxy_host, http_proxy_port);
				if (results == RETURN_ERROR)
					return RETURN_ERROR;

				results = choose_mirror_from_host_list(mirrorlist, selected_host, filepath);
			}
		}
	} while (results == RETURN_ERROR);

	return results;
}


/* -=-=-- */


enum return_type intf_select_and_up()
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
	enum return_type results = intf_select_and_up(NULL, NULL);

	if (results != RETURN_OK)
		return results;

	do {
		results = ask_from_entries_auto("Please enter the name or IP address of your NFS server, "
						"and the directory containing the " DISTRIB_NAME " Distribution.",
						questions, &answers, 40, questions_auto, NULL);
		if (results != RETURN_OK || streq(answers[0], "")) {
			unset_automatic(); /* we are in a fallback mode */
			return nfs_prepare();
		}
		
		nfsmount_location = malloc(strlen(answers[0]) + strlen(answers[1]) + 2);
		strcpy(nfsmount_location, answers[0]);
		strcat(nfsmount_location, ":");
		strcat(nfsmount_location, answers[1]);
		
		if (my_mount(nfsmount_location, MEDIA_LOCATION, "nfs", 0) == -1) {
			stg1_error_message("I can't mount the directory from the NFS server.");
			results = RETURN_BACK;
			continue;
		}
		free(nfsmount_location); nfsmount_location = NULL;

		results = try_with_directory(MEDIA_LOCATION, "nfs", "nfs-iso");
		if (results != RETURN_OK)
			umount(MEDIA_LOCATION);
		if (results == RETURN_ERROR)
                        return RETURN_ERROR;
	}
	while (results == RETURN_BACK);

	return RETURN_OK;
}


enum return_type ftp_prepare(void)
{
	char * questions[] = { "FTP server", DISTRIB_NAME " directory", "Login", "Password", NULL };
	char * questions_auto[] = { "server", "directory", "user", "pass", NULL };
	static char ** answers = NULL;
	enum return_type results;
	struct utsname kernel_uname;
	char *http_proxy_host, *http_proxy_port;
	int use_http_proxy;

	if (!ramdisk_possible()) {
		stg1_error_message("FTP install needs more than %d Mbytes of memory (detected %d Mbytes). You may want to try an NFS install.",
				   MEM_LIMIT_DRAKX, total_memory());
		return RETURN_ERROR;
	}

	results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

	get_http_proxy(&http_proxy_host, &http_proxy_port);
	use_http_proxy = http_proxy_host && http_proxy_port && !streq(http_proxy_host, "") && !streq(http_proxy_port, "");

	uname(&kernel_uname);

	do {
		char location_full[500];
		int ftp_serv_response = -1;
		int fd, size;
		char ftp_hostname[500];

		if (!IS_AUTOMATIC) {
			if (answers == NULL)
				answers = (char **) malloc(sizeof(questions));

			results = choose_mirror_from_list(http_proxy_host, http_proxy_port, "ftp", &answers[0], &answers[1]);

			if (results == RETURN_BACK)
				return ftp_prepare();

                        if (use_http_proxy) {
                            results = ask_yes_no("Do you want to use this HTTP proxy for FTP connections too ?");

			    if (results == RETURN_BACK)
				return ftp_prepare();

                            use_http_proxy = results == RETURN_OK;
                        }
		}

		results = ask_from_entries_auto("Please enter the name or IP address of the FTP server, "
						"the directory containing the " DISTRIB_NAME " Distribution, "
						"and the login/pass if necessary (leave login blank for anonymous). ",
						questions, &answers, 40, questions_auto, NULL);
		if (results != RETURN_OK || streq(answers[0], "")) {
			unset_automatic(); /* we are in a fallback mode */
			return ftp_prepare();
		}

		strcpy(location_full, answers[1][0] == '/' ? "" : "/");
		strcat(location_full, answers[1]);

		if (use_http_proxy) {
		        log_message("FTP: don't connect to %s directly, will use proxy", answers[0]);
		} else {
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
                }

		strcat(location_full, COMPRESSED_FILE_REL("/"));

		log_message("FTP: trying to retrieve %s", location_full);

		if (use_http_proxy) {
			if (strcmp(answers[2], "")) {
			        strcpy(ftp_hostname, answers[2]); /* user name */
				strcat(ftp_hostname, ":");
				strcat(ftp_hostname, answers[3]); /* password */
				strcat(ftp_hostname, "@");
			} else {
			    strcpy(ftp_hostname, "");
			}
			strcat(ftp_hostname, answers[0]);
			fd = http_download_file(ftp_hostname, location_full, &size, "ftp", http_proxy_host, http_proxy_port);
		} else {
		        fd = ftp_start_download(ftp_serv_response, location_full, &size);
		}

		if (fd < 0) {
			char *msg = str_ftp_error(fd);
			log_message("FTP: error get %d for remote file %s", fd, location_full);
			stg1_error_message("Error: %s.", msg ? msg : "couldn't retrieve Installation program");
			results = RETURN_BACK;
			continue;
		}

		log_message("FTP: size of download %d bytes", size);
		
		results = load_compressed_fd(fd, size);
		if (results == RETURN_OK) {
		        if (!use_http_proxy)
			        ftp_end_data_command(ftp_serv_response);
		} else {
			unset_automatic(); /* we are in a fallback mode */
			return results;
		}

		if (use_http_proxy) {
                        add_to_env("METHOD", "http");
		        sprintf(location_full, "ftp://%s%s", ftp_hostname, answers[1]);
		        add_to_env("URLPREFIX", location_full);
			add_to_env("PROXY", http_proxy_host);
			add_to_env("PROXYPORT", http_proxy_port);
		} else {
                        add_to_env("METHOD", "ftp");
		        add_to_env("HOST", answers[0]);
			add_to_env("PREFIX", answers[1]);
			if (!streq(answers[2], "")) {
			        add_to_env("LOGIN", answers[2]);
				add_to_env("PASSWORD", answers[3]);
			}
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
	char *http_proxy_host, *http_proxy_port;

	if (!ramdisk_possible()) {
		stg1_error_message("HTTP install needs more than %d Mbytes of memory (detected %d Mbytes). You may want to try an NFS install.",
				   MEM_LIMIT_DRAKX, total_memory());
		return RETURN_ERROR;
	}

	results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

        get_http_proxy(&http_proxy_host, &http_proxy_port);

	do {
		char location_full[500];
		int fd, size;
		int use_http_proxy;

		if (!IS_AUTOMATIC) {
			if (answers == NULL)
				answers = (char **) malloc(sizeof(questions));

			results = choose_mirror_from_list(http_proxy_host, http_proxy_port, "http", &answers[0], &answers[1]);

			if (results == RETURN_BACK)
				return ftp_prepare();
		}

		results = ask_from_entries_auto("Please enter the name or IP address of the HTTP server, "
						"and the directory containing the " DISTRIB_NAME " Distribution.",
						questions, &answers, 40, questions_auto, NULL);
		if (results != RETURN_OK || streq(answers[0], "")) {
			unset_automatic(); /* we are in a fallback mode */
			return http_prepare();
		}

		strcpy(location_full, answers[1][0] == '/' ? "" : "/");
		strcat(location_full, answers[1]);
		strcat(location_full, COMPRESSED_FILE_REL("/"));

		log_message("HTTP: trying to retrieve %s from %s", location_full, answers[0]);
		
		use_http_proxy = http_proxy_host && http_proxy_port && !streq(http_proxy_host, "") && !streq(http_proxy_port, "");

		fd = http_download_file(answers[0], location_full, &size, use_http_proxy ? "http" : NULL, http_proxy_host, http_proxy_port);
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
		
		if (load_compressed_fd(fd, size) != RETURN_OK) {
			unset_automatic(); /* we are in a fallback mode */
			return RETURN_ERROR;
                }

                add_to_env("METHOD", "http");
		sprintf(location_full, "http://%s%s%s", answers[0], answers[1][0] == '/' ? "" : "/", answers[1]);
		add_to_env("URLPREFIX", location_full);
                if (!streq(http_proxy_host, ""))
			add_to_env("PROXY", http_proxy_host);
                if (!streq(http_proxy_port, ""))
			add_to_env("PROXYPORT", http_proxy_port);
	}
	while (results == RETURN_BACK);

	return RETURN_OK;

}

#ifndef DISABLE_KA
enum return_type ka_prepare(void)
{
	enum return_type results;

	if (!ramdisk_possible()) {
		stg1_error_message("KA install needs more than %d Mbytes of memory (detected %d Mbytes).",
				   MEM_LIMIT_DRAKX, total_memory());
		return RETURN_ERROR;
	}

	results = intf_select_and_up();

	if (results != RETURN_OK)
		return results;

	return perform_ka();
}
#endif
