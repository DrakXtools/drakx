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
#include <unistd.h>
#include "insmod-busybox/insmod.h"
#include "stage1.h"
#include "log.h"
#include "mar/mar-extract-only.h"
#include "frontend.h"

#include "modules.h"

static struct module_deps_elem * modules_deps = NULL;

static char * archive_name = "/modules/modules.mar";
static struct mar_stream s = { 0, NULL, NULL };


static int ensure_archive_opened(void)
{
	/* don't consume too much memory */
	if (s.first_element == NULL) { 
		if (mar_open_file(archive_name, &s) != 0) {
			log_message("open marfile failed");
			return -1;
		}
	}
	return 0;
}

/* unarchive and insmod given module
 * WARNING: module must not contain the trailing ".o"
 */
static int insmod_archived_file(const char * mod_name, char * params)
{
	char module_name[50];
	char final_name[50] = "/tmp/";
	int i, rc;

	if (ensure_archive_opened() == -1)
		return -1;

	strncpy(module_name, mod_name, sizeof(module_name));
	strcat(module_name, ".o");
	i = mar_extract_file(&s, module_name, "/tmp/");
	if (i == 1) {
		log_message("file-not-found-in-archive %s", module_name);
		return -1;
	}
	if (i != 0)
		return -1;

	strcat(final_name, mod_name);
	strcat(final_name, ".o");

	rc = insmod_call(final_name, params);
	if (rc)
		log_message("\tfailed.");
	unlink(final_name); /* sucking no space left on device */
	return rc;
}



int load_modules_dependencies(void)
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
	if (read(fd, buf, s.st_size) != s.st_size) {
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


static int insmod_with_deps(const char * mod_name)
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
			insmod_with_deps(*one_dep);
			one_dep++;
		}
	}

	log_message("needs %s", mod_name);
	return insmod_archived_file(mod_name, NULL);
}


int my_insmod(const char * mod_name)
{
	int i;
	log_message("have to insmod %s", mod_name);

	if (IS_TESTING)
		return 0;

	i = insmod_with_deps(mod_name);
	if (i == 0)
		log_message("\tsucceeded %s.", mod_name);
	return i;

}

enum return_type insmod_with_params(char * mod)
{
	char * questions[] = { "Options", NULL };
	char ** answers;
	enum return_type results;

	results = ask_from_entries("Please enter the parameters to give to the kernel:", questions, &answers, 24);
	if (results != RETURN_OK)
		return results;

	if (insmod_archived_file(mod, answers[0])) {
		error_message("Insmod failed.");
		return RETURN_ERROR;
	}

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

	if (ensure_archive_opened() == -1)
		return -1;

	snprintf(msg, sizeof(msg), "Which driver should I try to gain %s access?", mytype);

	results = ask_from_list(msg, mar_list_contents(&s), &choice);

	if (results == RETURN_OK) {
		choice[strlen(choice)-2] = '\0'; /* remove trailing .o */
		if (my_insmod(choice)) {
			enum return_type results;
			unset_param(MODE_AUTOMATIC); /* we are in a fallback mode */

			results = ask_yes_no("Insmod failed.\nTry with parameters?");
			if (results == RETURN_OK)
				return insmod_with_params(choice);
			return RETURN_ERROR;
		} else
			return RETURN_OK;
	} else
		return results;
}
