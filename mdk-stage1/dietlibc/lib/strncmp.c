#include <sys/types.h>
#include <string.h>

/* gcc is broken and has a non-SUSv2 compliant internal prototype.
 * This causes it to warn about a type mismatch here.  Ignore it. */
int strncmp(const char *s1, const char *s2, size_t n) {
  register const char* a=s1;
  register const char* b=s2;
  register const char* fini=a+n;
  while (a<fini) {
    register int res=*a-*b;
    if (res) return res;
    if (!*a) return 0;
    ++a; ++b;
  }
  return 0;
}
