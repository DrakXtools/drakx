#include <unistd.h>

#include <pthread.h>
#include "thread_internal.h"

int tcdrain(int fd)
{
  __TEST_CANCEL();
  return __libc_tcdrain(fd);
}
