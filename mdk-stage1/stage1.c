/*
 * Guillaume Cottenceau (was gc@mandrakesoft.com)
 *
 * Copyright 2000-2004 MandrakeSoft
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
#include <linux/unistd.h>
_syscall2(int,pivot_root,const char *,new_root,const char *,put_old)

#include "stage1.h"

#include "log.h"
#include "probing.h"
#include "frontend.h"
#include "modules.h"
#include "tools.h"
#include "automatic.h"
#include "mount.h"
#include "lomount.h"
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

void stg1_fatal_message(char *msg, ...)
{
	va_list args;
	va_start(args, msg);
	log_message("unsetting automatic");
	unset_param(MODE_AUTOMATIC);
	verror_message(msg, args);
	va_end(args);
        exit(1);
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


#ifdef SPAWN_SHELL
static pid_t shell_pid = 0;

/************************************************************
 * spawns a shell on console #2 */
static void spawn_shell(void)
{
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
		
		if (!(shell_pid = fork())) {
			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			
			close(fd);
			setsid();
			if (ioctl(0, TIOCSCTTY, NULL))
				log_perror("could not set new controlling tty");

			execv(shell_name[0], shell_name);
			log_message("execve of %s failed: %s", shell_name[0], strerror(errno));
			exit(-1);
		}
		
		close(fd);
	}
}
#endif


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

	if (my_mount(floppy_device(), floppy_mount_location, "ext2", 0) == -1) {
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

	rc = insmod_local_file(final_name, answers[0]);
	umount(floppy_mount_location);

	if (rc) {
		log_message("\tfailed");
		stg1_error_message("Insmod failed.");
	}

	return expert_third_party_modules();
}


#ifdef ENABLE_PCMCIA
static void handle_pcmcia(void)
{
        char * pcmcia_adapter;
	if (kernel_version() == 2) {
		stg1_error_message("We now use kernel pcmcia support and this won't work with a 2.2 kernel.");
		return;
	}

	pcmcia_adapter = pcmcia_probe();
	if (!pcmcia_adapter) {
		log_message("no pcmcia adapter found");
		return;
	}
	my_insmod("pcmcia_core", ANY_DRIVER_TYPE, NULL, 0);
	my_insmod(pcmcia_adapter, ANY_DRIVER_TYPE, NULL, 0);
	my_insmod("ds", ANY_DRIVER_TYPE, NULL, 0);
	
        /* call to cardmgr takes time, let's use the wait message */
	wait_message("Enabling PCMCIA extension cards...");
	log_message("cardmgr rc: %d", cardmgr_call());
	remove_wait_message();

	if (IS_EXPERT)
		expert_third_party_modules();

        add_to_env("PCMCIA", pcmcia_adapter);
}
#endif


/************************************************************
 */

static void method_select_and_prepare(void)
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
        allow_additional_modules_floppy = 0;
#endif
#ifndef DISABLE_DISK
	means[i] = disk_install; means_auto[i++] = disk_install_auto;
        allow_additional_modules_floppy = 0;
#endif
	means[i] = NULL;

	results = ask_from_list_auto("Please choose the installation method.", means, &choice, "method", means_auto);

	if (results != RETURN_OK)
		return method_select_and_prepare();

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
}

enum return_type create_initial_fs(char* symlinks, char* devices)
{
        FILE *f;
        char buf[5000];

        if (scall(!(f = fopen(symlinks, "rb")), "fopen"))
                return RETURN_ERROR;
        while (fgets(buf, sizeof(buf), f)) {
                char oldpath[500], newpath[500], newpathfinal[500];
                buf[strlen(buf)-1] = '\0';  // trim \n
                if (sscanf(buf, "%s %s", oldpath, newpath) != 2) {
                        sprintf(oldpath, "%s%s", STAGE2_LOCATION_REL, buf);
                        sprintf(newpathfinal, "%s%s", SLASH_LOCATION, buf);
                } else {
                        sprintf(newpathfinal, "%s%s", SLASH_LOCATION, newpath);
                }
                log_message("creating symlink %s -> %s", oldpath, newpathfinal);
                if (scall(symlink(oldpath, newpathfinal), "symlink"))
                        return RETURN_ERROR;
        }
        fclose(f);

        // need to create the few devices needed to start up stage2 in a decent manner, we can't symlink or they will keep CD busy
        if (scall(mkdir(SLASH_LOCATION "/dev", 0755), "mkdir"))
                return RETURN_ERROR;
        if (scall(!(f = fopen(devices, "rb")), "fopen"))
                return RETURN_ERROR;
        while (fgets(buf, sizeof(buf), f)) {
                char name[500], path[500], type;
                int major, minor;
                sscanf(buf, "%s %c %d %d", name, &type, &major, &minor);
                sprintf(path, "%s%s", SLASH_LOCATION, name);
                log_message("creating device %s %c %d %d", path, type, major, minor);
                if (scall(mknod(path, (type == 'c' ? S_IFCHR : S_IFBLK) | 0600, makedev(major, minor)), "mknod"))
                        return RETURN_ERROR;
        }
        fclose(f);
        return RETURN_OK;
}

#ifdef MANDRAKE_MOVE
static enum return_type handle_clp(char* clp, char* live, char* location_live, char* location_mount, int* is_symlink, char* clp_tmpfs)
{
        static int count = 0;
        if (access(clp, R_OK)) {
                log_message("no %s found (or disabled), trying to fallback on plain tree", clp);
                if (!access(live, R_OK)) {
                        if (scall(symlink(location_live, location_mount), "symlink"))
                                return RETURN_ERROR;
                        *is_symlink = 1;
                        return RETURN_OK;
                } else {
                        log_message("move: can't find %s nor %s, proceeding hoping files will be there", clp, live);
                        return RETURN_OK;
                }
        }

        if (clp_tmpfs) {
                int ret;
                char buf[5000];
                sprintf(buf, "Loading (part %d)...", ++count);
                init_progression(buf, file_size(clp));
                ret = copy_file(clp, clp_tmpfs, update_progression);
                end_progression();
                if (ret != RETURN_OK)
                        return ret;
                clp = clp_tmpfs;
        }

        if (lomount(clp, location_mount, NULL, 1)) {
                stg1_error_message("Could not mount compressed loopback :(.");
                return RETURN_ERROR;
        }

        return RETURN_OK;
}

int mandrake_move_post(void)
{
        int boot__real_is_symlink_to_raw = 0;
        int always__real_is_symlink_to_raw = 0;
        int totem__real_is_symlink_to_raw = 0;
        int main__real_is_symlink_to_raw = 0;

        if (handle_clp(IMAGE_LOCATION "/live_tree_boot.clp", IMAGE_LOCATION "/live_tree_boot/usr/bin/runstage2.pl",
                       IMAGE_LOCATION "/live_tree_boot", BOOT_LOCATION,
                       &boot__real_is_symlink_to_raw, SLASH_LOCATION "/live_tree_boot.clp") != RETURN_OK)
                return RETURN_ERROR;

        if (handle_clp(IMAGE_LOCATION "/live_tree_always.clp", IMAGE_LOCATION "/live_tree_always/bin/bash",
                       IMAGE_LOCATION "/live_tree_always", ALWAYS_LOCATION,
                       &always__real_is_symlink_to_raw, SLASH_LOCATION "/live_tree_always.clp") != RETURN_OK)
                return RETURN_ERROR;

        if (handle_clp(IMAGE_LOCATION "/live_tree_totem.clp", IMAGE_LOCATION "/live_tree_totem/usr/bin/totem",
                       IMAGE_LOCATION "/live_tree_totem", TOTEM_LOCATION,
                       &totem__real_is_symlink_to_raw, SLASH_LOCATION "/live_tree_totem.clp") != RETURN_OK)
                return RETURN_ERROR;

        if (handle_clp(IMAGE_LOCATION "/live_tree.clp", IMAGE_LOCATION "/live_tree/etc/fstab",
                       IMAGE_LOCATION "/live_tree", IMAGE_LOCATION_REAL,
                       &main__real_is_symlink_to_raw, NULL) != RETURN_OK)
                return RETURN_ERROR;
       
        // in case we didn't mount any clp, because gzloop.o is not available later in /lib/modules
	my_insmod("gzloop", ANY_DRIVER_TYPE, NULL, 0);
        
        // hardcoded :(
        if (!access(TOTEM_LOCATION, R_OK)) {
                if (scall(symlink("/image_totem/usr", SLASH_LOCATION "/usr"), "symlink"))
                        return RETURN_ERROR;
        } else
                // need a fallback in case we don't use image_totem.clp nor live_tree_totem, but we're in -u mode
                if (scall(symlink(STAGE2_LOCATION_REL "/usr", SLASH_LOCATION "/usr"), "symlink"))
                        return RETURN_ERROR;

        if (create_initial_fs(IMAGE_LOCATION_REAL "/move/symlinks", IMAGE_LOCATION_REAL "/move/devices") != RETURN_OK)
                return RETURN_ERROR;

        if (boot__real_is_symlink_to_raw) {
                if (scall(unlink(BOOT_LOCATION), "unlink"))
                        return RETURN_ERROR;
                if (scall(symlink(RAW_LOCATION_REL "/live_tree_boot", BOOT_LOCATION), "symlink"))
                        return RETURN_ERROR;
        }

        if (always__real_is_symlink_to_raw) {
                if (scall(unlink(ALWAYS_LOCATION), "unlink"))
                        return RETURN_ERROR;
                if (scall(symlink(RAW_LOCATION_REL "/live_tree_always", ALWAYS_LOCATION), "symlink"))
                        return RETURN_ERROR;
        }

        if (totem__real_is_symlink_to_raw) {
                if (scall(unlink(TOTEM_LOCATION), "unlink"))
                        return RETURN_ERROR;
                if (scall(symlink(RAW_LOCATION_REL "/live_tree_totem", TOTEM_LOCATION), "symlink"))
                        return RETURN_ERROR;
        }

        if (main__real_is_symlink_to_raw) {
                if (scall(unlink(IMAGE_LOCATION_REAL), "unlink"))
                        return RETURN_ERROR;
                if (scall(symlink(RAW_LOCATION_REL "/live_tree", IMAGE_LOCATION_REAL), "symlink"))
                        return RETURN_ERROR;
        }
	return RETURN_OK;
}
#endif

int do_pivot_root(void)
{
        int fd;
        char rootdev[] = "0x0100"; 

        if (IS_DEBUGSTAGE1)
                while (1);

        log_message("pivot_rooting");
        // trick so that kernel won't try to mount the root device when initrd exits
        if (scall((fd = open("/proc/sys/kernel/real-root-dev", O_WRONLY)) < 0, "open"))
                return RETURN_ERROR;
        if (scall(write(fd, rootdev, strlen(rootdev)) != (signed)strlen(rootdev), "write")) {
                close(fd);
                return RETURN_ERROR;
        }
        close(fd);

        if (scall(mkdir(SLASH_LOCATION "/stage1", 0755), "mkdir"))
                return RETURN_ERROR;

        if (scall(pivot_root(SLASH_LOCATION, SLASH_LOCATION "/stage1"), "pivot_root"))
                return RETURN_ERROR;

        return RETURN_OK;
}

void finish_preparing(void)
{
	if (!IS_RESCUE) {
#ifdef MANDRAKE_MOVE
                if (mandrake_move_post() != RETURN_OK)
                        stg1_fatal_message("Fatal error when launching MandrakeMove.");
#else
                mkdir(SLASH_LOCATION "/etc", 0755);
                mkdir(SLASH_LOCATION "/var", 0755);
                /* STAGE2_LOCATION is wrong for live installs before pivot_root */
                if ((!IS_RAMDISK && create_initial_fs(IMAGE_LOCATION LIVE_LOCATION "/usr/share/symlinks",
                                                      IMAGE_LOCATION LIVE_LOCATION "/usr/share/devices") != RETURN_OK)
                  || (IS_RAMDISK && create_initial_fs(STAGE2_LOCATION "/usr/share/symlinks",
                                                      STAGE2_LOCATION "/usr/share/devices") != RETURN_OK))
                        stg1_fatal_message("Fatal error finishing initialization.");
#endif
                
                copy_file("/etc/resolv.conf", SLASH_LOCATION "/etc/resolv.conf", NULL);
                mkdir(SLASH_LOCATION "/modules", 0755);
                copy_file("/modules/modules.dep", SLASH_LOCATION "/modules/modules.dep", NULL);
                
                umount("/tmp/tmpfs");
                do_pivot_root();

                if (file_size("/sbin/init") == -1)
                        stg1_fatal_message("Fatal error giving hand to second stage.");
        }


	if (shell_pid != 0) {
                int fd;
		kill(shell_pid, 9);
		fd = open("/dev/tty2", O_RDWR);
                write(fd, "Killed\n", 7);
                close(fd);
        }
}

int main(int argc __attribute__ ((unused)), char **argv __attribute__ ((unused)), char **env)
{
	if (getenv("DEBUGSTAGE1"))
		set_param(MODE_TESTING);

	if (!IS_TESTING) {
		mkdir(SLASH_LOCATION, 0755);
		if (scall(mount("none", SLASH_LOCATION, "tmpfs", MS_MGC_VAL, NULL), "mount tmpfs"))
			fatal_error("Fatal error initializing.");
		mkdir(SLASH_LOCATION "/tmp", 0755);
	}

	spawn_interactive();

	open_log();
	log_message("welcome to the " DISTRIB_NAME " install (mdk-stage1, version " VERSION " built " __DATE__ " " __TIME__")");
	process_cmdline();
#ifdef SPAWN_SHELL
	spawn_shell();
#endif
	init_modules_insmoding();
	init_frontend("Welcome to " DISTRIB_NAME
#ifdef MANDRAKE_MOVE
                      ", "
#else
                      " (" VERSION ") "
#endif
                      __DATE__ " " __TIME__);

	if (IS_EXPERT)
		expert_third_party_modules();

	if (IS_UPDATEMODULES)
		update_modules();

#ifdef ENABLE_PCMCIA
	if (!IS_NOAUTO)
		handle_pcmcia();
#endif
        
        // load usb interface as soon as possible, helps usb mouse detection in stage2 */
	probe_that_type(USB_CONTROLLERS, BUS_USB);

	if (IS_CHANGEDISK)
		stg1_info_message("You are starting the installation with an alternate booting method. "
				  "Please change your disk, and insert the Installation disk.");

	if (IS_RESCUE && total_memory() < MEM_LIMIT_RESCUE) {
		stg1_error_message("You are starting the rescue with a low memory configuration. "
				   "Our experience shows that your system may crash at any point "
				   "or lock up for no apparent reason. Continue at "
				   "your own risk. Alternatively, you may reboot your system now.");
	}

#ifdef MANDRAKE_MOVE
	if (total_memory() < MEM_LIMIT_MOVE)
		stg1_info_message(DISTRIB_NAME " typically needs more than %d Mbytes of memory (detected %d Mbytes). You may proceed, but the machine may crash or lock up for no apparent reason. Continue at your own risk. Alternatively, you may reboot your system now.",
				   MEM_LIMIT_MOVE, total_memory());
#endif

#ifndef DISABLE_DISK
        if (IS_RECOVERY && streq(get_auto_value("method"), "cdrom")) {
                if (!process_recovery())
                        method_select_and_prepare();
        } else
#endif
                method_select_and_prepare();

	if (!IS_RAMDISK)
		if (symlink(IMAGE_LOCATION_REAL LIVE_LOCATION, STAGE2_LOCATION) != 0)
			log_perror("symlink from " IMAGE_LOCATION_REAL LIVE_LOCATION " to " STAGE2_LOCATION " failed");

	if (interactive_pid != 0)
		kill(interactive_pid, 9);

	finish_preparing();

	finish_frontend();
	close_log();

	if (IS_TESTING)
		return 0;
	else
		return 66;
}
