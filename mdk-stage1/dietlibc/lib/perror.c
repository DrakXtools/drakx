#include "dietfeatures.h"
#include <unistd.h>
#include <string.h>
#include <errno.h>

extern char *sys_errlist[];
extern int sys_nerr;
extern int errno;

void perror(const char *s) {
  register char *message="[unknown error]";
  write(2,s,strlen(s));
  write(2,": ",2);
  if (errno>=0 && errno<sys_nerr)
#ifdef WANT_THREAD_SAFE
    message=sys_errlist[*__errno_location()];
#else
    message=sys_errlist[errno];
#endif
  write(2,message,strlen(message));
  write(2,"\n",1);
}
