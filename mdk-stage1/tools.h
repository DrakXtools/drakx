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
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */

#ifndef _TOOLS_H_
#define _TOOLS_H_

#include <stdlib.h>

void process_cmdline(void);
int get_param(int i);
void set_param(int i);
void unset_param(int i);
int charstar_to_int(const char * s);
off_t file_size(const char * path);
int total_memory(void);
int image_has_stage2();
int ramdisk_possible(void);
enum return_type copy_file(char * from, char * to, void (*callback_func)(int overall));
enum return_type preload_mount_clp(int clp_fd, int clp_size, char *clp_name, char *location_mount);
enum return_type mount_clp(char *clp,  char *location_mount);
enum return_type mount_clp_may_preload(char *clp_name, char *location_mount, int preload);
#ifndef MANDRAKE_MOVE
enum return_type load_clp_fd(int fd, int size);
enum return_type may_load_clp(void);
#endif
void * memdup(void *src, size_t size);
void add_to_env(char * name, char * value);
char ** list_directory(char * direct);
int string_array_length(char ** a);
int kernel_version(void);
char * floppy_device(void);
char * asprintf_(const char *msg, ...);
int scall_(int retval, char * msg, char * file, int line);
#define scall(retval, msg) scall_(retval, msg, __FILE__, __LINE__)

struct param_elem
{
	char * name;
	char * value;
};

#define ptr_begins_static_str(pointer,static_str) (!strncmp(pointer,static_str,sizeof(static_str)-1))
#define streq(a,b) (!strcmp(a,b))

#endif
