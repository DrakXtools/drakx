#include <sys/types.h>
#include <string.h>

char *strstr(const char *haystack, const char *needle) {
  int nl=strlen(needle);
  int hl=strlen(haystack);
  int i;
  if (nl>hl) return 0;
  for (i=hl-nl+1; i; --i) {
    if (!memcmp(haystack,needle,nl))
      return (char*)haystack;
    ++haystack;
  }
  return 0;
}
