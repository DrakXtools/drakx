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
 * (1) calculate dependencies
 * (2) unarchive relevant modules
 * (3) insmod them
 */

#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include "insmod.h"
#include "stage1.h"
#include "log.h"
#include "mar/mar-extract-only.h"
#include "frontend.h"
#include "mount.h"
#include "modules_descr.h"

#include "modules.h"

static struct module_deps_elem * modules_deps = NULL;

static char * archive_name = "/modules/modules.mar";
int disable_modules = 0;


/* unarchive and insmod given module
 * WARNING: module must not contain the trailing ".o"
 */
static enum insmod_return insmod_archived_file(const char * mod_name, char * options)
{
	char module_name[50];
	char final_name[50] = "/tmp/";
	int i, rc;

	strncpy(module_name, mod_name, sizeof(module_name));
	strcat(module_name, ".o");
	i = mar_extract_file(archive_name, module_name, "/tmp/");
	if (i == 1) {
		log_message("file-not-found-in-archive %s (maybe you can try another boot floppy such as 'other.img' for seldom used SCSI modules)", module_name);
		return INSMOD_FAILED_FILE_NOT_FOUND;
	}
	if (i != 0)
		return INSMOD_FAILED;

	strcat(final_name, mod_name);
	strcat(final_name, ".o");

	rc = insmod_call(final_name, options);
	unlink(final_name); /* sucking no space left on device */
	if (rc) {
		log_message("\tfailed");
		return INSMOD_FAILED;
	}
	return INSMOD_OK;
}



static int load_modules_dependencies(void)
{
	char * deps_file = "/modules/modules.dep";
	char * buf, * ptr, * start, * end;
	struct stat s;
	int fd, line, i;

	log_message("loading modules dependencies");

	if (IS_TESTING)
		return 0;

	fd = open(deps_file, O_RDONLY);
	if (fd == -1) {
		log_perror(deps_file);
		return -1;
	}
	
	fstat(fd, &s);
	buf = alloca(s.st_size + 1);
	if (read(fd, buf, s.st_size) != (ssize_t)s.st_size) {
		log_perror(deps_file);
		return -1;
	}
	buf[s.st_size] = '\0';
	close(fd);

	ptr = buf;
	line = 0;
	while (ptr) {
		line++;
		ptr = strchr(ptr + 1, '\n');
	}

	modules_deps = malloc(sizeof(*modules_deps) * (line+1));

	start = buf;
	line = 0;
	while (start < (buf+s.st_size) && *start) {
		char * tmp_deps[50];

		end = strchr(start, '\n');
		*end = '\0';

		ptr = strchr(start, ':');
		if (!ptr) {
			start = end + 1;
			continue;
		}
		*ptr = '\0';
		ptr++;

		while (*ptr && (*ptr == ' ')) ptr++;
		if (!*ptr) {
			start = end + 1;
			continue;
		}

		/* sort of a good line */
		modules_deps[line].name = strdup(start);

		start = ptr;
		i = 0;
		while (start && *start) {
			ptr = strchr(start, ' ');
			if (ptr) *ptr = '\0';
			tmp_deps[i++] = strdup(start);
			if (ptr)
				start = ptr + 1;
			else
				start = NULL;
			while (start && *start && *start == ' ')
				start++;
		}
		tmp_deps[i++] = NULL;

		modules_deps[line].deps = memdup(tmp_deps, sizeof(char *) * i);

		line++;
		start = end + 1;
	}
	modules_deps[line].name = NULL;

	return 0;
}


void init_modules_insmoding(void)
{
	if (load_modules_dependencies()) {
		log_message("warning, error initing modules stuff, modules loading disabled");
		disable_modules = 1;
	}
}


static void add_modules_conf(char * str)
{
	static char data[5000] = "";
	char * target = "/etc/modules.conf";
	int fd;

	if (strlen(data) + strlen(str) >= sizeof(data))
		return;

	strcat(data, str);
	strcat(data, "\n");

	fd = open(target, O_CREAT|O_WRONLY|O_TRUNC, 00660);
	
	if (fd == -1) {
		log_perror(str);
		return;
	}

	if (write(fd, data, strlen(data) + 1) != (ssize_t) (strlen(data) + 1))
		log_perror(str);

	close(fd);
}


int module_already_present(const char * name)
{
	FILE * f;
	int answ = 0;
	f = fopen("/proc/modules", "rb");
	while (1) {
		char buf[500];
		if (!fgets(buf, sizeof(buf), f)) break;
		if (!strncmp(name, buf, strlen(name)) && buf[strlen(name)] == ' ')
			answ = 1;
	}
	fclose(f);
	return answ;
}


static enum insmod_return insmod_with_deps(const char * mod_name, char * options)
{
	struct module_deps_elem * dep;

	dep = modules_deps;
	while (dep && dep->name && strcmp(dep->name, mod_name)) dep++;

	if (dep && dep->name && dep->deps) {
		char ** one_dep;
		one_dep = dep->deps;
		while (*one_dep) {
			/* here, we can fail but we don't care, if the error is
			 * important, the desired module will fail also */
			insmod_with_deps(*one_dep, NULL);
			one_dep++;
		}
	}

	if (module_already_present(mod_name))
		return INSMOD_OK;

	log_message("needs %s", mod_name);
	return insmod_archived_file(mod_name, options);
}


#ifndef DISABLE_NETWORK
enum insmod_return my_insmod(const char * mod_name, enum driver_type type, char * options)
#else
enum insmod_return my_insmod(const char * mod_name, enum driver_type type __attribute__ ((unused)), char * options)
#endif
{
	int i;
#ifndef DISABLE_NETWORK
	char ** net_devices = NULL; /* fucking compiler */
#endif

	log_message("have to insmod %s", mod_name);

	if (disable_modules) {
		log_message("\tdisabled");
		return INSMOD_OK;
	}

#ifndef DISABLE_NETWORK
	if (type == NETWORK_DEVICES)
		net_devices = get_net_devices();
#endif

	if (IS_TESTING)
		return INSMOD_OK;

	i = insmod_with_deps(mod_name, options);
	if (i == 0) {
		log_message("\tsucceeded %s", mod_name);
#ifndef DISABLE_NETWORK
		if (type == NETWORK_DEVICES) {
			char ** new_net_devices = get_net_devices();
			while (new_net_devices && *new_net_devices) {
				char alias[500];
				char ** ptr = net_devices;
				while (ptr && *ptr) {
					if (!strcmp(*new_net_devices, *ptr))
						goto already_present;
					ptr++;
				}
				sprintf(alias, "alias %s %s", *new_net_devices, mod_name);
				add_modules_conf(alias);
				log_message("NET: %s", alias);
				net_discovered_interface(*new_net_devices);
				
			already_present:
				new_net_devices++;
			}
		}
#endif
	} else
		log_message("warning, insmod failed (%s %s) (%d)", mod_name, options, i);
	
	return i;

}

static enum return_type insmod_with_options(char * mod, enum driver_type type)
{
	char * questions[] = { "Options", NULL };
	static char ** answers = NULL;
	enum return_type results;
	char options[500] = "options ";

	results = ask_from_entries("Please enter the parameters to give to the kernel:", questions, &answers, 24, NULL);
	if (results != RETURN_OK)
		return results;

	strcat(options, mod);
	strcat(options, " ");
	strcat(options, answers[0]); // because my_insmod will eventually modify the string
	
	if (my_insmod(mod, type, answers[0]) != INSMOD_OK) {
		stg1_error_message("Insmod failed.");
		return RETURN_ERROR;
	}
	
	add_modules_conf(options);

	return RETURN_OK;
}

enum return_type ask_insmod(enum driver_type type)
{
	char * mytype;
	char msg[200];
	enum return_type results;
	char * choice;

	unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */

	if (type == SCSI_ADAPTERS)
		mytype = "SCSI";
	else if (type == NETWORK_DEVICES)
		mytype = "NET";
	else
		return RETURN_ERROR;

	if (disable_modules)
		return RETURN_BACK;

	snprintf(msg, sizeof(msg), "Which driver should I try to gain %s access?", mytype);

	{
		char ** drivers = mar_list_contents(archive_name);
		char ** descrs = malloc(sizeof(char *) * string_array_length(drivers));
		char ** p_drivers = drivers;
		char ** p_descrs = descrs;
		while (p_drivers && *p_drivers) {
			int i;
			*p_descrs = NULL;
			for (i = 0 ; i < modules_descriptions_num ; i++) {
				if (!strncmp(*p_drivers, modules_descriptions[i].module, strlen(modules_descriptions[i].module))
				    && (*p_drivers)[strlen(modules_descriptions[i].module)] == '.') /* one contains '.o' not the other */
					*p_descrs = modules_descriptions[i].descr;
			}
			p_drivers++;
			p_descrs++;
		}
		results = ask_from_list_comments(msg, drivers, descrs, &choice);
	}

	if (results == RETURN_OK) {
		choice[strlen(choice)-2] = '\0'; /* remove trailing .o */
		return insmod_with_options(choice, type);
	} else
		return results;
}


void update_modules(void)
{
	FILE * f;
	char ** disk_contents;
	char final_name[500];
	char floppy_mount_location[] = "/tmp/floppy";

	stg1_info_message("Please insert the Update Modules floppy.");;

	my_insmod("floppy", ANY_DRIVER_TYPE, NULL);

	if (my_mount("/dev/fd0", floppy_mount_location, "ext2", 0) == -1) {
		enum return_type results = ask_yes_no("I can't find a Linux ext2 floppy in first floppy drive.\n"
						      "Retry?");
		if (results == RETURN_OK)
			return update_modules();
		return;
	}

	disk_contents = list_directory(floppy_mount_location);

	if (!(f = fopen("/tmp/floppy/to_load", "rb"))) {
		stg1_error_message("I can't find \"to_load\" file.");
		umount(floppy_mount_location);
		return update_modules();
	}
	while (1) {
		char module[500];
		char * options;
		char ** entry = disk_contents;

		if (!fgets(module, sizeof(module), f)) break;
		if (module[0] == '#' || strlen(module) == 0)
			continue;

		while (module[strlen(module)-1] == '\n')
			module[strlen(module)-1] = '\0';
		options = strchr(module, ' ');
		if (options) {
			options[0] = '\0';
			options++;
		}

		log_message("updatemodules: (%s) (%s)", module, options);
		while (entry && *entry) {
			if (!strncmp(*entry, module, strlen(module)) && (*entry)[strlen(module)] == '.') {
				sprintf(final_name, "%s/%s", floppy_mount_location, *entry);
				if (insmod_call(final_name, options)) {
					log_message("\t%s (floppy): failed", *entry);
					stg1_error_message("Insmod %s (floppy) failed.", *entry);
				}
				break;
			}
			entry++;
		}
		if (!entry || !*entry) {
			enum insmod_return ret = my_insmod(module, ANY_DRIVER_TYPE, options);
			if (ret != INSMOD_OK) {
				log_message("\t%s (marfile): failed", module);
				stg1_error_message("Insmod %s (marfile) failed.", module);
			}
		}
	}
	fclose(f);
	umount(floppy_mount_location);
}
