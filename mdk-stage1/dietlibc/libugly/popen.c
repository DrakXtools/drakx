#include "dietstdio.h"
#include <unistd.h>

extern char **environ;

FILE *popen(const char *command, const char *type) {
  int pfd[2];
  int fd0;
  pid_t pid;
  if (pipe(pfd)<0) return 0;
  fd0=(*type=='r');
  if ((pid=vfork())<0) {
    close(pfd[0]);
    close(pfd[1]);
    return 0;
  }
  if (!pid) {	/* child */
    char *argv[]={"sh","-c",0,0};
    close(pfd[!fd0]); close(fd0);
    dup2(pfd[fd0],fd0); close(pfd[fd0]);
    argv[2]=(char*)command;
    execve("/bin/sh",argv,environ);
    _exit(255);
  }
  close(pfd[fd0]);
  {
    register FILE* f;
    if ((f=fdopen(pfd[!fd0],type)))
      f->popen_kludge=pid;
    return f;
  }
}
