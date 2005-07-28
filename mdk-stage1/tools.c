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
#include "lomount.h"

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
		if (!strcmp(name, "changedisk")) set_param(MODE_CHANGEDISK);
		if (!strcmp(name, "updatemodules") ||
		    !strcmp(name, "thirdparty")) set_param(MODE_THIRDPARTY);
		if (!strcmp(name, "rescue")) set_param(MODE_RESCUE);
		if (!strcmp(name, "keepmounted")) set_param(MODE_KEEP_MOUNTED);
		if (!strcmp(name, "noauto")) set_param(MODE_NOAUTO);
		if (!strcmp(name, "netauto")) set_param(MODE_NETAUTO);
		if (!strcmp(name, "debugstage1")) set_param(MODE_DEBUGSTAGE1);
		if (!strcmp(name, "automatic")) {
			set_param(MODE_AUTOMATIC);
			grab_automatic_params(value);
		}
		if (buf[i] == '\0')
			break;
		i++;
	}

	if (IS_AUTOMATIC && strcmp(get_auto_value("thirdparty"), "")) {
		set_param(MODE_THIRDPARTY);
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
				if (!strncmp(ptr+2, "rescue", 6)) set_param(MODE_RESCUE);
				ptr++;
			}
			ptr = buf;
			while ((ptr = strstr(ptr, "- "))) {
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

void unset_automatic(void)
{
	log_message("unsetting automatic");
	unset_param(MODE_AUTOMATIC);
	exit_bootsplash();
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


int image_has_stage2()
{
#ifdef MANDRAKE_MOVE
        return access(IMAGE_LOCATION "/live_tree.clp", R_OK) == 0;
#else
	return access(CLP_FILE_REL(IMAGE_LOCATION "/"), R_OK) == 0 ||
	       access(IMAGE_LOCATION "/" LIVE_LOCATION_REL, R_OK) == 0;
#endif
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

int clp_preload(void)
{
	if (total_memory() > (IS_RESCUE ? MEM_LIMIT_RESCUE_PRELOAD : MEM_LIMIT_DRAKX_PRELOAD))
		return 1;
	else {
		log_message("warning, not preloading clp due to low mem");
		return 0;
	}
}

enum return_type save_fd(int from_fd, char * to, void (*callback_func)(int overall))
{
        FILE * f_to;
        size_t quantity __attribute__((aligned(16))), overall = 0;
        char buf[4096] __attribute__((aligned(4096)));
        int ret = RETURN_ERROR;

        if (!(f_to = fopen(to, "w"))) {
                log_perror(to);
                goto close_from;
        }

        do {
		quantity = read(from_fd, buf, sizeof(buf));
		if (quantity > 0) {
                        if (fwrite(buf, 1, quantity, f_to) != quantity) {
                                log_message("short write (%s)", strerror(errno));
                                goto cleanup;
                        }
                } else if (quantity == -1) {
			log_message("an error occured: %s", strerror(errno));
			goto cleanup;
		}

                if (callback_func) {
                        overall += quantity;
                        callback_func(overall);
                }
        } while (quantity);

        ret = RETURN_OK;

 cleanup:
        fclose(f_to);
 close_from:
        close(from_fd);

        return ret;
}

enum return_type copy_file(char * from, char * to, void (*callback_func)(int overall))
{
        int from_fd;

	log_message("copy_file: %s -> %s", from, to);

	from_fd = open(from, O_RDONLY);
	if (from_fd != -1) {
		return save_fd(from_fd, to, callback_func);
	} else {
                log_perror(from);
                return RETURN_ERROR;
        }
}

enum return_type mount_clp(char *clp,  char *location_mount)
{
	if (lomount(clp, location_mount, NULL, 1)) {
                stg1_error_message("Could not mount compressed loopback :(.");
                return RETURN_ERROR;
        }
	return RETURN_OK;
}

enum return_type preload_mount_clp(int clp_fd, int clp_size, char *clp_name, char *location_mount)
{
	int ret;
	char *clp_tmpfs = asprintf_("%s/tmp/%s", SLASH_LOCATION, clp_name);
#ifdef MANDRAKE_MOVE
	static int count = 0;
	char buf[5000];
	sprintf(buf, "Loading program into memory (part %d)...", ++count);
#else
	char *buf = "Loading program into memory...";
#endif
	init_progression(buf, clp_size);
	ret = save_fd(clp_fd, clp_tmpfs, update_progression);
	end_progression();
	if (ret != RETURN_OK)
		return ret;
	
	return mount_clp(clp_tmpfs, location_mount);
}

enum return_type mount_clp_may_preload(char *clp_name, char *location_mount, int preload)
{
	char *clp = asprintf_("%s/%s", CLP_LOCATION, clp_name);

	log_message("mount_clp_may_preload: %s into %s (preload = %d)", clp, location_mount, preload);

        if (access(clp, R_OK) != 0) return RETURN_ERROR;

        if (preload) {
		int clp_fd = open(clp, O_RDONLY);
		if (clp_fd != -1) {
			return preload_mount_clp(clp_fd, file_size(clp), clp_name, location_mount);
		} else {
			log_perror(clp);
			return RETURN_ERROR;
		}
	} else {
                return mount_clp(clp, location_mount);
	}
}

#ifndef MANDRAKE_MOVE
enum return_type may_load_clp(void)
{
	if (!IS_RESCUE && access(IMAGE_LOCATION "/" LIVE_LOCATION_REL, R_OK) == 0) {
		/* LIVE install */
		return RETURN_OK;
	} else {
		/* CLP install */
		return mount_clp_may_preload(CLP_NAME(""), STAGE2_LOCATION, clp_preload());
	}
}

enum return_type load_clp_fd(int fd, int size)
{
	return preload_mount_clp(fd, size, CLP_NAME(""), STAGE2_LOCATION);
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

int try_mount(char * dev, char * location)
{
	char device_fullname[50];
	strcpy(device_fullname, "/dev/");
	strcat(device_fullname, dev);

	if (my_mount(device_fullname, location, "ext2", 0) == -1 &&
	    my_mount(device_fullname, location, "vfat", 0) == -1 &&
	    my_mount(device_fullname, location, "ntfs", 0) == -1 &&
	    my_mount(device_fullname, location, "reiserfs", 0) == -1 &&
	    my_mount(device_fullname, location, "iso9660", 0) == -1) {
                return 1;
        }

        return 0;
}

#ifndef DISABLE_DISK
int get_disks(char *** names, char *** models)
{
	char ** ptr;
	int count = 0;

	my_insmod("sd_mod", ANY_DRIVER_TYPE, NULL, 0);

	get_medias(DISK, names, models, BUS_ANY);

	ptr = *names;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

        return count;
}
#endif

#ifndef DISABLE_CDROM
int get_cdroms(char *** names, char *** models)
{
	char ** ptr;
	int count = 0;

	my_insmod("ide-cd", ANY_DRIVER_TYPE, NULL, 0);
	my_insmod("sr_mod", ANY_DRIVER_TYPE, NULL, 0);

	get_medias(CDROM, names, models, BUS_ANY);

	ptr = *names;
	while (ptr && *ptr) {
		count++;
		ptr++;
	}

	return count;
}
#endif

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
