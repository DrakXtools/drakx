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
#define SLASH_LOCATION   "/sysroot"
#define STAGE2_LOCATION  SLASH_LOCATION "/tmp/stage2"

#ifdef MANDRAKE_MOVE
#define MEM_LIMIT_MOVE 120
#define DISTRIB_NAME "Mandrakemove"
#define IMAGE_LOCATION_DIR SLASH_LOCATION
#define IMAGE_LOCATION IMAGE_LOCATION_DIR "/cdrom"
#define IMAGE_LOCATION_REAL SLASH_LOCATION "/image"
#define RAW_LOCATION_REL "/cdrom"
#define STAGE2_LOCATION_REL "/image"
#define BOOT_LOCATION SLASH_LOCATION "/image_boot"
#define ALWAYS_LOCATION SLASH_LOCATION "/image_always"
#define TOTEM_LOCATION SLASH_LOCATION "/image_totem"

#else

#define DISTRIB_NAME "Mandrakelinux"
#define IMAGE_LOCATION_DIR SLASH_LOCATION "/tmp/"
#define IMAGE_LOCATION IMAGE_LOCATION_DIR "image"
#define IMAGE_LOCATION_REAL "/tmp/image"
#define STAGE2_LOCATION_REL "/tmp/stage2"
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
