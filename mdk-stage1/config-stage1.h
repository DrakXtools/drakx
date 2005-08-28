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

#define SLASH_LOCATION   "/sysroot"

#ifdef MANDRAKE_MOVE

#define MEM_LIMIT_MOVE 120

#undef DISTRIB_NAME
#define DISTRIB_NAME "Mandrakemove"
#undef DISTRIB_DESCR
#define DISTRIB_DESCR DISTRIB_NAME

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

#define LIVE_LOCATION_REL "install/stage2/live/"
#define CLP_LOCATION_REL  "install/stage2/"
#define CLP_STAGE2_NAME "mdkinst.clp"
#define CLP_RESCUE_NAME "rescue.clp"
#define CLP_NAME(prefix) (IS_RESCUE ? prefix CLP_RESCUE_NAME : prefix CLP_STAGE2_NAME)
#define CLP_FILE_REL(prefix) CLP_NAME(prefix CLP_LOCATION_REL)

/* the remote media is mounted in 
   - IMAGE_LOCATION_DIR "nfsimage", and IMAGE_LOCATION is a symlink image -> nfsimage/mdk/mirror/dir
   - IMAGE_LOCATION_DIR "hdimage",  and IMAGE_LOCATION is a symlink image -> hdimage/mdk/mirror/dir
   - directly in IMAGE_LOCATION (for cdroms and .iso images)
 */
#define IMAGE_LOCATION_DIR SLASH_LOCATION "/tmp/"
#define IMAGE_LOCATION_REL "image"
#define IMAGE_LOCATION IMAGE_LOCATION_DIR IMAGE_LOCATION_REL

#define CLP_LOCATION IMAGE_LOCATION "/" CLP_LOCATION_REL

/* - if we use a clp   : STAGE2_LOCATION is a the mount point
   - if we use the live: STAGE2_LOCATION is a relative symlink to IMAGE_LOCATION_REL/install/stage2/live 
*/
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
#define MIRRORLIST_HOST "www.mandrivalinux.com"
#define MIRRORLIST_PATH "/mirrorsfull.list"
#endif

#endif
