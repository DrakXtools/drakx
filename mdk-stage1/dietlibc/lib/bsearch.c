#include <stdlib.h>

void *bsearch(const void *key, const void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *)) {
  const char *v, *r;
  int res;
  r=base+(nmemb-1)*size;
  do {
    register int num=nmemb/2;
    v=base+num*size;
    if ((res=compar(key,v))<0) {
      r=v-size;
      nmemb=num;
    } else {
      if (res==0) return (void*)v;
      base=v+size;
      nmemb-=num;
    }
  } while ((char*)base<=r);
  return 0;
}
