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
#include "stage1.h"
#include "log.h"

#include "tools.h"

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
