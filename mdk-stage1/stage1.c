/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000-2001 MandrakeSoft
 *
 * View the homepage: http://people.mandrakesoft.com/~gc/html/stage1.html
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

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <stdarg.h>
#include <signal.h>

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
#include "pcmcia_/pcmcia.h"
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
char * stage2_kickstart = NULL;


void fatal_error(char *msg)
{
	printf("FATAL ERROR IN STAGE1: %s\n\nI can't recover from this.\nYou may reboot your system.\n", msg);
	while (1);
}


/************************************************************
 * special frontend functs
 * (the principle is to not pollute frontend code with stage1-specific stuff) */

void stg1_error_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	log_message("unsetting automatic");
	unset_param(MODE_AUTOMATIC);
	verror_message(msg, args);
	va_end(args);
}

void stg1_info_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	if (IS_AUTOMATIC) {
		vlog_message(msg, args);
		return;
	}
	vinfo_message(msg, args);
	va_end(args);
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
			log_message("execve of %s failed: %s", shell_name[0], strerror(errno));
			exit(-1);
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

	if (my_mount("/dev/fd0", floppy_mount_location, "ext2", 0) == -1) {
		stg1_error_message("I can't find a Linux ext2 floppy in first floppy drive.");
		return expert_third_party_modules();
	}

	modules = list_directory(floppy_mount_location);

	if (!modules || !*modules) {
		stg1_error_message("No modules found on floppy disk.");
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
		stg1_error_message("Insmod failed.");
	}

	return expert_third_party_modules();
}


#ifdef ENABLE_PCMCIA
static void handle_pcmcia(char ** pcmcia_adapter)
{
	char buf[50];
	int fd = open("/proc/version", O_RDONLY);
	int size;
	if (fd == -1) 
		fatal_error("could not open /proc/version");
	size = read(fd, buf, sizeof(buf));
	buf[size-1] = '\0';   // -1 to eat the \n
	close(fd);
	buf[17] = '\0';       // enough to extract `2.2'
	if (ptr_begins_static_str(buf+14, "2.2")) {
		stg1_error_message("We now use kernel pcmcia support and this won't work with a 2.2 kernel.");
		return;
	}

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

	if (IS_EXPERT)
		expert_third_party_modules();
}
#endif


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
		return method_select_and_prepare();

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


int main(int argc __attribute__ ((unused)), char **argv __attribute__ ((unused)), char **env)
{
	enum return_type ret;
	char ** argptr;
	char * stage2_args[30];
#ifdef ENABLE_PCMCIA
	char * pcmcia_adapter = NULL;
#endif

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

	if (IS_UPDATEMODULES)
		update_modules();

#ifdef ENABLE_PCMCIA
	handle_pcmcia(&pcmcia_adapter);
#endif

	if (IS_CHANGEDISK)
		stg1_info_message("You are starting the installation with an alternate booting method. "
				  "Please change your disk, and insert the Installation disk.");

	if (IS_RESCUE && total_memory() < MEM_LIMIT_RESCUE) {
		stg1_error_message("You are starting the rescue with a low memory configuration. "
				   "Our experience shows that your system may crash at any point "
				   "or lock up for no apparent reason. Continue at "
				   "your own risk. Alternatively, you may reboot your system now.");
	}

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

	if (IS_RESCUE)
		return 66;
	if (IS_TESTING)
		return 0;

	argptr = stage2_args;
	*argptr++ = "/usr/bin/runinstall2";
	*argptr++ = "--method";
	*argptr++ = method_name;
#ifdef ENABLE_PCMCIA
	if (pcmcia_adapter) {
		*argptr++ = "--pcmcia";
		*argptr++ = pcmcia_adapter;
	}
#endif
	if (disable_modules)
		*argptr++ = "--blank";
	if (stage2_kickstart) {
		*argptr++ = "--kickstart";
		*argptr++ = stage2_kickstart;
	}
	*argptr++ = NULL;

	execve(stage2_args[0], stage2_args, grab_env());

	printf("error in exec of stage2 :-(\n");
	printf("trying to execute '/usr/bin/runinstall2' from the installation volume,\nthe following fatal error occurred\n");
	fatal_error(strerror(errno));
	
	return 0; /* shut up compiler (we can't get here anyway!) */
}
