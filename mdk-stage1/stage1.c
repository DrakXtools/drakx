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

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#include "log.h"


int testing;


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN STAGE1: %s\n\nI can't recover from this, please reboot manually and send bugreport.\n", msg);
	while (1);
}

void process_cmdline(void)
{
    char buf[512];
    int fd;
    int size;


    log_message("opening /proc/cmdline... ");

    if ((fd = open("/proc/cmdline", O_RDONLY, 0)) < 0) fatal_error("could not open /proc/cmdline");

    size = read(fd, buf, sizeof(buf) - 1);
    buf[size] = '\0';
    close(fd);

    log_message("\t%s", buf);
}


#ifdef SPAWN_SHELL
/* spawns a shell on console #2 */
void spawn_shell(void)
{
	pid_t pid;
	int fd;
	char * shell_name = "/sbin/sash";

	if (!testing)
	{
		fd = open("/dev/tty2", O_RDWR);
		if (fd < 0)
		{
			log_message("cannot open /dev/tty2 -- no shell will be provided");
			return;
		}
		else
			if (access(shell_name, X_OK))
			{
				log_message("cannot open shell - /usr/bin/sh doesn't exist");
				return;
			}
		
		if (!(pid = fork()))
		{
			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			
			close(fd);
			setsid();
			if (ioctl(0, TIOCSCTTY, NULL))
				perror("could not set new controlling tty");
			
			execl(shell_name, shell_name, NULL);
			log_message("execl of %s failed: %s", shell_name, strerror(errno));
		}
		
		close(fd);
	}
	else
		log_message("I should be spawning a shell");
}
#endif


int
main(int argc, char **argv)
{
	/* getpid() != 1 should work, by linuxrc tends to get a larger pid */
	testing = (getpid() > 50);

	open_log(testing);

	log_message("welcome to the Linux-Mandrake install (stage1, version " VERSION " built " __DATE__ " " __TIME__")");

	process_cmdline();
	spawn_shell();

	
                     printf("Temporary end of stage1 binary -- entering an infinite loop\n");
		     log_message("Temporary end of stage1 binary -- entering an infinite loop");
	             while(1);

	return 0;
}
