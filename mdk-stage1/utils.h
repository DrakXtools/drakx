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

#ifndef _UTILS_H_
#define _UTILS_H_

#include <sys/stat.h>

int charstar_to_int(const char * s);
off_t file_size(const char * path);
char * cat_file(const char * file, struct stat * s);
int line_counts(const char * buf);
int total_memory(void);
void * _memdup(const void *src, size_t size);
void add_to_env(const char * name, const char * value);
char ** list_directory(const char * direct);
int string_array_length(const char ** a);
int scall_(int retval, const char * msg, const char * file, int line);
char *my_dirname(const char *path);
#define scall(retval, msg) scall_(retval, msg, __FILE__, __LINE__)
void lowercase(char *s);

#define ptr_begins_static_str(pointer,static_str) (pointer != nullptr && !strncmp((const char*)pointer,static_str,sizeof(static_str)-1))
#define streq(a,b) (!strcmp(a,b))

#endif
