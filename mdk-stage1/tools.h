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

#ifndef _TOOLS_H_
#define _TOOLS_H_

#include <stdlib.h>

void process_cmdline(void);
int get_param(int i);
void set_param(int i);
void unset_param(int i);
int charstar_to_int(char * s);
int total_memory(void);
int ramdisk_possible(void);
char * get_ramdisk_realname(void);
enum return_type load_ramdisk(void);
enum return_type load_ramdisk_fd(int ramdisk_fd, int size);
void * memdup(void *src, size_t size);
void add_to_env(char * name, char * value);
void handle_env(char ** env);
char ** grab_env(void);
char ** list_directory(char * direct);
int string_array_length(char ** a);

struct param_elem
{
	char * name;
	char * value;
};

#define ptr_begins_static_str(pointer,static_str) (!strncmp(pointer,static_str,sizeof(static_str)-1))
#define streq(a,b) (!strcmp(a,b))

#endif
