/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2000 Mandriva
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

#include "stage1.h"

#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <fcntl.h>
#include <libgen.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <sys/utsname.h>
#include "log.h"
#include "utils.h"
#include "frontend.h"
#include "mount.h"
#include "zlibsupport.h"

#include "modules.h"

#define UEVENT_HELPER_FILE "/sys/kernel/uevent_helper"
#define UEVENT_HELPER_VALUE "/sbin/hotplug"

static char modules_directory[100];
static struct module_deps_elem * modules_deps = NULL;
static struct module_descr_elem * modules_descr = NULL;

extern long init_module(void *, unsigned long, const char *);


static const char *moderror(int err)
{
	switch (err) {
	case ENOEXEC:
		return "Invalid module format";
	case ENOENT:
		return "Unknown symbol in module";
	case ESRCH:
		return "Module has wrong symbol version";
	case EINVAL:
		return "Invalid parameters";
	default:
		return strerror(err);
	}
}

int insmod_local_file(char * path, char * options)
{
	void *file;
	unsigned long len;
	int rc;
                
	if (IS_TESTING)
		return 0;

	file = grab_file(path, &len);
                
	if (!file) {
		log_perror(asprintf_("\terror reading %s", path));
		return -1;
	}
                
	rc = init_module(file, len, options ? options : "");
	if (rc)
		log_message("\terror: %s", moderror(errno));
	return rc;
}

static char *kernel_module_extension(void)
{
	return ".ko";
}


static char *filename2modname(char * filename) {
	char *modname, *p;

	modname = strdup(basename(filename));
	if (strstr(modname, kernel_module_extension())) {
		modname[strlen(modname)-strlen(kernel_module_extension())] = '\0'; /* remove trailing .ko.gz */
	}

	p = modname;
	while (p && *p) {
		if (*p == '-')
			*p = '_';
		p++;
	}

	return modname;
}

static void find_modules_directory(void)
{
	struct utsname kernel_uname;
	char * prefix = "/lib/modules";
	char * release;
	if (uname(&kernel_uname)) {
		fatal_error("uname failed");
	}
	release = kernel_uname.release;
	sprintf(modules_directory , "%s/%s", prefix, release);
}

static int load_modules_dependencies(void)
{
	char * deps_file = asprintf_("%s/%s", modules_directory, "modules.dep");
	char * buf, * ptr, * start, * end;
	struct stat s;
	int line, i;

	log_message("loading modules dependencies");
	buf = cat_file(deps_file, &s);
	if (!buf)
		return -1;
	line = line_counts(buf);
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

		/* sort of a good line */
		modules_deps[line].filename = start[0] == '/' ? strdup(start) : asprintf_("%s/%s", modules_directory, start);
		modules_deps[line].modname = filename2modname(start);

		start = ptr;
		i = 0;
		while (start && *start && i < sizeof(tmp_deps)/sizeof(char *)) {
			ptr = strchr(start, ' ');
			if (ptr) *ptr = '\0';
			tmp_deps[i++] = filename2modname(start);
			if (ptr)
				start = ptr + 1;
			else
				start = NULL;
			while (start && *start && *start == ' ')
				start++;
		}
		if(i >= sizeof(tmp_deps)/sizeof(char *)-1) {
			log_message("warning, more than %zu dependencies for module %s",
				    sizeof(tmp_deps)/sizeof(char *)-1,
				    modules_deps[line].modname);
			i = sizeof(tmp_deps)/sizeof(char *)-1;
		}
		tmp_deps[i++] = NULL;

		modules_deps[line].deps = memdup(tmp_deps, sizeof(char *) * i);

		line++;
		start = end + 1;
	}
	modules_deps[line].modname = NULL;

	free(buf);

	return 0;
}


static int load_modules_descriptions(void)
{
	char * descr_file = asprintf_("%s/%s", modules_directory, "modules.description");
	char * buf, * ptr, * start, * end;
	struct stat s;
	int line;

	log_message("loading modules descriptions");

	buf = cat_file(descr_file, &s);
	if (!buf)
		return -1;
	line = line_counts(buf);
	modules_descr = malloc(sizeof(*modules_descr) * (line+1));

	start = buf;
	line = 0;
	while (start < (buf+s.st_size) && *start) {
		end = strchr(start, '\n');
		*end = '\0';

		ptr = strchr(start, '\t');
		if (!ptr) {
			start = end + 1;
			continue;
		}
		*ptr = '\0';
		ptr++;

		modules_descr[line].modname = filename2modname(start);
		modules_descr[line].description = strndup(ptr, 50);

		line++;
		start = end + 1;
	}
	modules_descr[line].modname = NULL;

	free(buf);

	return 0;
}

void init_firmware_loader(void)
{
	int fd = open(UEVENT_HELPER_FILE, O_WRONLY|O_TRUNC, 0666);
	if (!fd) {
		log_message("warning, unable to set firmware loader");
		return;
	}
	write(fd, UEVENT_HELPER_VALUE, strlen(UEVENT_HELPER_VALUE));
	close(fd);
}

void init_modules_insmoding(void)
{
	find_modules_directory();
	if (load_modules_dependencies()) {
		fatal_error("warning, error initing modules stuff, modules loading disabled");
	}
	if (load_modules_descriptions()) {
		log_message("warning, error initing modules stuff");
	}
}


static void add_modules_conf(char * str)
{
	static char data[5000] = "";
	char * target = "/tmp/modules.conf";
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

	if ((f = fopen("/proc/modules", "rb"))) {
                while (1) {
                        char buf[500];
                        if (!fgets(buf, sizeof(buf), f)) break;
                        if (!strncmp(name, buf, strlen(name)) && buf[strlen(name)] == ' ')
                                answ = 1;
                }
                fclose(f);
        }
       /* built-in module case. try to find them through sysfs */
       if (!answ) {
               asprintf(&path, "/sys/module/%s", name);
               if (!stat(path, &sb))
                       answ = 1;
               free(path);
       }
	return answ;
}


#ifndef ENABLE_NETWORK_STANDALONE
static enum insmod_return insmod_with_deps(const char * mod_name, char * options, int allow_modules_floppy)
{
	struct module_deps_elem * dep;
	const char * filename;

	dep = modules_deps;
	while (dep && dep->modname && strcmp(dep->modname, mod_name)) dep++;

	if (dep && dep->modname && dep->deps) {
		char ** one_dep;
		one_dep = dep->deps;
		while (*one_dep) {
			/* here, we can fail but we don't care, if the error is
			 * important, the desired module will fail also */
			insmod_with_deps(*one_dep, NULL, allow_modules_floppy);
			one_dep++;
		}
	}
        
	if (dep && dep->filename) {
	       filename = dep->filename;
	} else {
		log_message("warning: unable to get module filename for %s", mod_name);
		filename = mod_name;
	}

	if (module_already_present(mod_name))
		return INSMOD_OK;

	log_message("needs %s", filename);
	{
		return insmod_local_file((char *) filename, options);
	}
}
#endif


#ifndef DISABLE_NETWORK
enum insmod_return my_insmod(const char * mod_name, enum driver_type type, char * options, int allow_modules_floppy)
#else
enum insmod_return my_insmod(const char * mod_name, enum driver_type type __attribute__ ((unused)), char * options, int allow_modules_floppy)
#endif
{
	int i;
#ifndef DISABLE_NETWORK
	char ** net_devices = NULL; /* fucking compiler */
#endif

	if (module_already_present(mod_name))
		return INSMOD_OK;

	log_message("have to insmod %s", mod_name);

#ifndef DISABLE_NETWORK
	if (type == NETWORK_DEVICES)
		net_devices = get_net_devices();
#endif

#ifdef ENABLE_NETWORK_STANDALONE
	{
		char *cmd = options ? asprintf_("/sbin/modprobe %s %s", mod_name, options) : 
			              asprintf_("/sbin/modprobe %s", mod_name);
		log_message("running %s", cmd);
		i = system(cmd);
	}
#else
	i = insmod_with_deps(mod_name, options, allow_modules_floppy);
#endif
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
	
	if (my_insmod(mod, type, answers[0], 1) != INSMOD_OK) {
		stg1_error_message("Insmod failed.");
		return RETURN_ERROR;
	}
	
	add_modules_conf(options);

	return RETURN_OK;
}

static int strsortfunc(const void *a, const void *b)
{
    return strcmp(* (char * const *) a, * (char * const *) b);
}

enum return_type ask_insmod(enum driver_type type)
{
	enum return_type results;
	char * choice;
	char ** dlist = list_directory(modules_directory);
	char ** modules = alloca(sizeof(char *) * (string_array_length(dlist) + 1));
	char ** descrs = alloca(sizeof(char *) * (string_array_length(dlist) + 1));
	char ** p_dlist = dlist;
	char ** p_modules = modules;
	char ** p_descrs = descrs;

	qsort(dlist, string_array_length(dlist), sizeof(char *), strsortfunc);

	unset_automatic(); /* we are in a fallback mode */

	while (p_dlist && *p_dlist) {
		struct module_descr_elem * descr;
		if (!strstr(*p_dlist, kernel_module_extension())) {
			p_dlist++;
			continue;
		}
		*p_modules = *p_dlist;
		*p_descrs = NULL;
		(*p_modules)[strlen(*p_modules)-strlen(kernel_module_extension())] = '\0'; /* remove trailing .ko.gz */

		descr = modules_descr;
		while (descr && descr->modname && strcmp(descr->modname, *p_modules)) descr++;
		if (descr)
			*p_descrs = descr->description;

		p_dlist++;
		p_modules++;
		p_descrs++;
	}
	*p_modules = NULL;
	*p_descrs = NULL;

	if (modules && *modules) {
		char * mytype;
		char msg[200];
		if (type == MEDIA_ADAPTERS)
			mytype = "MEDIA";
		else if (type == NETWORK_DEVICES)
			mytype = "NET";
		else
			return RETURN_ERROR;

		snprintf(msg, sizeof(msg), "Which driver should I try to gain %s access?", mytype);
		results = ask_from_list_comments(msg, modules, descrs, &choice);
		if (results == RETURN_OK)
			return insmod_with_options(choice, type);
		else
			return results;
	} else {
		return RETURN_BACK;
	}
}
