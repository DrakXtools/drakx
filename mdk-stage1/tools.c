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

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/types.h>
#include <bzlib.h>
#include "stage1.h"
#include "log.h"
#include "mount.h"
#include "frontend.h"
#include "automatic.h"

#include "tools.h"


static struct param_elem * params;

void process_cmdline(void)
{
	char buf[512];
	int fd, size, i, p;
	struct param_elem tmp_params[50];
	
	log_message("opening /proc/cmdline... ");
	
	if ((fd = open("/proc/cmdline", O_RDONLY, 0)) == -1)
		fatal_error("could not open /proc/cmdline");
	
	size = read(fd, buf, sizeof(buf));
	buf[size-1] = 0;
	close(fd);

	log_message("\t%s", buf);

	i = 0; p = 0;
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

		tmp_params[p].name = name;
		tmp_params[p].value = value;
		if (!strcmp(name, "expert")) set_param(MODE_EXPERT);
		if (!strcmp(name, "rescue")) set_param(MODE_RESCUE);
		if (!strcmp(name, "special_stage2")) set_param(MODE_SPECIAL_STAGE2);
		if (!strcmp(name, "automatic")) {
			set_param(MODE_AUTOMATIC);
			grab_automatic_params(value);
		}
		p++;
		if (buf[i] == '\0')
			break;
		i++;
	}
	
	if (IS_RESCUE) {
		tmp_params[p].name = "special_stage2";
		tmp_params[p].value = "rescue";
		p++;
		set_param(MODE_SPECIAL_STAGE2);
	}

	tmp_params[p++].name = NULL;

	params = memdup(tmp_params, sizeof(struct param_elem) * p);

	log_message("\tgot %d args", p-1);
}


int stage1_mode = 0;

int get_param(int i)
{
	return (stage1_mode & i);
}

char * get_param_valued(char *param_name)
{
	struct param_elem * ptr = params;

	while (ptr->name) {
		if (!strcmp(ptr->name, param_name))
			return ptr->value;
		ptr++;
	}

	return NULL;
}

void set_param(int i)
{
	stage1_mode |= i;
}

void unset_param(int i)
{
	stage1_mode &= ~i;
}

int charstar_to_int(char * s)
{
	int number = 0;
	while (*s && isdigit(*s)) {
		number = (number * 10) + (*s - '0');
		s++;
	}
	return number;
}

int total_memory(void)
{
	int fd;
	int i;
	char buf[4096];
	char * memtotal_tag = "MemTotal:";
	int memtotal = 0;
    
	fd = open("/proc/meminfo", O_RDONLY);
	if (fd == -1)
		fatal_error("could not open /proc/meminfo");

	i = read(fd, buf, sizeof(buf));
	if (i < 0)
		fatal_error("could not read /proc/meminfo");
		
	close(fd);
	buf[i] = 0;

	i = 0;
	while (buf[i] != 0 && strncmp(&buf[i], memtotal_tag, strlen(memtotal_tag)))
		i++;

	while (buf[i] != 0 && buf[i] != '\n' && !isdigit(buf[i]))
		i++;

	if (buf[i] == 0 || buf[i] == '\n')
		fatal_error("could not read MemTotal");

	memtotal = charstar_to_int(&(buf[i]));
	
	log_message("%s %d kB", memtotal_tag, memtotal);

	return memtotal;
}


int ramdisk_possible(void)
{
	if (total_memory() > MEM_LIMIT_RAMDISK)
		return 1;
	else {
		log_message("warning, ramdisk is not possible due to low mem!");
		return 0;
	}
}


enum return_type load_ramdisk_fd(int ramdisk_fd, int size)
{
	BZFILE * st2;
	char * ramdisk = "/dev/ram3"; /* warning, verify that this file exists in the initrd (and actually is a ramdisk device file) */
	int ram_fd;
	char buffer[4096];
	int z_errnum;
	char * wait_msg = "Loading program into memory...";
	int bytes_read = 0;
	int actually;
	int seems_ok = 0;

	st2 = BZ2_bzdopen(ramdisk_fd, "r");

	if (!st2) {
		log_message("Opening compressed ramdisk: %s", BZ2_bzerror(st2, &z_errnum));
		error_message("Could not open compressed ramdisk file.");
		return RETURN_ERROR;
	}

	ram_fd = open(ramdisk, O_WRONLY);
	if (ram_fd == -1) {
		log_perror(ramdisk);
		error_message("Could not open ramdisk device file.");
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
		remove_wait_message();
		error_message("Could not uncompress second stage ramdisk.");
		return RETURN_ERROR;
	}

	end_progression();

	BZ2_bzclose(st2); /* opened by gzdopen, but also closes the associated fd */
	close(ram_fd);

	if (IS_RESCUE)
		return RETURN_OK; /* fucksike, I lost several hours wondering why the kernel won't see the rescue if it is alreay mounted */

	if (my_mount(ramdisk, STAGE2_LOCATION, "ext2"))
		return RETURN_ERROR;

	set_param(MODE_RAMDISK);

	return RETURN_OK;
}


char * get_ramdisk_realname(void)
{
	char img_name[500];
	char * stg2_name = get_param_valued("special_stage2");
	char * begin_img = RAMDISK_LOCATION;
	char * end_img = "_stage2.bz2";

	if (!stg2_name)
		stg2_name = "mdkinst";

	if (IS_RESCUE)
		stg2_name = "rescue";
	
	strcpy(img_name, begin_img);
	strcat(img_name, stg2_name);
	strcat(img_name, end_img);

	return strdup(img_name);
}


enum return_type load_ramdisk(void)
{
	int st2_fd;
	struct stat statr;
	char img_name[500];

	strcpy(img_name, IMAGE_LOCATION);
	strcat(img_name, get_ramdisk_realname());

	log_message("trying to load %s as a ramdisk", img_name);

	st2_fd = open(img_name, O_RDONLY); /* to be able to see the progression */

	if (st2_fd == -1) {
		log_message("open ramdisk file (%s) failed", img_name);
		error_message("Could not open compressed ramdisk file (%s).", img_name);
		return RETURN_ERROR;
	}

	if (stat(img_name, &statr))
		return RETURN_ERROR;
	else
		return load_ramdisk_fd(st2_fd, statr.st_size);
}

/* pixel's */
void * memdup(void *src, size_t size)
{
	void * r;
	r = malloc(size);
	memcpy(r, src, size);
	return r;
}


static char ** my_env = NULL;
static int env_size = 0;

void handle_env(char ** env)
{
	char ** ptr = env;
	while (ptr && *ptr) {
		ptr++;
		env_size++;
	}
	my_env = malloc(sizeof(char *) * 100);
	memcpy(my_env, env, sizeof(char *) * (env_size+1));
}

char ** grab_env(void) {
	return my_env;
}

void add_to_env(char * name, char * value)
{
	char tmp[500];
	sprintf(tmp, "%s=%s", name, value);
	my_env[env_size] = strdup(tmp);
	env_size++;
	my_env[env_size] = NULL;
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
