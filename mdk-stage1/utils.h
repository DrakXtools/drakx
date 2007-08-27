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

#ifndef _UTILS_H_
#define _UTILS_H_

int charstar_to_int(const char * s);
off_t file_size(const char * path);
char * cat_file(const char * file, struct stat * s);
int line_counts(const char * buf);
int total_memory(void);
void * memdup(void *src, size_t size);
void add_to_env(char * name, char * value);
char ** list_directory(char * direct);
int string_array_length(char ** a);
int kernel_version(void);
char * asprintf_(const char *msg, ...);
int scall_(int retval, char * msg, char * file, int line);
#define scall(retval, msg) scall_(retval, msg, __FILE__, __LINE__)
void lowercase(char *s);

#define ptr_begins_static_str(pointer,static_str) (!strncmp(pointer,static_str,sizeof(static_str)-1))
#define streq(a,b) (!strcmp(a,b))

#endif
