
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

int image_has_stage2();
enum return_type create_IMAGE_LOCATION(char *location_full);
int ramdisk_possible(void);
enum return_type copy_file(char * from, char * to, void (*callback_func)(int overall));
enum return_type recursiveRemove(char *file);
enum return_type recursiveRemove_if_it_exists(char *file);
enum return_type preload_mount_compressed_fd(int compressed_fd, int image_size, char *image_name, char *location_mount);
enum return_type mount_compressed_image(char *compressed_image,  char *location_mount);
enum return_type mount_compressed_image_may_preload(char *image_name, char *location_mount, int preload);
enum return_type load_compressed_fd(int fd, int size);
enum return_type may_load_compressed_image(void);
int try_mount(char * dev, char * location);
#ifndef DISABLE_DISK
int get_disks(char *** names, char *** models);
#endif
#ifndef DISABLE_CDROM
int get_cdroms(char *** names, char *** models);
#endif
char * floppy_device(void);

#endif
