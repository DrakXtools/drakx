#ifndef _NETDB_H
#define _NETDB_H

#include <sys/cdefs.h>
#include <sys/types.h>

/* Absolute file name for network data base files.  */
#define	_PATH_HEQUIV		"/etc/hosts.equiv"
#define	_PATH_HOSTS		"/etc/hosts"
#define	_PATH_NETWORKS		"/etc/networks"
#define	_PATH_NSSWITCH_CONF	"/etc/nsswitch.conf"
#define	_PATH_PROTOCOLS		"/etc/protocols"
#define	_PATH_SERVICES		"/etc/services"

/* Description of data base entry for a single service.  */
struct servent
{
  char *s_name;			/* Official service name.  */
  char **s_aliases;		/* Alias list.  */
  int s_port;			/* Port number.  */
  char *s_proto;		/* Protocol to use.  */
};

extern void endservent (void) __THROW;
extern struct servent *getservent (void) __THROW;
extern struct servent *getservbyname (const char *__name,
				      const char *__proto) __THROW;
extern struct servent *getservbyport (int __port, const char *__proto)
     __THROW;

struct hostent
{
  char *h_name;			/* Official name of host.  */
  char **h_aliases;		/* Alias list.  */
  int h_addrtype;		/* Host address type.  */
  socklen_t h_length;		/* Length of address.  */
  char **h_addr_list;		/* List of addresses from name server.  */
#define	h_addr	h_addr_list[0]	/* Address, for backward compatibility.  */
};

extern void endhostent (void) __THROW;
extern struct hostent *gethostent (void) __THROW;
extern struct hostent *gethostbyaddr (const void *__addr, socklen_t __len,
				      int __type) __THROW;
extern struct hostent *gethostbyname (const char *__name) __THROW;
extern struct hostent *gethostbyname2 (const char *__name, int __af) __THROW;

/* this glibc "invention" is so ugly, I'm going to throw up any minute
 * now */
extern int gethostbyname_r(const char* NAME, struct hostent* RESULT_BUF,char* BUF,
			   size_t BUFLEN, struct hostent** RESULT,
			   int* H_ERRNOP) __THROW;

#define HOST_NOT_FOUND 1
#define TRY_AGAIN 2
#define NO_RECOVERY 3
#define NO_ADDRESS 4

extern int gethostbyaddr_r(const char* addr, size_t length, int format,
		    struct hostent* result, char *buf, size_t buflen,
		    struct hostent **RESULT, int *h_errnop) __THROW;

struct protoent {
  char    *p_name;        /* official protocol name */
  char    **p_aliases;    /* alias list */
  int     p_proto;        /* protocol number */
};

struct protoent *getprotoent(void) __THROW;
struct protoent *getprotobyname(const char *name) __THROW;
struct protoent *getprotobynumber(int proto) __THROW;
void setprotoent(int stayopen) __THROW;
void endprotoent(void) __THROW;


/* Description of data base entry for a single network.  NOTE: here a
   poor assumption is made.  The network number is expected to fit
   into an unsigned long int variable.  */
struct netent
{
  char *n_name;			/* Official name of network.  */
  char **n_aliases;		/* Alias list.  */
  int n_addrtype;		/* Net address type.  */
  uint32_t n_net;		/* Network number.  */
};

extern struct netent *getnetbyname (__const char *__name) __THROW;


#endif
