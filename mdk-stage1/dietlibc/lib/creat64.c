#include <fcntl.h>

int creat64(const char *file,mode_t mode) {
  return open64(file,O_WRONLY|O_CREAT|O_TRUNC,mode);
}
