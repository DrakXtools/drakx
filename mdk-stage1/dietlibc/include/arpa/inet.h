#ifndef _ARPA_INET_H
#define _ARPA_INET_H

#include <sys/cdefs.h>
#include <sys/types.h>

int inet_aton(const char *cp, struct in_addr *inp) __THROW;
unsigned long int inet_addr(const char *cp) __THROW;
unsigned long int inet_network(const char *cp) __THROW;
char *inet_ntoa(struct in_addr in) __THROW;
struct in_addr inet_makeaddr(int net, int host) __THROW;
unsigned long int inet_lnaof(struct in_addr in) __THROW;
unsigned long int inet_netof(struct in_addr in) __THROW;

#endif
