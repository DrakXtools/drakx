/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * View the homepage: http://us.mandrakesoft.com/~gc/html/stage1.html
 *
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

#include <sys/mount.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>

#include "stage1.h"

#include "log.h"
#include "probing.h"
#include "frontend.h"
#include "modules.h"
#include "tools.h"
#include "automatic.h"

#ifndef DISABLE_CDROM
#include "cdrom.h"
#endif

#ifndef DISABLE_NETWORK
#include "network.h"
#endif

#ifndef DISABLE_DISK
#include "disk.h"
#endif


/* globals */

char * method_name;


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN STAGE1: %s\n\nI can't recover from this.\n", msg);
	while (1);
}



/* spawns a shell on console #2 */
void spawn_shell(void)
{
	int fd;
	pid_t pid;
	char * shell_name = "/sbin/sash";

	log_message("spawning a shell..");

	if (!IS_TESTING) {
		fd = open("/dev/tty2", O_RDWR);
		if (fd == -1) {
			log_message("cannot open /dev/tty2 -- no shell will be provided");
			return;
		}
		else if (access(shell_name, X_OK)) {
			log_message("cannot open shell - %s doesn't exist", shell_name);
			return;
		}
		
		if (!(pid = fork())) {
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
}


enum return_type method_select_and_prepare(void)
{
	enum return_type results;
	char * choice;
	char * means[10], * means_auto[10];
	int i;

#ifndef DISABLE_DISK
	char * disk_install = "Hard disk"; char * disk_install_auto = "disk";
#endif
#ifndef DISABLE_CDROM
	char * cdrom_install = "CDROM drive"; char * cdrom_install_auto = "cdrom";
#endif
#ifndef DISABLE_NETWORK
	char * network_nfs_install = "NFS server"; char * network_nfs_install_auto = "nfs";
	char * network_ftp_install = "FTP server"; char * network_ftp_install_auto = "ftp";
	char * network_http_install = "HTTP server"; char * network_http_install_auto = "http";
#endif

	i = 0;
#ifndef DISABLE_NETWORK
	means[i] = network_nfs_install; means_auto[i++] = network_nfs_install_auto;
	means[i] = network_ftp_install; means_auto[i++] = network_ftp_install_auto;
	means[i] = network_http_install; means_auto[i++] = network_http_install_auto;
#endif
#ifndef DISABLE_CDROM
	means[i] = cdrom_install; means_auto[i++] = cdrom_install_auto;
#endif
#ifndef DISABLE_DISK
	means[i] = disk_install; means_auto[i++] = disk_install_auto;
#endif
	means[i] = NULL;

	results = ask_from_list_auto("Please choose the mean of installation.", means, &choice, "method", means_auto);

	if (results != RETURN_OK)
		return results;

	results = RETURN_ERROR;

#ifndef DISABLE_CDROM
	if (!strcmp(choice, cdrom_install))
		results = cdrom_prepare();
#endif
        
#ifndef DISABLE_DISK
	if (!strcmp(choice, disk_install))
		results = disk_prepare();
#endif
	
#ifndef DISABLE_NETWORK
	if (!strcmp(choice, network_nfs_install))
		results = nfs_prepare();
	
	if (!strcmp(choice, network_ftp_install))
		results = ftp_prepare();
	
	if (!strcmp(choice, network_http_install))
		results = http_prepare();
#endif

	if (results != RETURN_OK)
		method_select_and_prepare();

	return RETURN_OK;
}


int main(int argc, char **argv)
{
	enum return_type ret;
	char ** argptr;
	char * stage2_args[30];

	if (getpid() > 50)
		set_param(MODE_TESTING);

	open_log();
	log_message("welcome to the Linux-Mandrake install (stage1, version " VERSION " built " __DATE__ " " __TIME__")");
	process_cmdline();
	spawn_shell();
	if (load_modules_dependencies())
		fatal_error("could not open and parse modules dependencies");
	init_frontend();

#ifndef DISABLE_CDROM
	if (IS_CDROM) {
		/* try as automatic as possible with cdrom bootdisk */
		ret = cdrom_prepare();
		if (ret != RETURN_OK)
			ret = method_select_and_prepare();
	}
	else
#endif
		ret = method_select_and_prepare();

	finish_frontend();
	close_log();

	if (ret != RETURN_OK)
		fatal_error("could not select an installation method");

	if (!IS_RAMDISK) {
		if (symlink("/tmp/image/Mandrake/mdkinst", "/tmp/stage2") != 0)
			fatal_error("symlink to /tmp/stage2 failed");
	}

	if (IS_RESCUE) {
		int fd = open("/proc/sys/kernel/real-root-dev", O_RDWR);
#ifdef __sparc__
		write(fd, "0x1030000", sizeof("0x1030000")); /* ram3 or sparc */
#else
		write(fd, "0x103", sizeof("0x103")); /* ram3 */
#endif
		close(fd);
		return 0;
	}

	if (IS_TESTING)
		return 0;

	argptr = stage2_args;
	*argptr++ = "/usr/bin/runinstall2";
	*argptr++ = method_name;
	*argptr++ = NULL;

	execv(stage2_args[0], stage2_args);

	printf("error in exec of stage2 :-(\n");
	fatal_error(strerror(errno));
	
	return 0; /* shut up compiler (we can't get here anyway!) */
}
