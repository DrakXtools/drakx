#include <sys/types.h>
#include <string.h>
#include "dietwarning.h"

void bzero(void *s, size_t n);
void bzero(void *s, size_t n) {
  memset(s,0,n);
}

link_warning("bzero","warning: you used bzero without including dietlibc's <string.h> w/ _BSD_SOURCE!")
