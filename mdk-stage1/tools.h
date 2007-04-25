
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
#include "bootsplash.h"

void process_cmdline(void);
int get_param(int i);
void set_param(int i);
void unset_param(int i);
void unset_automatic(void);
int charstar_to_int(const char * s);
off_t file_size(const char * path);
int total_memory(void);
int image_has_stage2();
int ramdisk_possible(void);
enum return_type copy_file(char * from, char * to, void (*callback_func)(int overall));
enum return_type recursiveRemove(char *file);
enum return_type recursiveRemove_if_it_exists(char *file);
enum return_type preload_mount_compressed_fd(int compressed_fd, int image_size, char *image_name, char *location_mount);
enum return_type mount_compressed_image(char *compressed_image,  char *location_mount);
enum return_type mount_compressed_image_may_preload(char *image_name, char *location_mount, int preload);
enum return_type load_compressed_fd(int fd, int size);
enum return_type may_load_compressed_image(void);
void * memdup(void *src, size_t size);
void add_to_env(char * name, char * value);
char ** list_directory(char * direct);
int string_array_length(char ** a);
int kernel_version(void);
int try_mount(char * dev, char * location);
#ifndef DISABLE_DISK
int get_disks(char *** names, char *** models);
#endif
#ifndef DISABLE_CDROM
int get_cdroms(char *** names, char *** models);
#endif
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
