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
#include <zlib.h>
#include "stage1.h"
#include "log.h"
#include "mount.h"
#include "frontend.h"

#include "tools.h"


struct cmdline_elem
{
	char * name;
	char * value;
};

struct cmdline_elem * params;

void process_cmdline(void)
{
	char buf[512];
	int fd, size, i, p;
	struct cmdline_elem tmp_params[50];
	
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

		tmp_params[p].name = name;
		tmp_params[p].value = value;
		p++;
		i++;
		if (!strcmp(name, "expert")) set_param(MODE_EXPERT);
		if (!strcmp(name, "rescue")) set_param(MODE_RESCUE);
		if (!strcmp(name, "pcmcia")) set_param(MODE_PCMCIA);
		if (!strcmp(name, "cdrom")) set_param(MODE_CDROM);
		if (!strcmp(name, "special_stage2")) set_param(MODE_SPECIAL_STAGE2);
	}
	
	if (IS_RESCUE) {
		tmp_params[p].name = "special_stage2";
		tmp_params[p].value = "rescue";
		p++;
		set_param(MODE_SPECIAL_STAGE2);
	}

	tmp_params[p++].name = NULL;

	params = (struct cmdline_elem *) malloc(sizeof(struct cmdline_elem) * p);
	memcpy(params, tmp_params, sizeof(struct cmdline_elem) * p);

	log_message("\tgot %d args", p);
}


int stage1_mode = 0;

int get_param(int i)
{
	return (stage1_mode & i);
}

char * get_param_valued(char *param_name)
{
	struct cmdline_elem * ptr = params;

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

	while (buf[i] != 0 && isdigit(buf[i])) {
	    memtotal = (memtotal * 10) + (buf[i] - '0');
	    i++;
	}
	
	log_message("%s %d kB", memtotal_tag, memtotal);

	return memtotal;
}


int ramdisk_possible(void)
{
	if (total_memory() > MEM_LIMIT_RAMDISK)
		return 1;
	else {
		log_message("Warning, ramdisk is not possible due to low mem!");
		return 0;
	}
}


enum return_type load_ramdisk(void)
{
	char * img_name;
	gzFile st2;
	char * ramdisk = "/dev/ram3"; /* warning, verify that this file exists in the initrd (and actually is a ramdisk device file) */
	int ram_fd;
	char buffer[4096];
	char * stg2_name = get_param_valued("special_stage2");
	char * begin_img = "/tmp/image/Mandrake/base/";
	char * end_img = "_stage2.gz";
	int gz_errnum;

	if (!stg2_name)
		stg2_name = "mdkinst";

	if (IS_RESCUE)
		stg2_name = "rescue";
	
	img_name = malloc(strlen(begin_img) + strlen(stg2_name) + strlen(end_img) + 1);
	strcpy(img_name, begin_img);
	strcat(img_name, stg2_name);
	strcat(img_name, end_img);

	log_message("trying to load %s as a ramdisk", img_name);

	st2 = gzopen(img_name, "r");
	if (!st2) {
		log_message("Opening compressed ramdisk: %s", gzerror(st2, &gz_errnum));
		error_message("Could not open compressed ramdisk file.");
		return RETURN_ERROR;
	}

	ram_fd = open(ramdisk, O_WRONLY);
	if (ram_fd == -1) {
		log_perror(ramdisk);
		error_message("Could not open ramdisk device file.");
		return RETURN_ERROR;
	}

	wait_message("Loading Installation program into memory...");

	while (!gzeof(st2)) {
		int actually = gzread(st2, buffer, sizeof(buffer));
		if (actually != sizeof(buffer) && !gzeof(st2)) {
			log_message("Reading compressed ramdisk: %s", gzerror(st2, &gz_errnum));
			remove_wait_message();
			return RETURN_ERROR;
		}
		if (write(ram_fd, buffer, actually) != actually) {
			log_perror("Writing ramdisk");
			remove_wait_message();
			return RETURN_ERROR;
		}
		log_progression(100);
	}

	log_progression_done();
	remove_wait_message();
	gzclose(st2);
	close(ram_fd);

	if (IS_RESCUE)
		return RETURN_OK; /* fucksike, I lost several hours wondering why the kernel won't see the rescue if it is alreay mounted */

	if (my_mount(ramdisk, "/tmp/stage2", "ext2"))
		return RETURN_ERROR;

	set_param(MODE_RAMDISK);

	return RETURN_OK;
}

