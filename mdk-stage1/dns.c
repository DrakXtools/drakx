/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2000 Mandriva
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

// dietlibc can do hostname lookup, whereas glibc can't when linked statically :-(

#if defined(__dietlibc__)

#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <netdb.h>
#include <sys/socket.h>
#include <resolv.h>

#include "network.h"
#include "log.h"

#include "dns.h"

int mygethostbyname(char * name, struct in_addr * addr)
{
	struct addrinfo hints, *res, *p;
	int status;
	char ipstr[INET6_ADDRSTRLEN];

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_INET; //AF_UNSPEC for both IPv4 & IPv6
	hints.ai_socktype = SOCK_STREAM;

	/* prevent from timeouts */
	if (_res.nscount == 0) 
		return -1;

	if ((status = getaddrinfo(name, NULL, &hints, &res)) != 0) {
          log_message("getaddrinfo: %s\n", gai_strerror(status));
          return -1;
	}

	for (p = res;p != NULL; p = p->ai_next) {
          void *tmp_addr;

          struct sockaddr_in *ipv = (struct sockaddr_in *)p->ai_addr;
          tmp_addr = &(ipv->sin_addr);

          /* convert the IP to a string: */
          inet_ntop(p->ai_family, addr, ipstr, sizeof ipstr);

	  memcpy(addr, tmp_addr, sizeof(*addr));
	  log_message("is-at: %s\n", inet_ntoa(*addr));
	}

	freeaddrinfo(res); // free the linked list
	return 0;
}

char * mygethostbyaddr(char * ipnum)
{
	struct sockaddr_in sa;
	char hbuf[NI_MAXHOST];

        /* prevent from timeouts */
        if (_res.nscount == 0) 
                return NULL;
  
	memset(&sa, 0, sizeof sa);
	sa.sin_family = AF_INET;

	if (inet_pton(AF_INET, ipnum, &sa.sin_addr) != 1)
          return NULL;

	if (getnameinfo((struct sockaddr*)&sa, sizeof(sa), hbuf, sizeof(hbuf), NULL, 0, 0 |NI_NAMEREQD) == 0) //NI_NUMERICHOST  NI_NAMEREQD
          return strdup(hbuf);
	else return NULL;
}

#elif defined(__GLIBC__)
  
#include <alloca.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <resolv.h>
#include <arpa/nameser.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"

#include "dns.h"

/* This is dumb, but glibc doesn't like to do hostname lookups w/o libc.so */

union dns_response {
    HEADER hdr;
    u_char buf[PACKETSZ];
} ;

static int do_query(char * query, int queryType, char ** domainName, struct in_addr * ipNum)
{
	int len, ancount, type;
	u_char * data, * end;
	char name[MAXDNAME];
	union dns_response response;
	
#ifdef __sparc__
	/* from jj: */
	/* We have to wait till ethernet negotiation is done */
	_res.retry = 3;
#else
	_res.retry = 2;
#endif


	len = res_search(query, C_IN, queryType, (void *) &response, sizeof(response));
	if (len <= 0)
		return -1;

	if (ntohs(response.hdr.rcode) != NOERROR)
		return -1;

	ancount = ntohs(response.hdr.ancount);
	if (ancount < 1)
		return -1;
	
	data = response.buf + sizeof(HEADER);
	end = response.buf + len;
	
	/* skip the question */
	data += dn_skipname(data, end) + QFIXEDSZ;

	/* parse the answer(s) */
	while (--ancount >= 0 && data < end) {

		/* skip the domain name portion of the RR record */
		data += dn_skipname(data, end);

		/* get RR information */
		GETSHORT(type, data);
		data += INT16SZ; /* skipp class */
		data += INT32SZ; /* skipp TTL */
		GETSHORT(len,  data);

		if (type == T_PTR) {
			/* we got a pointer */
			len = dn_expand(response.buf, end, data, name, sizeof(name));
			if (len <= 0) return -1;
			if (queryType == T_PTR && domainName) {
				/* we wanted a pointer */
				*domainName = malloc(strlen(name) + 1);
				strcpy(*domainName, name);
				return 0;
			}
		} else if (type == T_A) {
			/* we got an address */
			if (queryType == T_A && ipNum) {
				/* we wanted an address */
				memcpy(ipNum, data, sizeof(*ipNum));
				return 0;
			}
		}
		
		/* move ahead to next RR */
		data += len;
	} 
	
	return -1;
}

char * mygethostbyaddr(char * ipnum) {
	int rc;
	char * result;
	char * strbuf;
	char * chptr;
	char * splits[4];
	int i;

	_res.retry = 1;
	
	strbuf = alloca(strlen(ipnum) + 1);
	strcpy(strbuf, ipnum);
	
	ipnum = alloca(strlen(strbuf) + 20);
	
	for (i = 0; i < 4; i++) {
		chptr = strbuf;
		while (*chptr && *chptr != '.')
			chptr++;
		*chptr = '\0';
		
		if (chptr - strbuf > 3) return NULL;
		splits[i] = strbuf;
		strbuf = chptr + 1;
	}
	
	sprintf(ipnum, "%s.%s.%s.%s.in-addr.arpa", splits[3], splits[2], splits[1], splits[0]);
	
	rc = do_query(ipnum, T_PTR, &result, NULL);
	
	if (rc) 
		return NULL;
	else
		return result;
}

int mygethostbyname(char * name, struct in_addr * addr) {
	int rc = do_query(name, T_A, NULL, addr);
	if (!rc)
		log_message("is-at %s", inet_ntoa(*addr));
	return rc;
}

#else

#error "Unsupported C library"

#endif
