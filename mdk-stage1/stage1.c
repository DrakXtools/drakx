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

#include "cdrom.h"
#include "network.h"
#include "disk.h"


/* globals */

int stage1_mode = 0;
struct cmdline_elem params[500];


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN STAGE1: %s\n\nI can't recover from this, please reboot manually and send bugreport.\n", msg);
	while (1);
}


void process_cmdline(void)
{
	char buf[512];
	int fd, size, i, p;
	
	log_message("opening /proc/cmdline... ");
	
	if ((fd = open("/proc/cmdline", O_RDONLY, 0)) == -1)
		fatal_error("could not open /proc/cmdline");
	
	size = read(fd, buf, sizeof(buf));
	buf[size-1] = 0;
	close(fd);

	log_message("\t%s", buf);

	i = 0; p = 0;
	while (buf[i] != 0) {
		char *name, *value = NULL;
		int j = i;
		while (buf[i] != ' ' && buf[i] != '=' && buf[i] != 0)
			i++;
		if (i == j) {
			i++;
			continue;
		}
		name = (char *) malloc(i-j + 1);
		memcpy(name, &buf[j], i-j);
		name[i-j] = 0;

		if (buf[i] == '=') {
			int k = i+1;
			i++;
			while (buf[i] != ' ' && buf[i] != 0)
				i++;
			value = (char *) malloc(i-k + 1);
			memcpy(value, &buf[k], i-k);
			value[i-k] = 0;
		}

		params[p].name = name;
		params[p].value = value;
		p++;
		i++;
		if (!strcmp(name, "expert")) stage1_mode |= MODE_EXPERT;
		if (!strcmp(name, "text")) stage1_mode |= MODE_TEXT;
		if (!strcmp(name, "rescue")) stage1_mode |= MODE_RESCUE;
		if (!strcmp(name, "pcmcia")) stage1_mode |= MODE_PCMCIA;
		if (!strcmp(name, "cdrom")) stage1_mode |= MODE_CDROM;
	}
	params[p].name = NULL;

	log_message("\tgot %d args", p);
}


/* spawns a shell on console #2 */
void spawn_shell(void)
{
	pid_t pid;
	int fd;
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
	char * disk_install = "Hard disk";
	char * cdrom_install = "CDROM drive";
	char * network_nfs_install = "NFS server";
	char * network_ftp_install = "FTP server";
	char * network_http_install = "HTTP server";
	enum return_type results;
	char * choice;
	char * means[10];
	int i;

	i = 0;
#ifndef DISABLE_NETWORK
	means[i] = network_nfs_install; i++;
	means[i] = network_ftp_install; i++;
	means[i] = network_http_install; i++;
#endif
#ifndef DISABLE_DISK
	means[i] = disk_install; i++;
#endif
#ifndef DISABLE_CDROM
	means[i] = cdrom_install; i++;
#endif
	means[i] = NULL;

	results = ask_from_list("Please choose the mean of installation.", means, &choice);

	if (results != RETURN_OK)
		return results;

	if (!strcmp(choice, cdrom_install))
		return cdrom_prepare();
	else if (!strcmp(choice, disk_install))
		return disk_prepare();
	else if (!strcmp(choice, network_nfs_install))
		return nfs_prepare();
	else if (!strcmp(choice, network_ftp_install))
		return ftp_prepare();
	else if (!strcmp(choice, network_http_install))
		return http_prepare();

	return RETURN_ERROR;
}


int main(int argc, char **argv)
{
	enum return_type ret;

	if (getpid() > 50)
		stage1_mode |= MODE_TESTING;

	open_log(IS_TESTING);

	log_message("welcome to the Linux-Mandrake install (stage1, version " VERSION " built " __DATE__ " " __TIME__")");

	process_cmdline();
	spawn_shell();
	if (load_modules_dependencies())
		fatal_error("could not open and parse modules dependencies");

	init_frontend();

	if (IS_CDROM)
		ret = cdrom_prepare();
	else
		ret = method_select_and_prepare();

	while (ret == RETURN_BACK)
		ret = method_select_and_prepare();

	finish_frontend();
	close_log();

	if (ret == RETURN_ERROR)
		fatal_error("could not select an installation method");

	return 0;
}
