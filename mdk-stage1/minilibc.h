/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */


#include <stdarg.h>

#define _LOOSE_KERNEL_NAMES 1

#define NULL ((void *) 0)

#define	WIFSTOPPED(status)	(((status) & 0xff) == 0x7f)
#define	WIFSIGNALED(status)	(!WIFSTOPPED(status) && !WIFEXITED(status))
#define	WEXITSTATUS(status)	(((status) & 0xff00) >> 8)
#define	WTERMSIG(status)	((status) & 0x7f)
#define	WSTOPSIG(status)	WEXITSTATUS(status)
#define	WIFEXITED(status)	(WTERMSIG(status) == 0)

#define MS_MGC_VAL 0xc0ed0000

#define isspace(a) (a == ' ' || a == '\t')

extern char ** _environ;

extern int errno;

/* Aieee, gcc 2.95+ creates a stub for posix_types.h on i386 which brings
   glibc headers in and thus makes __FD_SET etc. not defined with 2.3+ kernels. */
#define _FEATURES_H 1
#include <linux/posix_types.h>
#include <linux/socket.h>
#include <linux/types.h>
#include <linux/time.h>
#include <linux/if.h>
#include <linux/un.h>
#include <linux/loop.h>
#include <linux/net.h>
#include <asm/termios.h>
#include <asm/ioctls.h>
#include <asm/unistd.h>
#include <asm/fcntl.h>
#include <asm/signal.h>

#ifndef __NR__newselect
#define __NR__newselect __NR_select
#endif

#ifndef MINILIBC_INTERNAL
static inline _syscall5(int,mount,const char *,spec,const char *,dir,const char *,type,unsigned long,rwflag,const void *,data);
static inline _syscall5(int,_newselect,int,n,fd_set *,rd,fd_set *,wr,fd_set *,ex,struct timeval *,timeval);
static inline _syscall4(int,wait4,pid_t,pid,int *,status,int,opts,void *,rusage)
static inline _syscall3(int,write,int,fd,const char *,buf,unsigned long,count)
static inline _syscall3(int,reboot,int,magic,int,magic_too,int,flag)
static inline _syscall3(int,execve,const char *,fn,void *,argv,void *,envp)
static inline _syscall3(int,read,int,fd,const char *,buf,unsigned long,count)
static inline _syscall3(int,open,const char *,fn,int,flags,mode_t,mode)
static inline _syscall3(int,ioctl,int,fd,int,request,void *,argp)
static inline _syscall2(int,dup2,int,one,int,two)
static inline _syscall2(int,kill,pid_t,pid,int,sig)
static inline _syscall2(int,symlink,const char *,a,const char *,b)
static inline _syscall2(int,chmod,const char * ,path,mode_t,mode)
static inline _syscall2(int,sethostname,const char *,name,int,len)
static inline _syscall2(int,setdomainname,const char *,name,int,len)
static inline _syscall2(int,setpgid,int,name,int,len)
static inline _syscall2(int,mkdir,const char *,pathname,mode_t,mode)
#ifdef __x86_64__
extern __sighandler_t signal(int signum, __sighandler_t handler);
#else
static inline _syscall2(int,signal,int,num,void *,len)
#endif
#ifdef __NR_umount
static inline _syscall1(int,umount,const char *,dir)
#else
static inline _syscall2(int,umount2,const char *,dir,int,flags)
static inline int umount(const char * dir) { return umount2(dir, 0); }
#endif
static inline _syscall1(int,unlink,const char *,fn)
static inline _syscall1(int,close,int,fd)
static inline _syscall1(int,swapoff,const char *,fn)
static inline _syscall0(int,getpid)
static inline _syscall0(int,sync)
#ifdef __sparc__
/* Nonstandard fork calling convention :( */
static inline int fork(void) {
  int __res;
  __asm__ __volatile__ (
    "mov %0, %%g1\n\t"
    "t 0x10\n\t"
    "bcc 1f\n\t"
    "dec %%o1\n\t"
    "sethi %%hi(%2), %%g1\n\t"
    "st %%o0, [%%g1 + %%lo(%2)]\n\t"
    "b 2f\n\t"
    "mov -1, %0\n\t"
    "1:\n\t"
    "and %%o0, %%o1, %0\n\t"
    "2:\n\t"
    : "=r" (__res)
    : "0" (__NR_fork), "i" (&errno)
    : "g1", "o0", "cc");
  return __res;
}
#else
static inline _syscall0(int,fork)
#endif
static inline _syscall0(pid_t,setsid)
static inline _syscall3(int,syslog,int, type, char *, buf, int, len);
#else
static inline _syscall5(int,_newselect,int,n,fd_set *,rd,fd_set *,wr,fd_set *,ex,struct timeval *,timeval);
static inline _syscall3(int,write,int,fd,const char *,buf,unsigned long,count)
#ifdef __NR_socketcall
static inline _syscall2(int,socketcall,int,code,unsigned long *, args)
#endif
#define __NR__do_exit __NR_exit
static inline _syscall1(int,_do_exit,int,exitcode)
#endif

#define select _newselect

extern int errno;

int socket(int a, int b, int c);
int bind(int a, void * b, int c);
int listen(int a, int b);
int accept(int a, void * addr, void * addr2);

void sleep(int secs);

int strlen(const char * string);
char * strcpy(char * dst, const char * src);
void * memcpy(void * dst, const void * src, size_t count);
int strcmp(const char * a, const char * b);
int strncmp(const char * a, const char * b, int len);
char * strchr(char * str, int ch);
char * strstr(char *haystack, char *needle);
char * strncpy(char * dst, const char * src, int len);

void print_str_init(int fd, char * string);
void print_int_init(int fd, int i);
/* Minimum printf which handles only characters, %d's and %s's */
void printf(char * fmt, ...) __attribute__ ((format (printf, 1, 2)));

