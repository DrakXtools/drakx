#include <stdarg.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include "dietstdarg.h"

int execlp(const char* file, const char *arg,...) {
  va_list ap,bak;
  int n,i;
  char **argv,*tmp;
  va_start(ap, arg);
  va_copy(bak,ap);
  n=2;
  while ((tmp=va_arg(ap,char *)))
    ++n;
  va_end (ap);
  if ((argv=(char **)alloca(n*sizeof(char*)))) {
    argv[0]=arg;
    for (i=0; i<n; ++i)
      argv[i+1]=va_arg(bak,char *);
    va_end (bak);
    return execvp(file,argv);
  }
  __set_errno(ENOMEM);
  return -1;
}
