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

#include <stdlib.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/types.h>
#include <bzlib.h>
#include <sys/mount.h>
#include <sys/poll.h>
#include <errno.h>
#include <sys/utsname.h>
#include <sys/ioctl.h>
#include <linux/fd.h>
#include "stage1.h"
#include "log.h"
#include "mount.h"
#include "frontend.h"
#include "automatic.h"

#include "tools.h"
#include "probing.h"
#include "modules.h"

static struct param_elem params[50];
static int param_number = 0;

void process_cmdline(void)
{
	char buf[512];
	int size, i;
	int fd = -1; 

	if (IS_TESTING) {
		log_message("TESTING: opening cmdline... ");

		if ((fd = open("cmdline", O_RDONLY)) == -1)
			log_message("TESTING: could not open cmdline");
	}

	if (fd == -1) {
		log_message("opening /proc/cmdline... ");

		if ((fd = open("/proc/cmdline", O_RDONLY)) == -1)
			fatal_error("could not open /proc/cmdline");
	}

	size = read(fd, buf, sizeof(buf));
	buf[size-1] = '\0'; // -1 to eat the \n
	close(fd);

	log_message("\t%s", buf);

	i = 0;
	while (buf[i] != '\0') {
		char *name, *value = NULL;
		int j = i;
		while (buf[i] != ' ' && buf[i] != '=' && buf[i] != '\0')
			i++;
		if (i == j) {
			i++;
			continue;
		}
		name = memdup(&buf[j], i-j + 1);
		name[i-j] = '\0';

		if (buf[i] == '=') {
			int k = i+1;
			i++;
			while (buf[i] != ' ' && buf[i] != '\0')
				i++;
			value = memdup(&buf[k], i-k + 1);
			value[i-k] = '\0';
		}

		params[param_number].name = name;
		params[param_number].value = value;
		param_number++;
		if (!strcmp(name, "expert")) set_param(MODE_EXPERT);
		if (!strcmp(name, "changedisk")) set_param(MODE_CHANGEDISK);
		if (!strcmp(name, "updatemodules")) set_param(MODE_UPDATEMODULES);
		if (!strcmp(name, "rescue")) set_param(MODE_RESCUE);
		if (!strcmp(name, "noauto")) set_param(MODE_NOAUTO);
		if (!strcmp(name, "netauto")) set_param(MODE_NETAUTO);
		if (!strcmp(name, "recovery")) set_param(MODE_RECOVERY);
		if (!strcmp(name, "debugstage1")) set_param(MODE_DEBUGSTAGE1);
		if (!strcmp(name, "automatic")) {
			set_param(MODE_AUTOMATIC);
			grab_automatic_params(value);
		}
		if (buf[i] == '\0')
			break;
		i++;
	}
	
	log_message("\tgot %d args", param_number);
}


int stage1_mode = 0;

int get_param(int i)
{
#ifdef SPAWN_INTERACTIVE
	static int fd = 0;
	char buf[5000];
	char * ptr;
	int nb;

	if (fd <= 0) {
		fd = open(interactive_fifo, O_RDONLY);
		if (fd == -1)
			return (stage1_mode & i);
		fcntl(fd, F_SETFL, O_NONBLOCK);
	}

	if (fd > 0) {
		if ((nb = read(fd, buf, sizeof(buf))) > 0) {
			buf[nb] = '\0';
			ptr = buf;
			while ((ptr = strstr(ptr, "+ "))) {
				if (!strncmp(ptr+2, "expert", 6)) set_param(MODE_EXPERT);
				if (!strncmp(ptr+2, "rescue", 6)) set_param(MODE_RESCUE);
				ptr++;
			}
			ptr = buf;
			while ((ptr = strstr(ptr, "- "))) {
				if (!strncmp(ptr+2, "expert", 6)) unset_param(MODE_EXPERT);
				if (!strncmp(ptr+2, "rescue", 6)) unset_param(MODE_RESCUE);
				ptr++;
			}
		}
	}
#endif

	return (stage1_mode & i);
}

char * get_param_valued(char *param_name)
{
	int i;
	for (i = 0; i < param_number ; i++)
		if (!strcmp(params[i].name, param_name))
			return params[i].value;

	return NULL;
}

void set_param_valued(char *param_name, char *param_value)
{
	params[param_number].name = param_name;
	params[param_number].value = param_value;
	param_number++;
}

void set_param(int i)
{
	stage1_mode |= i;
}

void unset_param(int i)
{
	stage1_mode &= ~i;
}

// warning, many things rely on the fact that:
// - when failing it returns 0
// - it stops on first non-digit char
int charstar_to_int(const char * s)
{
	int number = 0;
	while (*s && isdigit(*s)) {
		number = (number * 10) + (*s - '0');
		s++;
	}
	return number;
}

off_t file_size(const char * path)
{
	struct stat statr;
	if (stat(path, &statr))
		return -1;
        else
                return statr.st_size;
}

int total_memory(void)
{
	int value;

	/* drakx powered: use /proc/kcore and rounds every 4 Mbytes */
	value = 4 * ((int)((float)file_size("/proc/kcore") / 1024 / 1024 / 4 + 0.5));
	log_message("Total Memory: %d Mbytes", value);

	return value;
}


int ramdisk_possible(void)
{
	if (total_memory() > (IS_RESCUE ? MEM_LIMIT_RESCUE : MEM_LIMIT_DRAKX))
		return 1;
	else {
		log_message("warning, ramdisk is not possible due to low mem!");
		return 0;
	}
}


enum return_type copy_file(char * from, char * to, void (*callback_func)(int overall))
{
        FILE * f_from, * f_to;
        size_t quantity __attribute__((aligned(16))), overall = 0;
        char buf[4096] __attribute__((aligned(4096)));
        int ret = RETURN_ERROR;

        log_message("copy_file: %s -> %s", from, to);

        if (!(f_from = fopen(from, "rb"))) {
                log_perror(from);
                return RETURN_ERROR;
        }

        if (!(f_to = fopen(to, "w"))) {
                log_perror(to);
                goto close_from;
                return RETURN_ERROR;
        }

        do {
                if ((quantity = fread(buf, 1, sizeof(buf), f_from)) > 0) {
                        if (fwrite(buf, 1, quantity, f_to) != quantity) {
                                log_message("short write (%s)", strerror(errno));
                                goto cleanup;
                        }
                }
                if (callback_func) {
                        overall += quantity;
                        callback_func(overall);
                }
        } while (!feof(f_from) && !ferror(f_from) && !ferror(f_to));

        if (ferror(f_from) || ferror(f_to)) {
                log_message("an error occured: %s", strerror(errno));
                goto cleanup;
        }

        ret = RETURN_OK;

 cleanup:
        fclose(f_to);
 close_from:
        fclose(f_from);

        return ret;
}

#ifndef MANDRAKE_MOVE
static void save_stuff_for_rescue(void)
{
        copy_file("/etc/resolv.conf", STAGE2_LOCATION "/etc/resolv.conf", NULL);
}

enum return_type load_ramdisk_fd(int ramdisk_fd, int size)
{
	BZFILE * st2;
	char * ramdisk = "/dev/ram3"; /* warning, verify that this file exists in the initrd, and that root=/dev/ram3 is actually passed to the kernel at boot time */
	int ram_fd;
	char buffer[32768];
	int z_errnum;
	char * wait_msg = "Loading program into memory...";
	int bytes_read = 0;
	int actually;
	int seems_ok = 0;

	st2 = BZ2_bzdopen(ramdisk_fd, "r");

	if (!st2) {
		log_message("Opening compressed ramdisk: %s", BZ2_bzerror(st2, &z_errnum));
		stg1_error_message("Could not open compressed ramdisk file.");
		return RETURN_ERROR;
	}

	ram_fd = open(ramdisk, O_WRONLY);
	if (ram_fd == -1) {
		log_perror(ramdisk);
		stg1_error_message("Could not open ramdisk device file.");
		return RETURN_ERROR;
	}
	
	init_progression(wait_msg, size);

	while ((actually = BZ2_bzread(st2, buffer, sizeof(buffer))) > 0) {
		seems_ok = 1;
		if (write(ram_fd, buffer, actually) != actually) {
			log_perror("writing ramdisk");
			remove_wait_message();
			return RETURN_ERROR;
		}
		update_progression((int)((bytes_read += actually) / RAMDISK_COMPRESSION_RATIO));
	}

	if (!seems_ok) {
		log_message("reading compressed ramdisk: %s", BZ2_bzerror(st2, &z_errnum));
		BZ2_bzclose(st2); /* opened by gzdopen, but also closes the associated fd */
		close(ram_fd);
		remove_wait_message();
		stg1_error_message("Could not uncompress second stage ramdisk. "
				   "This is probably an hardware error while reading the data. "
				   "(this may be caused by a hardware failure or a Linux kernel bug)");
		return RETURN_ERROR;
	}

	end_progression();

	BZ2_bzclose(st2); /* opened by gzdopen, but also closes the associated fd */
	close(ram_fd);

	if (my_mount(ramdisk, STAGE2_LOCATION, "ext2", 1))
		return RETURN_ERROR;

	set_param(MODE_RAMDISK);

	if (IS_RESCUE) {
		save_stuff_for_rescue();
		if (umount(STAGE2_LOCATION)) {
			log_perror(ramdisk);
			return RETURN_ERROR;
		}
		return RETURN_OK; /* fucksike, I lost several hours wondering why the kernel won't see the rescue if it is alreay mounted */
	}

	return RETURN_OK;
}


char * get_ramdisk_realname(void)
{
	char img_name[500];
	
	strcpy(img_name, RAMDISK_LOCATION);
	strcat(img_name, IS_RESCUE ? "rescue" : "mdkinst");
	strcat(img_name, "_stage2.bz2");

	return strdup(img_name);
}


enum return_type load_ramdisk(void)
{
	int st2_fd;
        off_t size;
	char img_name[500];

	strcpy(img_name, IMAGE_LOCATION);
	strcat(img_name, get_ramdisk_realname());

	log_message("trying to load %s as a ramdisk", img_name);

	st2_fd = open(img_name, O_RDONLY); /* to be able to see the progression */

	if (st2_fd == -1) {
		log_message("open ramdisk file (%s) failed", img_name);
		stg1_error_message("Could not open compressed ramdisk file (%s).", img_name);
		return RETURN_ERROR;
	}

	if ((size = file_size(img_name)) == -1)
		return RETURN_ERROR;
	else
		return load_ramdisk_fd(st2_fd, size);
}
#endif

/* pixel's */
void * memdup(void *src, size_t size)
{
	void * r;
	r = malloc(size);
	memcpy(r, src, size);
	return r;
}


void add_to_env(char * name, char * value)
{
        FILE* fakeenv = fopen(SLASH_LOCATION "/tmp/env", "a");
        if (fakeenv) {
                char* e = asprintf_("%s=%s\n", name, value);
                fwrite(e, 1, strlen(e), fakeenv);
                free(e);
                fclose(fakeenv);
        } else 
                log_message("couldn't fopen to fake env");
}


char ** list_directory(char * direct)
{
	char * tmp[50000]; /* in /dev there can be many many files.. */
	int i = 0;
	struct dirent *ep;
	DIR *dp = opendir(direct);
	while (dp && (ep = readdir(dp))) {
		if (strcmp(ep->d_name, ".") && strcmp(ep->d_name, "..")) {
			tmp[i] = strdup(ep->d_name);
			i++;
		}
	}
	if (dp)
		closedir(dp);
	tmp[i] = NULL;
	return memdup(tmp, sizeof(char*) * (i+1));
}


int string_array_length(char ** a)
{
	int i = 0;
	if (!a)
		return -1;
	while (a && *a) {
		a++;
		i++;
	}
	return i;
}

int kernel_version(void)
{
        struct utsname val;
        if (uname(&val)) {
                log_perror("uname failed");
                return -1;
        }
        return charstar_to_int(val.release + 2);
}

char * floppy_device(void)
{
        char ** names, ** models;
        int fd;
	my_insmod("floppy", ANY_DRIVER_TYPE, NULL, 0);
        fd = open("/dev/fd0", O_RDONLY|O_NONBLOCK);
        if (fd != -1) {
                char drivtyp[17];
                if (!ioctl(fd, FDGETDRVTYP, (void *)drivtyp)) {
                        struct floppy_drive_struct ds;
                        log_message("/dev/fd0 type: %s", drivtyp);
                        if (!ioctl(fd, FDPOLLDRVSTAT, &ds)) {
                                log_message("\ttrack: %d", ds.track);
                                if (ds.track >= 0) {
                                        close(fd);
                                        return "/dev/fd0";
                                }
                        }
                } else {
                        log_perror("can't FDGETDRVTYP /dev/fd0");
                }
                close(fd);
        }
        log_message("seems that you don't have a regular floppy drive");
        my_insmod("sd_mod", ANY_DRIVER_TYPE, NULL, 0);
	get_medias(FLOPPY, &names, &models, BUS_ANY);
	if (names && *names)
                return asprintf_("/dev/%s", *names);
        else
                return "/dev/fd0";
}

char * asprintf_(const char *msg, ...)
{
        int n;
        char * s;
        va_list arg_ptr;
        va_start(arg_ptr, msg);
        n = vsnprintf(0, 1000000, msg, arg_ptr);
        va_start(arg_ptr, msg);
        if ((s = malloc(n + 1))) {
                vsnprintf(s, n + 1, msg, arg_ptr);
                va_end(arg_ptr);
                return s;
        }
        va_end(arg_ptr);
        return strdup("");
}

int scall_(int retval, char * msg, char * file, int line)
{
	char tmp[5000];
        sprintf(tmp, "%s(%s:%d) failed", msg, file, line);
        if (retval)
                log_perror(tmp);
        return retval;
}
