#include "dietfeatures.h"
#include <unistd.h>
#include <sys/stat.h>

#ifdef __linux__

extern int __ltostr(char *s, int size, unsigned long i, int base, char UpCase);

char *ttyname(int fd) {
#ifdef SLASH_PROC_OK
  char ibuf[20];
  static char obuf[20];
  strcpy(ibuf,"/proc/self/fd/");
  ibuf[__ltostr(ibuf+14,6,fd,10,0)+14]=0;
  if (readlink(ibuf,obuf,sizeof(obuf)-1)<0) return 0;
  return obuf;
#else
  static char buf[20]="/dev/tty";
  struct stat s;
  char *c=buf+8;
  int n;
  if (fstat(fd,&s)) return 0;
  if (S_ISCHR(s.st_mode)) {
    n=minor(s.st_rdev);
    switch (major(s.st_rdev)) {
    case 4:
      buf[5]='t'; buf[7]='y';
      if (n>63) {
	n-=64;
	*c='S';
	++c;
      }
num:
      c[__ltostr(c,6,n,10,0)]=0;
      break;
    case 2:
      buf[5]='p'; buf[7]='y';
      buf[8]='p'-(n>>4);
      buf[9]=n%4+'0';
      if (buf[9]>'9') *c+='a'-'0';
      buf[10]=0;
    case 136:
    case 137:
    case 138:
    case 139:
      buf[5]='p'; buf[7]='s';
      n+=(major(s.st_rdev)-136)<<8;
      *c='/'; ++c;
      goto num;
    default:
      return 0;
    }
    return buf;
  }
  return 0;
#endif
}

#endif
