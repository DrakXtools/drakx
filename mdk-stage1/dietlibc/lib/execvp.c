#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include "exec_lib.h"

int execvp(const char *file, char *const argv[]) {
  char *path=getenv("PATH");
  char *cur,*next;
  char buf[PATH_MAX];
  if (strchr((char*)file,'/')) {
    if (execve(file,argv,environ)==-1) {
      if (errno==ENOEXEC) __exec_shell(file,argv);
      return -1;
    }
  }
  if (!path) path=_PATH_DEFPATH;
  for (cur=path; cur; cur=next) {
    next=strchr(cur,':');
    if (!next)
      next=cur+strlen(cur);
    if (next==cur) {
      buf[0]='.';
      cur--;
    } else
      memmove(buf,cur,next-cur);
    buf[next-cur]='/';
    memmove(&buf[next-cur+1],file,strlen(file)+1);
    if (execve(buf,argv,environ)==-1) {
      if (errno==ENOEXEC) return __exec_shell(buf,argv);
      if ((errno!=EACCES) && (errno!=ENOENT)) return -1;
    }
    if (*next==0) break;
    next++;
  }
  return -1;
}
