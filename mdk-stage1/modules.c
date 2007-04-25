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
#include <errno.h>
#include "stage1.h"
#include "log.h"
#include "frontend.h"
#include "mount.h"
#include "modules_descr.h"
#include "zlibsupport.h"

#include "modules.h"

static struct module_deps_elem * modules_deps = NULL;

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
  return ".ko.gz";
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
		fatal_error("warning, error initing modules stuff, modules loading disabled");
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
	return answ;
}


static enum insmod_return insmod_with_deps(const char * mod_name, char * options, int allow_modules_floppy)
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
			insmod_with_deps(*one_dep, NULL, allow_modules_floppy);
			one_dep++;
		}
	}

	if (module_already_present(mod_name))
		return INSMOD_OK;

	log_message("needs %s", mod_name);
	{
		char *file = asprintf_("/modules/%s%s", mod_name, kernel_module_extension());
		return insmod_local_file(file, options);
	}
}


static const char * get_name_kernel_26_transition(const char * name)
{
	struct kernel_24_26_mapping {
		const char * name_24;
		const char * name_26;
	};
	static struct kernel_24_26_mapping mappings[] = {
                { "usb-ohci", "ohci-hcd" },
                { "usb-uhci", "uhci-hcd" },
                { "uhci", "uhci-hcd" },
//                { "printer", "usblp" },
                { "bcm4400", "b44" },
                { "3c559", "3c359" },
                { "3c90x", "3c59x" },
                { "dc395x_trm", "dc395x" },
//                { "audigy", "snd-emu10k1" },
        };
	int mappings_nb = sizeof(mappings) / sizeof(struct kernel_24_26_mapping);
        int i;

        /* pcitable contains 2.4 names. this will need to change if/when it contains 2.6 names! */
        for (i=0; i<mappings_nb; i++) {
            if (streq(name, mappings[i].name_24))
                return mappings[i].name_26;
        }
        return name;
}


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

        const char * real_mod_name = get_name_kernel_26_transition(mod_name);

	if (module_already_present(real_mod_name))
		return INSMOD_OK;

	log_message("have to insmod %s", real_mod_name);

#ifndef DISABLE_NETWORK
	if (type == NETWORK_DEVICES)
		net_devices = get_net_devices();
#endif

	if (IS_TESTING)
		return INSMOD_OK;

#ifdef ENABLE_NETWORK_STANDALONE
	{
		char *cmd = options ? asprintf_("/sbin/modprobe %s %s", mod_name, options) : 
			              asprintf_("/sbin/modprobe %s", mod_name);
		log_message("running %s", cmd);
		i = system(cmd);
	}
#else
	i = insmod_with_deps(real_mod_name, options, allow_modules_floppy);
#endif
	if (i == 0) {
		log_message("\tsucceeded %s", real_mod_name);
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
		log_message("warning, insmod failed (%s %s) (%d)", real_mod_name, options, i);
	
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

enum return_type ask_insmod(enum driver_type type)
{
	char * mytype;
	char msg[200];
	enum return_type results;
	char * choice;

	unset_automatic(); /* we are in a fallback mode */

	if (type == SCSI_ADAPTERS)
		mytype = "SCSI";
	else if (type == NETWORK_DEVICES)
		mytype = "NET";
	else
		return RETURN_ERROR;

	snprintf(msg, sizeof(msg), "Which driver should I try to gain %s access?", mytype);

	{
		char ** modules = NULL;
		char ** descrs = malloc(sizeof(char *) * string_array_length(modules));
		char ** p_modules = modules;
		char ** p_descrs = descrs;
		while (p_modules && *p_modules) {
			int i;
			*p_descrs = NULL;
			for (i = 0 ; i < modules_descriptions_num ; i++) {
				if (!strncmp(*p_modules, modules_descriptions[i].module, strlen(modules_descriptions[i].module))
				    && (*p_modules)[strlen(modules_descriptions[i].module)] == '.') /* one contains '.ko.gz' not the other */
					*p_descrs = modules_descriptions[i].descr;
			}
			p_modules++;
			p_descrs++;
		}
		if (modules && *modules)
			results = ask_from_list_comments(msg, modules, descrs, &choice);
		else
			results = RETURN_BACK;
	}

	if (results == RETURN_OK) {
		choice[strlen(choice)-strlen(kernel_module_extension())] = '\0'; /* remove trailing .ko.gz */
		return insmod_with_options(choice, type);
	} else
		return results;
}
