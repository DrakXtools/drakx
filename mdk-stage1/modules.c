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
#include <errno.h>
#include "insmod.h"
#include "stage1.h"
#include "log.h"
#include "mar/mar-extract-only.h"
#include "frontend.h"
#include "mount.h"
#include "modules_descr.h"

#include "modules.h"

static struct module_deps_elem * modules_deps = NULL;

static char archive_name[] = "/modules/modules.mar";
static char additional_archive_name[] = "/tmp/tmpfs/modules.mar";
int allow_additional_modules_floppy = 1;

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

static void *grab_file(const char *filename, unsigned long *size)
{
	unsigned int max = 16384;
	int ret, fd;
	void *buffer = malloc(max);

        fd = open(filename, O_RDONLY, 0);
	if (fd < 0)
		return NULL;

	*size = 0;
	while ((ret = read(fd, buffer + *size, max - *size)) > 0) {
		*size += ret;
		if (*size == max)
			buffer = realloc(buffer, max *= 2);
	}
	if (ret < 0) {
		free(buffer);
		buffer = NULL;
	}
	close(fd);
	return buffer;
}

static enum return_type ensure_additional_modules_available(void)
{
        struct stat statbuf;
        if (stat(additional_archive_name, &statbuf)) {
                char floppy_mount_location[] = "/tmp/floppy";
                char floppy_modules_mar[] = "/tmp/floppy/modules.mar";
                int ret;
                int automatic = 0;

                if (stat("/tmp/tmpfs", &statbuf)) {
                        if (scall(mkdir("/tmp/tmpfs", 0755), "mkdir"))
                                return RETURN_ERROR;
                        if (scall(mount("none", "/tmp/tmpfs", "tmpfs", MS_MGC_VAL, NULL), "mount tmpfs"))
                                return RETURN_ERROR;
                }
                
                if (IS_AUTOMATIC) {
                        unset_param(MODE_AUTOMATIC);
                        automatic = 1;
                }
          
        retry:
                stg1_info_message("Please insert the Additional Drivers floppy.");;

                while (my_mount(floppy_device(), floppy_mount_location, "ext2", 0) == -1) {
                        enum return_type results = ask_yes_no(errno == ENXIO ?
                                                              "There is no detected floppy drive, or no floppy disk in drive.\nRetry?"
                                                              : errno == EINVAL ?
                                                              "Floppy is not a Linux ext2 floppy in first floppy drive.\nRetry?"
                                                              : "Can't find a linux ext2 floppy in first floppy drive.\nRetry?");
                        if (results != RETURN_OK) {
                                allow_additional_modules_floppy = 0;
                                if (automatic)
                                        set_param(MODE_AUTOMATIC);
                                return results;
                        }
                }
                                
                if (stat(floppy_modules_mar, &statbuf)) {
                        stg1_error_message("This is not an Additional Drivers floppy, as far as I can see.");
                        umount(floppy_mount_location);
                        goto retry;
                }

                init_progression("Copying...", file_size(floppy_modules_mar));
                ret = copy_file(floppy_modules_mar, additional_archive_name, update_progression);
                end_progression();
                umount(floppy_mount_location);
                if (automatic)
                        set_param(MODE_AUTOMATIC);
                return ret;
        } else
                return RETURN_OK;
}

int insmod_local_file(char * path, char * options)
{
        if (kernel_version() <= 4) {
                return insmod_call(path, options);
        } else {
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
}

/* unarchive and insmod given module
 * WARNING: module must not contain the trailing ".o"
 */
static enum insmod_return insmod_archived_file(const char * mod_name, char * options, int allow_modules_floppy)
{
	char module_name[50];
	char final_name[50] = "/tmp/";
	int i, rc;

	strncpy(module_name, mod_name, sizeof(module_name));
        if (kernel_version() <= 4)
                strcat(module_name, ".o");
        else
                strcat(module_name, ".ko");
	i = mar_extract_file(archive_name, module_name, "/tmp/");
	if (i == 1) {
                static int recurse = 0;
                if (allow_additional_modules_floppy && allow_modules_floppy && !recurse) {
                        recurse = 1;
                        if (ensure_additional_modules_available() == RETURN_OK)
                                i = mar_extract_file(additional_archive_name, module_name, "/tmp/");
                        recurse = 0;
                }
        }
        if (i == 1) {
                log_message("file-not-found-in-archive %s (maybe you can try another boot floppy such as 'hdcdrom_usb.img')", module_name);
                return INSMOD_FAILED_FILE_NOT_FOUND;
        }
	if (i != 0)
		return INSMOD_FAILED;

	strcat(final_name, module_name);

        rc = insmod_local_file(final_name, options);

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
	return insmod_archived_file(mod_name, options, allow_modules_floppy);
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
        if (kernel_version() > 4)
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

	i = insmod_with_deps(real_mod_name, options, allow_modules_floppy);
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

	unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */

	if (type == SCSI_ADAPTERS)
		mytype = "SCSI";
	else if (type == NETWORK_DEVICES)
		mytype = "NET";
	else
		return RETURN_ERROR;

	snprintf(msg, sizeof(msg), "Which driver should I try to gain %s access?", mytype);

	{
		char ** modules = mar_list_contents(ensure_additional_modules_available() == RETURN_OK ? additional_archive_name
                                                                                                       : archive_name);
		char ** descrs = malloc(sizeof(char *) * string_array_length(modules));
		char ** p_modules = modules;
		char ** p_descrs = descrs;
		while (p_modules && *p_modules) {
			int i;
			*p_descrs = NULL;
			for (i = 0 ; i < modules_descriptions_num ; i++) {
				if (!strncmp(*p_modules, modules_descriptions[i].module, strlen(modules_descriptions[i].module))
				    && (*p_modules)[strlen(modules_descriptions[i].module)] == '.') /* one contains '.o' not the other */
					*p_descrs = modules_descriptions[i].descr;
			}
			p_modules++;
			p_descrs++;
		}
		results = ask_from_list_comments(msg, modules, descrs, &choice);
	}

	if (results == RETURN_OK) {
                if (kernel_version() <= 4)
                        choice[strlen(choice)-2] = '\0'; /* remove trailing .o */
                else
                        choice[strlen(choice)-3] = '\0'; /* remove trailing .ko */
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

	if (my_mount(floppy_device(), floppy_mount_location, "ext2", 0) == -1) {
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
				if (insmod_local_file(final_name, options)) {
					log_message("\t%s (floppy): failed", *entry);
					stg1_error_message("Insmod %s (floppy) failed.", *entry);
				}
				break;
			}
			entry++;
		}
		if (!entry || !*entry) {
			enum insmod_return ret = my_insmod(module, ANY_DRIVER_TYPE, options, 0);
			if (ret != INSMOD_OK) {
				log_message("\t%s (marfile): failed", module);
				stg1_error_message("Insmod %s (marfile) failed.", module);
			}
		}
	}
	fclose(f);
	umount(floppy_mount_location);
}
