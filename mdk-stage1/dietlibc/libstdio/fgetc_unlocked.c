#include "dietstdio.h"
#include <unistd.h>

int fgetc_unlocked(FILE *stream) {
  unsigned char c;
  if (stream->ungotten) {
    stream->ungotten=0;
    return stream->ungetbuf;
  }
  if (feof(stream))
    return EOF;
  if (__fflush4(stream,BUFINPUT)) return EOF;
  if (stream->bm>=stream->bs) {
    int len=read(stream->fd,stream->buf,stream->buflen);
    if (len==0) {
      stream->flags|=EOFINDICATOR;
      return EOF;
    } else if (len<0) {
      stream->flags|=ERRORINDICATOR;
      return EOF;
    }
    stream->bm=0;
    stream->bs=len;
  }
  c=stream->buf[stream->bm];
  ++stream->bm;
  return c;
}

int fgetc(FILE* stream) __attribute__((weak,alias("fgetc_unlocked")));
