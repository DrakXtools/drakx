/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
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

#ifndef INIT_HEADERS
#include "init-libc-headers.h"
#else
#include INIT_HEADERS
#endif

#include "config-stage1.h"

#if defined(__powerpc__)
#define TIOCSCTTY     0x540E
#endif

char * env[] = {
	"PATH=/usr/bin:/bin:/sbin:/usr/sbin:/mnt/sbin:/mnt/usr/sbin:/mnt/bin:/mnt/usr/bin",
	"LD_LIBRARY_PATH=/lib:/usr/lib:/mnt/lib:/mnt/usr/lib:/usr/X11R6/lib:/mnt/usr/X11R6/lib",
	"HOME=/",
	"TERM=linux",
	"TERMINFO=/etc/terminfo",
	NULL
};


/* 
 * this needs to handle the following cases:
 *
 *	1) run from a CD root filesystem
 *	2) run from a read only nfs rooted filesystem
 *      3) run from a floppy
 *	4) run from a floppy that's been loaded into a ramdisk 
 *
 */

int testing;
int klog_pid;


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN INIT: %s\n\nI can't recover from this, please reboot manually and send bugreport.\n", msg);
	while (1);
}

void print_error(char *msg)
{
	printf("E: %s\n", msg);
}

void print_warning(char *msg)
{
	printf("W: %s\n", msg);
}

void print_int_init(int fd, int i)
{
	char buf[10];
	char * chptr = buf + 9;
	int j = 0;
	
	if (i < 0)
	{
		write(1, "-", 1);
		i = -1 * i;
	}
	
	while (i)
	{
		*chptr-- = '0' + (i % 10);
		j++;
		i = i / 10;
	}
	
	write(fd, chptr + 1, j);
}

void print_str_init(int fd, char * string)
{
	write(fd, string, strlen(string));
}


/* fork to:
 *   (1) watch /proc/kmsg and copy the stuff to /dev/tty4
 *   (2) listens to /dev/log and copy also this stuff (log from programs)
 */
void doklog()
{
	fd_set readset, unixs;
	int in, out, i;
	int log;
	int s;
	int sock = -1;
	struct sockaddr_un sockaddr;
	char buf[1024];
	int readfd;

	/* open kernel message logger */
	in = open("/proc/kmsg", O_RDONLY,0);
	if (in < 0) {
		print_error("could not open /proc/kmsg");
		return;
	}

	if ((log = open("/tmp/syslog", O_WRONLY | O_CREAT, 0644)) < 0) {
		print_error("error opening /tmp/syslog");
		sleep(5);
		return;
	}

	if ((klog_pid = fork())) {
		close(in);
		close(log);
		return;
	} else {
		close(0); 
		close(1);
		close(2);
	}
	
	out = open("/dev/tty4", O_WRONLY, 0);
	if (out < 0) 
		print_warning("couldn't open tty for syslog -- still using /tmp/syslog\n");

	/* now open the syslog socket */
// ############# LINUX 2.4 /dev/log IS BUGGED! --> apparently the syslogs can't reach me, and it's full up after a while
//	  sockaddr.sun_family = AF_UNIX;
//	  strncpy(sockaddr.sun_path, "/dev/log", UNIX_PATH_MAX);
//	  sock = socket(AF_UNIX, SOCK_STREAM, 0);
//	  if (sock < 0) {
//		  printf("error creating socket: %d\n", errno);
//		  sleep(5);
//	  }
//
//	  print_str_init(log, "] got socket\n");
//	  if (bind(sock, (struct sockaddr *) &sockaddr, sizeof(sockaddr.sun_family) + strlen(sockaddr.sun_path)))	{
//		  print_str_init(log, "] bind error: ");
//		  print_int_init(log, errno);
//		  print_str_init(log, "\n");
//		  sleep(//	  }
//
//	  print_str_init(log, "] bound socket\n");
//	  chmod("/dev/log", 0666);
//	  if (listen(sock, 5)) {
//		  print_str_init(log, "] listen error: ");
//		  print_int_init(log, errno);
//		  print_str_init(log, "\n");
//		  sleep(5);
//	  }

	/* disable on-console syslog output */
	syslog(8, NULL, 1);

	print_str_init(log, "] kernel/system logger ok\n");
	FD_ZERO(&unixs);
	while (1) {
		memcpy(&readset, &unixs, sizeof(unixs));

		if (sock >= 0)
			FD_SET(sock, &readset);
		FD_SET(in, &readset);
		
		i = select(20, &readset, NULL, NULL, NULL);
		if (i <= 0)
			continue;

		/* has /proc/kmsg things to tell us? */
		if (FD_ISSET(in, &readset)) {
			i = read(in, buf, sizeof(buf));
			if (i > 0) {
				if (out >= 0)
					write(out, buf, i);
				write(log, buf, i);
			}
		} 

		/* examine some fd's in the hope to find some syslog outputs from programs */
		for (readfd = 0; readfd < 20; ++readfd) {
			if (FD_ISSET(readfd, &readset) && FD_ISSET(readfd, &unixs)) {
				i = read(readfd, buf, sizeof(buf));
				if (i > 0) {
					/* grep out the output of RPM telling that it installed/removed some packages */
					if (!strstr(buf, "mdk installed") && !strstr(buf, "mdk removed")) {
						if (out >= 0)
							write(out, buf, i);
						write(log, buf, i);
					}
				} else if (i == 0) {
					/* socket closed */
					close(readfd);
					FD_CLR(readfd, &unixs);
				}
			}
		}

		/* the socket has moved, new stuff to do */
		if (sock >= 0 && FD_ISSET(sock, &readset)) {
			s = sizeof(sockaddr);
			readfd = accept(sock, (struct sockaddr *) &sockaddr, &s);
			if (readfd < 0) {
				char * msg_error = "] error in accept\n";
				if (out >= 0)
					write(out, msg_error, strlen(msg_error));
				write(log, msg_error, strlen(msg_error));
				close(sock);
				sock = -1;
			}
			else
				FD_SET(readfd, &unixs);
		}
	}
}


#define LOOP_CLR_FD	0x4C01

void del_loop(char *device) 
{
	int fd;
	if ((fd = open(device, O_RDONLY, 0)) < 0) {
		printf("del_loop open failed\n");
		return;
	}

	if (ioctl(fd, LOOP_CLR_FD, 0) < 0) {
		printf("del_loop ioctl failed");
		return;
	}

	close(fd);
}

struct filesystem
{
	char * dev;
	char * name;
	char * fs;
	int mounted;
};

/* attempt to unmount all filesystems in /proc/mounts */
void unmount_filesystems(void)
{
	int fd, size;
	char buf[65535];			/* this should be big enough */
	char *p;
	struct filesystem fs[500];
	int numfs = 0;
	int i, nb;
	
	printf("unmounting filesystems...\n"); 
	
	fd = open("/proc/mounts", O_RDONLY, 0);
	if (fd < 1) {
		print_error("failed to open /proc/mounts");
		sleep(2);
		return;
	}

	size = read(fd, buf, sizeof(buf) - 1);
	buf[size] = '\0';

	close(fd);

	p = buf;
	while (*p) {
		fs[numfs].mounted = 1;
		fs[numfs].dev = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		fs[numfs].name = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		fs[numfs].fs = p;
		while (*p != ' ') p++;
		*p++ = '\0';
		while (*p != '\n') p++;
		p++;
		if (strcmp(fs[numfs].name, "/") != 0) numfs++; /* skip if root, no need to take initrd root in account */
	}

	/* Pixel's ultra-optimized sorting algorithm:
	   multiple passes trying to umount everything until nothing moves
	   anymore (a.k.a holy shotgun method) */
	do {
		nb = 0;
		for (i = 0; i < numfs; i++) {
			/*printf("trying with %s\n", fs[i].name);*/
			if (fs[i].mounted && umount(fs[i].name) == 0) { 
				if (strncmp(fs[i].dev + sizeof("/dev/") - 1, "loop",
					    sizeof("loop") - 1) == 0)
					del_loop(fs[i].dev);
				
				printf("\t%s\n", fs[i].name);
				fs[i].mounted = 0;
				nb++;
			}
		}
	} while (nb);
	
	for (i = nb = 0; i < numfs; i++)
		if (fs[i].mounted) {
			printf("\t%s umount failed\n", fs[i].name);
			if (strcmp(fs[i].fs, "ext2") == 0) nb++; /* don't count not-ext2 umount failed */
		}
	
	if (nb) {
		printf("failed to umount some filesystems\n");
		while (1);
	}
}

int exit_value_rescue = 66;

int main(int argc __attribute__ ((unused)), char **argv __attribute__ ((unused)))
{
	pid_t installpid, childpid;
	int wait_status;
	int fd;
	int abnormal_termination = 0;
	int end_stage2 = 0;

	/* getpid() != 1 should work, by linuxrc tends to get a larger pid */
	testing = (getpid() > 50);

	if (!testing) {
		/* turn off screen blanking */
		printf("\033[9;0]");
		printf("\033[8]");
	}
	else
		printf("*** TESTING MODE *** (pid is %d)\n", getpid());


	printf("\n\t\t\t\033[1;40mWelcome to \033[1;36mMandrake\033[0;39m Linux\n\n");
	
	if (!testing) {
		if (mount("/proc", "/proc", "proc", 0, NULL))
			fatal_error("Unable to mount proc filesystem");
	}
	

	/* ignore Control-C and keyboard stop signals */
	signal(SIGINT, SIG_IGN);
	signal(SIGTSTP, SIG_IGN);


	if (!testing) {
		fd = open("/dev/tty1", O_RDWR, 0);
		if (fd < 0)
			/* try with devfs */
			fd = open("/dev/vc/1", O_RDWR, 0);
		
		if (fd < 0)
			fatal_error("failed to open /dev/tty1 and /dev/vc/1");
		
		dup2(fd, 0);
		dup2(fd, 1);
		dup2(fd, 2);
		close(fd);
	}
		

	/* I set me up as session leader (probably not necessary?) */
	setsid();
	if (ioctl(0, TIOCSCTTY, NULL))
		print_error("could not set new controlling tty");

	if (!testing) {
		char my_hostname[] = "localhost.localdomain";
		sethostname(my_hostname, sizeof(my_hostname));
		/* the default domainname (as of 2.0.35) is "(none)", which confuses 
		   glibc */
		setdomainname("", 0);
	}

	if (!testing) 
		doklog();

	/* Go into normal init mode - keep going, and then do a orderly shutdown
	   when:
	   
	   1) install exits
	   2) we receive a SIGHUP 
	*/

	printf("If more people were to meet doing raklets, this planet\n");
	printf("would be a safer place.\n");
	printf("\n");
	printf("Running install...\n"); 
	
	if (!(installpid = fork())) {
		/* child */
		char * child_argv[2];
		child_argv[0] = "/sbin/stage1";
		child_argv[1] = NULL;

		execve(child_argv[0], child_argv, env);
		printf("error in exec of stage1 :-(\n");
		return 0;
	}

	while (!end_stage2) {
		childpid = wait4(-1, &wait_status, 0, NULL);
		if (childpid == installpid)
			end_stage2 = 1;
	}

	if (!WIFEXITED(wait_status) || (WEXITSTATUS(wait_status) != 0 && WEXITSTATUS(wait_status) != exit_value_rescue)) {
		printf("install exited abnormally :-( ");
		if (WIFSIGNALED(wait_status))
			printf("-- received signal %d", WTERMSIG(wait_status));
		printf("\n");
		abnormal_termination = 1;
	} else if (WIFEXITED(wait_status) && WEXITSTATUS(wait_status) == exit_value_rescue) {
		kill(klog_pid, 9);
		printf("exiting init -- giving hand to rescue\n");
		return 0;
        } else
		printf("install succeeded\n");

	if (testing)
		return 0;

	sync(); sync();

	printf("sending termination signals...");
	kill(-1, 15);
	sleep(2);
	printf("done\n");

	printf("sending kill signals...");
	kill(-1, 9);
	sleep(2);
	printf("done\n");

	unmount_filesystems();

	if (!abnormal_termination) {
		printf("rebooting system\n");
		sleep(2);
		reboot(0xfee1dead, 672274793, 0x01234567);
	} else {
		printf("you may safely reboot your system\n");
		while (1);
	}

	return 0;
}
