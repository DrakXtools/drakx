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
#include <signal.h>

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
#include "mount.h"
#include "insmod.h"

#ifdef ENABLE_PCMCIA
#include "pcmcia/pcmcia.h"
#endif

#ifndef DISABLE_CDROM
#include "cdrom.h"
#endif

#ifndef DISABLE_NETWORK
#include "network.h"
#endif

#ifndef DISABLE_DISK
#include "disk.h"
#endif


/************************************************************
 * globals */

char * method_name;


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN STAGE1: %s\n\nI can't recover from this.\nYou may reboot your system.\n", msg);
	while (1);
}


/************************************************************
 * backend functs
 * the principle is to not pollute frontend code with stage1-specific stuff */

int error_message_backend(void)
{
	unset_param(MODE_AUTOMATIC);
	return 0;
}

int info_message_backend(void)
{
	return IS_AUTOMATIC ? 1 : 0;
}


/************************************************************
 * spawns a shell on console #2 */
static void spawn_shell(void)
{
#ifdef SPAWN_SHELL
	int fd;
	char * shell_name[] = { "/tmp/sh", NULL };

	log_message("spawning a shell");

	if (!IS_TESTING) {
		fd = open("/dev/tty2", O_RDWR);
		if (fd == -1) {
			log_message("cannot open /dev/tty2 -- no shell will be provided");
			return;
		}
		else if (access(shell_name[0], X_OK)) {
			log_message("cannot open shell - %s doesn't exist", shell_name[0]);
			return;
		}
		
		if (!fork()) {
			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			
			close(fd);
			setsid();
			if (ioctl(0, TIOCSCTTY, NULL))
				log_perror("could not set new controlling tty");

			execve(shell_name[0], shell_name, grab_env());
			log_message("execl of %s failed: %s", shell_name[0], strerror(errno));
		}
		
		close(fd);
	}
#endif
}


char * interactive_fifo = "/tmp/stage1-fifo";
static pid_t interactive_pid = 0;

/* spawns my small interactive on console #6 */
static void spawn_interactive(void)
{
#ifdef SPAWN_INTERACTIVE
	int fd;
	char * dev = "/dev/tty6";

	printf("spawning my interactive on %s\n", dev);

	if (!IS_TESTING) {
		fd = open(dev, O_RDWR);
		if (fd == -1) {
			printf("cannot open %s -- no interactive\n", dev);
			return;
		}

		if (mkfifo(interactive_fifo, O_RDWR)) {
			printf("cannot create fifo -- no interactive\n");
			return;
		}
		
		if (!(interactive_pid = fork())) {
			int fif_out;

			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			
			close(fd);
			setsid();
			if (ioctl(0, TIOCSCTTY, NULL))
				perror("could not set new controlling tty");

			fif_out = open(interactive_fifo, O_WRONLY);
			printf("Please enter your command (availables: [+,-] [rescue,expert]).\n");
				
			while (1) {
				char s[50];
				int i = 0;
				printf("? ");
				fflush(stdout);
				read(0, &(s[i++]), 1);
				fcntl(0, F_SETFL, O_NONBLOCK);
				while (read(0, &(s[i++]), 1) > 0 && i < sizeof(s));
				fcntl(0, F_SETFL, 0);
				write(fif_out, s, i-2);
				printf("Ok.\n");
			}
		}
		
		close(fd);
	}
#endif
}


/************************************************************
 */

static void expert_third_party_modules(void)
{
	enum return_type results;
	char * floppy_mount_location = "/tmp/floppy";
	char ** modules;
	char final_name[500];
	char * choice;
	int rc;
	char * questions[] = { "Options", NULL };
	static char ** answers = NULL;

	results = ask_yes_no("If you want to insert third-party kernel modules, insert "
			     "a Linux (ext2fs) formatted floppy containing the modules and confirm. Otherwise, select \"no\".");;
	if (results != RETURN_OK)
		return;

	my_insmod("floppy", ANY_DRIVER_TYPE, NULL);

	if (my_mount("/dev/fd0", floppy_mount_location, "ext2") == -1) {
		error_message("I can't find a Linux ext2 floppy in first floppy drive.");
		return expert_third_party_modules();
	}

	modules = list_directory(floppy_mount_location);

	if (!modules || !*modules) {
		error_message("No modules found on floppy disk.");
		umount(floppy_mount_location);
		return expert_third_party_modules();
	}

	results = ask_from_list("Which driver would you like to insmod?", modules, &choice);
	if (results != RETURN_OK) {
		umount(floppy_mount_location);
		return;
	}

	sprintf(final_name, "%s/%s", floppy_mount_location, choice);

	results = ask_from_entries("Please enter the options:", questions, &answers, 24, NULL);
	if (results != RETURN_OK) {
		umount(floppy_mount_location);
		return expert_third_party_modules();
	}

	rc = insmod_call(final_name, answers[0]);
	umount(floppy_mount_location);

	if (rc) {
		log_message("\tfailed");
		error_message("Insmod failed.");
	}

	return expert_third_party_modules();
}


static void handle_pcmcia(char ** pcmcia_adapter)
{
#ifdef ENABLE_PCMCIA
	*pcmcia_adapter = pcmcia_probe();
	if (!*pcmcia_adapter) {
		log_message("no pcmcia adapter found");
		return;
	}
	my_insmod("pcmcia_core", ANY_DRIVER_TYPE, NULL);
	my_insmod(*pcmcia_adapter, ANY_DRIVER_TYPE, NULL);
	my_insmod("ds", ANY_DRIVER_TYPE, NULL);
	
        /* call to cardmgr takes time, let's use the wait message */
	wait_message("Enabling PCMCIA extension cards...");
	log_message("cardmgr rc: %d", cardmgr_call());
	remove_wait_message();
#endif
}


/************************************************************
 */

static enum return_type method_select_and_prepare(void)
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

	results = ask_from_list_auto("Please choose the installation method.", means, &choice, "method", means_auto);

	if (results != RETURN_OK)
		return 	method_select_and_prepare();

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
		return method_select_and_prepare();

	return RETURN_OK;
}


int main(int argc, char **argv, char **env)
{
	enum return_type ret;
	char ** argptr;
	char * stage2_args[30];
	char * pcmcia_adapter = NULL;

	if (getpid() > 50)
		set_param(MODE_TESTING);

	spawn_interactive();

	open_log();
	log_message("welcome to the " DISTRIB_NAME " install (mdk-stage1, version " VERSION " built " __DATE__ " " __TIME__")");
	process_cmdline();
	handle_env(env);
	spawn_shell();
	init_modules_insmoding();
	init_frontend("Welcome to " DISTRIB_NAME " (" VERSION ") " __DATE__ " " __TIME__);

	if (IS_EXPERT)
		expert_third_party_modules();

	handle_pcmcia(&pcmcia_adapter);

	ret = method_select_and_prepare();

	finish_frontend();
	close_log();

	if (ret != RETURN_OK)
		fatal_error("could not select an installation method");

	if (!IS_RAMDISK) {
		if (symlink(IMAGE_LOCATION LIVE_LOCATION, STAGE2_LOCATION) != 0) {
			printf("symlink from " IMAGE_LOCATION LIVE_LOCATION " to " STAGE2_LOCATION " failed");
			fatal_error(strerror(errno));
		}
	}

	if (interactive_pid != 0)
		kill(interactive_pid, 9);

	if (IS_RESCUE) {
		int fd = open("/proc/sys/kernel/real-root-dev", O_RDWR);
#if defined(__powerpc__) || defined (__sparc__)
		write(fd, "0x1030000", sizeof("0x1030000")); /* ram3 or sparc */
#else
		write(fd, "0x103", sizeof("0x103")); /* ram3 */
#endif
		close(fd);
		return 66;
	}

	if (IS_TESTING)
		return 0;

	argptr = stage2_args;
	*argptr++ = "/usr/bin/runinstall2";
	*argptr++ = "--method";
	*argptr++ = method_name;
	if (pcmcia_adapter) {
		*argptr++ = "--pcmcia";
		*argptr++ = pcmcia_adapter;
	}
	*argptr++ = NULL;

	execve(stage2_args[0], stage2_args, grab_env());

	printf("error in exec of stage2 :-(\n");
	fatal_error(strerror(errno));
	
	return 0; /* shut up compiler (we can't get here anyway!) */
}
