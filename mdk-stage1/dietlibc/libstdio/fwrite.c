#include <sys/types.h>
#include "dietstdio.h"
#include <unistd.h>
#include <errno.h>

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
  int res;
  unsigned long len=size*nmemb;
  long i;
  if (!nmemb || len/nmemb!=size) return 0; /* check for integer overflow */
  if (len>stream->buflen || (stream->flags&NOBUF)) {
    fflush(stream);
    do {
      res=write(stream->fd,ptr,size*nmemb);
    } while (res==-1 && errno==EINTR);
  } else {
    register const unsigned char *c=ptr;
    for (i=len; i>0; --i,++c)
      if (fputc(*c,stream)) { res=len-i; goto abort; }
    res=len;
  }
  if (res<0) {
    stream->flags|=ERRORINDICATOR;
    return 0;
  }
abort:
  return size?res/size:0;
}
