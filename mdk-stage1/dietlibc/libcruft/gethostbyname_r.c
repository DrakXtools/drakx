#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <stdlib.h>
#include <arpa/inet.h>
#include <sys/poll.h>
#include <unistd.h>
#include <errno.h>

#include <stdio.h>

extern int __dns_gethostbyx_r(const char* name, struct hostent* result,
			char *buf, size_t buflen,
			struct hostent **RESULT, int *h_errnop, int lookfor);

/* Oh boy, this interface sucks so badly, there are no words for it.
 * Not one, not two, but _three_ error signalling methods!  (*h_errnop
 * nonzero?  return value nonzero?  *RESULT zero?)  The glibc goons
 * really outdid themselves with this one. */
int gethostbyname_r(const char* name, struct hostent* result,
				char *buf, size_t buflen,
				struct hostent **RESULT, int *h_errnop) {
  int L=strlen(name);
  result->h_name=buf;
  if (buflen<L) { *h_errnop=ERANGE; return 1; }
  strcpy(buf,name);
  return __dns_gethostbyx_r(name,result,buf+L,buflen-L,RESULT,h_errnop,1);
}
