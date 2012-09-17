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
#include <libldetect.h>
#include <libkmod.h>

#include "log.h"
#include "utils.h"
#include "frontend.h"
#include "mount.h"

#include "modules.h"
#include "drvinst.h"

#define UEVENT_HELPER_FILE "/sys/kernel/uevent_helper"
#define UEVENT_HELPER_VALUE "/sbin/hotplug"

static const char kernel_module_extension[] = ".ko";
static char modules_directory[100];
static struct module_descr_elem * modules_descr = NULL;

static void print_mod_strerror(int err, struct kmod_module *mod, const char *filename)
{
    switch (err) {
	case -EEXIST:
	    fprintf(stderr, "could not insert '%s': Module already in kernel\n",
		    mod ? kmod_module_get_name(mod) : filename);
	    break;
	case -ENOENT:
	    fprintf(stderr, "could not insert '%s': Unknown symbol in module, "
		    "or file not found (see dmesg)\n",
		    mod ? kmod_module_get_name(mod) : filename);
	    break;
	case -ESRCH:
	    fprintf(stderr, "could not insert '%s': Module has wrong symbol version "
		    "(see dmesg)\n",
		    mod ? kmod_module_get_name(mod) : filename);
	    break;
	case -EINVAL:
	    fprintf(stderr, "could not insert '%s': Module has invalid parameters "
		    "(see dmesg)\n",
		    mod ? kmod_module_get_name(mod) : filename);
	    break;
	default:
		fprintf(stderr, "could not insert '%s': %s\n",
			mod ? kmod_module_get_name(mod) : filename,
			strerror(-err));
	    break;
    }
}

int insmod(const char *filename, const char *options)
{
	struct kmod_ctx *ctx;
	struct kmod_module *mod;
	int err = 0;
	const char *null_config = NULL;

	ctx = kmod_new(NULL, &null_config);
	if (!ctx) {
		fputs("Error: kmod_new() failed!\n", stderr);
		goto exit;
	}

	err = kmod_module_new_from_path(ctx, filename, &mod);
	if (err < 0) {
		print_mod_strerror(err, NULL, filename);
		goto exit;
	}

	err = kmod_module_insert_module(mod, 0, options);
	if (err < 0) {
		print_mod_strerror(err, NULL, filename);
	}
	kmod_module_unref(mod);

exit:
	kmod_unref(ctx);

	return err;
}

int modprobe(const char *alias, const char *extra_options) {
    struct kmod_ctx *ctx;
    struct kmod_list *l, *list = NULL;
    int err = 0, flags = 0;
    char dirname[PATH_MAX];
    struct utsname u;

    if (uname(&u) < 0) {
	perror("Error: uname() failed");
	return 0;
    }
    snprintf(dirname, sizeof(dirname), "/lib/modules/%s", u.release);

    ctx = kmod_new(dirname, NULL);
    if (!ctx) {
	fputs("Error: kmod_new() failed!\n", stderr);
	goto exit;
    }
    kmod_load_resources(ctx);

    err = kmod_module_new_from_lookup(ctx, alias, &list);
    if (err < 0)
	goto exit;

    // No module found...
    if (list == NULL)
	goto exit;

    // filter through blacklist
    struct kmod_list *filtered = NULL;
    err =  kmod_module_apply_filter(ctx, KMOD_FILTER_BLACKLIST, list, &filtered);
    kmod_module_unref_list(list);
    if (err < 0)
	goto exit;
    list = filtered;

    kmod_list_foreach(l, list) {
	struct kmod_module *mod = kmod_module_get_module(l);
	err = kmod_module_probe_insert_module(mod, flags,
		extra_options, NULL, NULL, NULL);

	if (err >= 0)
	    /* ignore flag return values such as a mod being blacklisted */
	    err = 0;
	else {
	    switch (err) {
		case -EEXIST:
		    fprintf(stderr, "could not insert '%s': Module already in kernel\n",
			    kmod_module_get_name(mod));
		    break;
		case -ENOENT:
		    fprintf(stderr, "could not insert '%s': Unknown symbol in module, "
			    "or unknown parameter (see dmesg)\n",
			    kmod_module_get_name(mod));
		    break;
		default:
		    fprintf(stderr, "could not insert '%s': %s\n",
			    kmod_module_get_name(mod),
			    strerror(-err));
		    break;
	    }
	}

	kmod_module_unref(mod);
	if (err < 0)
	    break;
    }

    kmod_module_unref_list(list);

exit:
    kmod_unref(ctx);

    return err;
}

static char *modinfo_do(struct kmod_ctx *ctx, const char *path)
{
	struct kmod_module *mod;
	struct kmod_list *l, *list = NULL;
	int err;
	char *ret = NULL;

	err = kmod_module_new_from_path(ctx, path, &mod);
	if (err < 0) {
		fprintf(stderr, "Module %s not found.\n", path);
		return ret;
	}

	err = kmod_module_get_info(mod, &list);
	if (err < 0) {
		fprintf(stderr, "could not get modinfo from '%s': %s\n",
			kmod_module_get_name(mod), strerror(-err));
		return ret;
	}

	kmod_list_foreach(l, list) {
		const char *key = kmod_module_info_get_key(l);
		const char *value = kmod_module_info_get_value(l);

		if (strcmp("description", key) != 0)
			continue;
		ret = strndup(value, 50);
		break;
	}

	kmod_module_info_free_list(list);
	kmod_module_unref(mod);

	return ret;
}

static char *filename2modname(char * filename) {
	char *modname, *p;

	modname = strdup(basename(filename));
	if (strstr(modname, kernel_module_extension)) {
		modname[strlen(modname)-(sizeof(kernel_module_extension)-1)] = '\0'; /* remove trailing .ko.gz */
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

static int load_modules_descriptions(void)
{
	int modnum;
	char ** dlist;
	struct kmod_ctx *ctx;
	char modpath[PATH_MAX];

	log_message("loading modules descriptions");

	dlist = list_directory(modules_directory);
	for (modnum = 0; dlist[modnum] && *dlist[modnum]; modnum++);

	modules_descr = calloc((modnum+1), sizeof(*modules_descr));

	ctx = kmod_new(modules_directory, NULL);
	if (!ctx) {
		fputs("Error: kmod_new() failed!\n", stderr);
		return 1;
	}
	kmod_load_resources(ctx);

	for (int i = 0; i < modnum; i++) {
		modules_descr[i].modname = filename2modname(dlist[i]);
		if (strstr(dlist[i], ".ko")) {
			sprintf(modpath, "%s/%s", modules_directory, dlist[i]);
			modules_descr[i].description = modinfo_do(ctx, modpath);
		}
	}
	free(dlist);
	kmod_unref(ctx);

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
	if (load_modules_descriptions()) {
		log_message("warning, error initing modules stuff");
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
	struct stat sb;
	char *path;
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


static enum insmod_return insmod_with_deps(const char * mod_name, char * options, int allow_modules_floppy)
{
	int err = modprobe(mod_name, options);
	switch (err){
	    case 0:
		return INSMOD_OK;
	    case -ENOENT:
		return INSMOD_FAILED_FILE_NOT_FOUND;
	    default:
		return INSMOD_FAILED;
	}
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

	if (module_already_present(mod_name))
		return INSMOD_OK;

	log_message("have to insmod %s", mod_name);

#ifndef DISABLE_NETWORK
	if (type == NETWORK_DEVICES)
		net_devices = get_net_devices();
#endif

	if (binary_name && !strcmp(binary_name, "dhcp-client"))
	{
		char *cmd = options ? asprintf_("/sbin/modprobe %s %s", mod_name, options) : 
			              asprintf_("/sbin/modprobe %s", mod_name);
		log_message("running %s", cmd);
		i = system(cmd);
	} else
    	    i = insmod_with_deps(mod_name, options, allow_modules_floppy);

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
		if (!strstr(*p_dlist, kernel_module_extension)) {
			p_dlist++;
			continue;
		}
		*p_modules = *p_dlist;
		*p_descrs = NULL;
		(*p_modules)[strlen(*p_modules)-(sizeof(kernel_module_extension)-1)] = '\0'; /* remove trailing .ko.gz */

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
