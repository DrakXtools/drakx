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

#ifndef _CONFIG_STAGE1_H_
#define _CONFIG_STAGE1_H_

#define _GNU_SOURCE 1


/* If we have more than that amount of memory (in Mbytes), we assume we can load the second stage as a ramdisk */
#define MEM_LIMIT_RAMDISK 68

/* If we have more than that amount of memory (in Mbytes), we assume we can load the rescue as a ramdisk */
#define MEM_LIMIT_RESCUE 40


#define RAMDISK_COMPRESSION_RATIO 1.95

#define LIVE_LOCATION    "/Mandrake/mdkinst/"
#define RAMDISK_LOCATION "/Mandrake/base/"
#define STAGE2_LOCATION  "/tmp/stage2"

#ifdef MANDRAKE_MOVE
#define DISTRIB_NAME "Mandrake Move"
#define IMAGE_LOCATION   "/sysroot/image_raw"
#define IMAGE_LOCATION_REAL "/sysroot/image"
#define SLASH_LOCATION   "/sysroot"
#define RAW_LOCATION_REL "/image_raw"
#define LIVE_LOCATION_REL "/image"
#define BOOT_LOCATION "/sysroot/image_boot"
#define ALWAYS_LOCATION "/sysroot/image_always"
#else
#define DISTRIB_NAME "Mandrake Linux"
#define IMAGE_LOCATION   "/tmp/image"
#define IMAGE_LOCATION_REAL "/tmp/image"
#endif


/* user-definable (in Makefile): DISABLE_NETWORK, DISABLE_DISK, DISABLE_CDROM, DISABLE_PCMCIA */


/* some factorizing for disabling more features */

#ifdef DISABLE_DISK
#ifdef DISABLE_CDROM
#define DISABLE_MEDIAS
#endif
#endif


#endif
