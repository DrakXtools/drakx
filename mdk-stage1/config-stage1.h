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

#ifndef _CONFIG_STAGE1_H_
#define _CONFIG_STAGE1_H_

#define _GNU_SOURCE 1


/* If we have more than that amount of memory (in Mbytes), we assume we can load the second stage as a ramdisk */
#define MEM_LIMIT_DRAKX 68

/* If we have more than that amount of memory (in Mbytes), we assume we can load the rescue as a ramdisk */
#define MEM_LIMIT_RESCUE 40


#define RAMDISK_COMPRESSION_RATIO 1.95

#define RAMDISK_LOCATION_REL "install/stage2/"
#define SLASH_LOCATION   "/sysroot"

#ifdef MANDRAKE_MOVE

#define MEM_LIMIT_MOVE 120
#define DISTRIB_NAME "Mandrakemove"

#define IMAGE_LOCATION_DIR SLASH_LOCATION "/"
#define IMAGE_LOCATION_REL "cdrom"
#define IMAGE_LOCATION IMAGE_LOCATION_DIR IMAGE_LOCATION_REL

#define CLP_LOCATION IMAGE_LOCATION

#define STAGE2_LOCATION_ROOTED "/image"
#define STAGE2_LOCATION SLASH_LOCATION STAGE2_LOCATION_ROOTED

#define BOOT_LOCATION SLASH_LOCATION "/image_boot"
#define ALWAYS_LOCATION SLASH_LOCATION "/image_always"
#define TOTEM_LOCATION SLASH_LOCATION "/image_totem"

#else

#define DISTRIB_NAME "Mandrakelinux"

#define LIVE_LOCATION_REL "install/stage2/live/"

/* the remote media is mounted in 
   - IMAGE_LOCATION_DIR "nfsimage", and IMAGE_LOCATION is a symlink image -> nfsimage/mdk/mirror/dir
   - IMAGE_LOCATION_DIR "hdimage",  and IMAGE_LOCATION is a symlink image -> hdimage/mdk/mirror/dir
   - directly in IMAGE_LOCATION (for cdroms and .iso images)
 */
#define IMAGE_LOCATION_DIR SLASH_LOCATION "/tmp/"
#define IMAGE_LOCATION_REL "image"
#define IMAGE_LOCATION IMAGE_LOCATION_DIR IMAGE_LOCATION_REL

#define STAGE2_LOCATION_ROOTED "/tmp/stage2"
#define STAGE2_LOCATION  SLASH_LOCATION STAGE2_LOCATION_ROOTED

#endif


/* user-definable (in Makefile): DISABLE_NETWORK, DISABLE_DISK, DISABLE_CDROM, DISABLE_PCMCIA */


/* some factorizing for disabling more features */

#ifdef DISABLE_DISK
#ifdef DISABLE_CDROM
#define DISABLE_MEDIAS
#endif
#endif

/* path to mirror list for net install */
#ifndef DISABLE_NETWORK
#define MIRRORLIST_HOST "www.linux-mandrake.com"
#define MIRRORLIST_PATH "/mirrorsfull.list"
#define MIRRORLIST_MAX_ITEMS 500
#define MIRRORLIST_MAX_MEDIA 10
#endif

#endif
