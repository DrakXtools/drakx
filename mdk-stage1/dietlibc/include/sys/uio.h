#ifndef _SYS_UIO
#define _SYS_UIO 1

#include <linux/uio.h>

int readv(int filedes, const struct iovec *vector, size_t count);
int writev(int filedes, const struct iovec *vector, size_t count);

#endif
