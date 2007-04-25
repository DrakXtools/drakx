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

#ifdef _GNU_SOURCE
#   undef _GNU_SOURCE
#endif
#define _GNU_SOURCE 1


/* If we have more than that amount of memory (in Mbytes), we assume we can load the second stage as a ramdisk */
#define MEM_LIMIT_DRAKX 68
/* If we have more than that amount of memory (in Mbytes), we preload the second stage as a ramdisk */
#define MEM_LIMIT_DRAKX_PRELOAD 100

/* If we have more than that amount of memory (in Mbytes), we assume we can load the rescue as a ramdisk */
#define MEM_LIMIT_RESCUE 40
/* If we have more than that amount of memory (in Mbytes), we preload the rescue as a ramdisk */
#define MEM_LIMIT_RESCUE_PRELOAD 100

#define KA_MAX_RETRY    5

#define LIVE_LOCATION_REL "install/stage2/live/"
#define COMPRESSED_LOCATION_REL  "install/stage2/"
#define COMPRESSED_STAGE2_NAME "mdkinst.sqfs"
#define COMPRESSED_RESCUE_NAME "rescue.sqfs"
#define COMPRESSED_NAME(prefix) (IS_RESCUE ? prefix COMPRESSED_RESCUE_NAME : prefix COMPRESSED_STAGE2_NAME)
#define COMPRESSED_FILE_REL(prefix) COMPRESSED_NAME(prefix COMPRESSED_LOCATION_REL)

/* the remote media is mounted in MEDIA_LOCATION, and
   - IMAGE_LOCATION is a symlink image -> image/mdk/mirror/dir
   - IMAGE_LOCATION is a symlink image -> loop/i586 and iso file is loopback mounted in LOOP_LOCATION
 */
#define MEDIA_LOCATION_REL "media"
#define MEDIA_LOCATION IMAGE_LOCATION_DIR MEDIA_LOCATION_REL

#define LOOP_LOCATION_REL "loop"
#define LOOP_LOCATION IMAGE_LOCATION_DIR LOOP_LOCATION_REL

#define IMAGE_LOCATION_REL "image"
#define IMAGE_LOCATION_DIR "/tmp/"
#define IMAGE_LOCATION IMAGE_LOCATION_DIR IMAGE_LOCATION_REL

#define COMPRESSED_LOCATION IMAGE_LOCATION "/" COMPRESSED_LOCATION_REL

/* - if we use a compressed image   : STAGE2_LOCATION is a the mount point
   - if we use the live: STAGE2_LOCATION is a relative symlink to image/install/stage2/live 
*/
#define STAGE2_LOCATION "/tmp/stage2"


/* user-definable (in Makefile): DISABLE_NETWORK, DISABLE_DISK, DISABLE_CDROM, DISABLE_PCMCIA */


/* some factorizing for disabling more features */

#ifdef DISABLE_DISK
#ifdef DISABLE_CDROM
#define DISABLE_MEDIAS
#endif
#endif

/* path to mirror list for net install */
#ifndef DISABLE_NETWORK
#define MIRRORLIST_HOST "www.mandrivalinux.com"
#define MIRRORLIST_PATH "/mirrorsfull.list"
#endif

#endif
