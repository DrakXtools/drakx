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

#include "minilibc.h"


#define KICK_FLOPPY     1
#define KICK_BOOTP	2

#define MS_REMOUNT      32

#define ENV_PATH 		0
#define ENV_LD_LIBRARY_PATH 	1
#define ENV_HOME		2
#define ENV_TERM		3
#define ENV_DEBUG		4

char * env[] = {
    "PATH=/usr/bin:/bin:/sbin:/usr/sbin:/mnt/sbin:/mnt/usr/sbin:"
		   "/mnt/bin:/mnt/usr/bin",
    "LD_LIBRARY_PATH=/lib:/usr/lib:/mnt/lib:/mnt/usr/lib:/usr/X11R6/lib:/mnt/usr/X11R6/lib",
    "HOME=/",
    "TERMINFO=/etc/linux-terminfo",
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


void fatal_error(char *msg)
{
	printf("FATAL ERROR: %s\n\nI can't recover from this, please reboot manually and send bugreport.\n", msg);
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


void doklog(char * fn)
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
	if (in < 0)
	{
		print_error("could not open /proc/kmsg");
		return;
	}

	out = open(fn, O_WRONLY, 0);
	if (out < 0) 
		print_warning("couldn't open tty for syslog -- still using /tmp/syslog\n");

	log = open("/tmp/syslog", O_WRONLY | O_CREAT, 0644);
	
	if (log < 0)
	{
		print_error("error opening /tmp/syslog");
		sleep(5);
		close(in);
		return;
	}

	/* if we get this far, we should be in good shape */
	if (fork())
	{
		/* parent */
		close(in);
		close(out);
		close(log);
		return;
	}
	
	close(0); 
	close(1);
	close(2);

	dup2(1, log);

#if defined(USE_LOGDEV)
	/* now open the syslog socket */
	sockaddr.sun_family = AF_UNIX;
	strcpy(sockaddr.sun_path, "/dev/log");
	sock = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sock < 0)
	{
		printf("error creating socket: %d\n", errno);
		sleep(5);
	}

	printf("got socket\n");
	if (bind(sock, (struct sockaddr *) &sockaddr, sizeof(sockaddr.sun_family) + 
		 strlen(sockaddr.sun_path)))
	{
		printf("bind error: %d\n", errno);
		sleep(5);
	}

	printf("bound socket\n");
	chmod("/dev/log", 0666);
	if (listen(sock, 5))
	{
		printf("listen error: %d\n", errno);
		sleep(5);
	}
#endif

	syslog(8, NULL, 1);

	FD_ZERO(&unixs);
	while (1)
	{
		memcpy(&readset, &unixs, sizeof(unixs));

		if (sock >= 0) FD_SET(sock, &readset);
		FD_SET(in, &readset);
		
		i = select(20, &readset, NULL, NULL, NULL);
		if (i <= 0) continue;
		
		if (FD_ISSET(in, &readset))
		{
			i = read(in, buf, sizeof(buf));
			if (i > 0)
			{
				if (out >= 0) write(out, buf, i);
				write(log, buf, i);
			}
		} 
		
		for (readfd = 0; readfd < 20; ++readfd)
		{
			if (FD_ISSET(readfd, &readset) && FD_ISSET(readfd, &unixs))
			{
				i = read(readfd, buf, sizeof(buf));
				if (i > 0)
				{
					if (out >= 0)
					{
						write(out, buf, i);
						write(out, "\n", 1);
					}

					write(log, buf, i);
					write(log, "\n", 1);
				}
				else
					if (i == 0)
					{
						/* socket closed */
						close(readfd);
						FD_CLR(readfd, &unixs);
					}
			}
		}

		if (sock >= 0 && FD_ISSET(sock, &readset))
		{
			s = sizeof(sockaddr);
			readfd = accept(sock, (struct sockaddr *) &sockaddr, &s);
			if (readfd < 0)
			{
				if (out >= 0) write(out, "error in accept\n", 16);
				write(log, "error in accept\n", 16);
				close(sock);
				sock = -1;
			}
			else
			{
				FD_SET(readfd, &unixs);
			}
		}
	}
}


void del_loop(char *device) 
{
	int fd;
	if ((fd = open(device, O_RDONLY, 0)) < 0)
	{
		printf("del_loop open failed\n");
		return;
	}

	if (ioctl(fd, LOOP_CLR_FD, 0) < 0)
	{
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
	if (fd < 1)
	{
		print_error("failed to open /proc/mounts");
		sleep(2);
		return;
	}

	size = read(fd, buf, sizeof(buf) - 1);
	buf[size] = '\0';

	close(fd);

	p = buf;
	while (*p)
	{
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
	do
	{
		nb = 0;
		for (i = 0; i < numfs; i++)
		{
			/*printf("trying with %s\n", fs[i].name);*/
			if (fs[i].mounted && umount(fs[i].name) == 0)
			{ 
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
		if (fs[i].mounted)
		{
			printf("\t%s umount failed\n", fs[i].name);
			if (strcmp(fs[i].fs, "ext2") == 0) nb++; /* don't count not-ext2 umount failed */
		}
	
	if (nb)
	{
		printf("failed to umount some filesystems\n");
		while (1);
	}
}


void disable_swap(void)
{
	int fd;
	char buf[4096];
	int i;
	char * start;
	char * chptr;
	
	printf("disabling swap...\n");

	fd = open("/proc/swaps", O_RDONLY, 0);
	if (fd < 0)
	{
		print_warning("failed to open /proc/swaps");
		return;
	}

	/* read all data at once */
	i = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (i < 0)
	{
		print_warning("failed to read /proc/swaps");
		return;
	}
	buf[i] = '\0';

	start = buf;
	while (*start)
	{
		/* move to next line */
		while (*start != '\n' && *start) start++;
		if (!*start) return;

		/* first char of new line */
		start++;
		if (*start != '/') return;

		/* build up an ASCIIZ filename */
		chptr = start;
		while (*chptr && *chptr != ' ') chptr++;
		if (!(*chptr)) return;
		*chptr = '\0';

		/* call swapoff */
		printf("Swapoff %s ", start);
		if (swapoff(start))
			printf(" failed (%d)\n", errno);
		else
			printf(" succeeded\n");

		start = chptr + 1;
	}
}


int main(int argc, char **argv)
{
	pid_t installpid, childpid;
	int wait_status;
	int fd;
	int abnormal_termination = 0;
	int end_stage2 = 0;
	char * child_argv[20];
	
	/* getpid() != 1 should work, by linuxrc tends to get a larger pid */
	testing = (getpid() > 50);

	printf("*** TESTING MODE ***\n");

	if (!testing)
	{
		/* turn off screen blanking */
		printf("\033[9;0]");
		printf("\033[8]");
	}

	printf("--- Hi. Linux-Mandrake install initializer starting. ---\n");
	printf("VERSION: %s\n", VERSION);

	
	if (!testing)
	{
		printf("mounting /proc filesystem... "); 
		if (mount("/proc", "/proc", "proc", 0, NULL))
			fatal_error("Unable to mount proc filesystem");
		printf("done\n");
	}
	

	/* ignore Control-C and keyboard stop signals */
	signal(SIGINT, SIG_IGN);
	signal(SIGTSTP, SIG_IGN);


	if (!testing)
	{
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

	if (!testing)
	{
		char * my_hostname = "localhost.localdomain";
		sethostname(my_hostname, strlen(my_hostname));
		/* the default domainname (as of 2.0.35) is "(none)", which confuses 
		   glibc */
		setdomainname("", 0);
	}

	if (!testing) 
		doklog("/dev/tty4");


	/* Go into normal init mode - keep going, and then do a orderly shutdown
	   when:
	   
	   1) /bin/install exits
	   2) we receive a SIGHUP 
	*/
	
	printf("running stage1...\n"); 
	
	if (!(installpid = fork()))
	{
		/* child */
		int index;
		child_argv[0] = "/sbin/stage1";

		index = 1;
		while (argv[index])
		{
			/* should be strdup but I don't have malloc */
			child_argv[index] = argv[index];
			index++;
		}
		child_argv[index] = NULL;

		printf("execing: %s\n", child_argv[0]);
		execve(child_argv[0], child_argv, env);
	
		exit(0);
	}

	while (!end_stage2)
	{
		childpid = wait4(-1, &wait_status, 0, NULL);
		if (childpid == installpid)
			end_stage2 = 1;
	}

	if (!WIFEXITED(wait_status) || WEXITSTATUS(wait_status))
	{
		printf("install exited abnormally :-( ");
		if (WIFSIGNALED(wait_status))
		{
			printf("-- received signal %d", WTERMSIG(wait_status));
		}
		printf("\n");
		abnormal_termination = 1;
	}
	else
		printf("back to stage1-initializer control -- install exited normally\n");

	if (testing)
		exit(0);

	sync(); sync();

	printf("sending termination signals...");
	kill(-1, 15);
	sleep(2);
	printf("done\n");

	printf("sending kill signals...");
	kill(-1, 9);
	sleep(2);
	printf("done\n");

	disable_swap();
	unmount_filesystems();

	if (!abnormal_termination)
	{
		printf("rebooting system\n");
		sleep(2);
		
		reboot(0xfee1dead, 672274793, 0x1234567);
	}
	else
	{
		printf("you may safely reboot your system\n");
		while (1);
	}

	exit(0);
	return 0;
}
