#include <sys/types.h>
#include <dietstdio.h>
#include <unistd.h>

#define SEEK_END 2

int __stdio_parse_mode(const char *mode);
FILE* __stdio_init_file(int fd);

FILE *fdopen (int filedes, const char *mode) {
  int f=0;	/* O_RDONLY, O_WRONLY or O_RDWR */
  int fd;

  f=__stdio_parse_mode(mode);
  if ((fd=filedes)<0) return 0;
  {
	  FILE * ret = __stdio_init_file(fd);
	  ret->flags |= UNSEEKABLE;
	  return ret;
  }
}
