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

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include "params.h"
#include "utils.h"
#include "automatic.h"
#include "log.h"
#include "bootsplash.h"

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
