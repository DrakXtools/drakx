/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 * Olivier Blin (oblin@mandrakesoft.com)
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

#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <string.h>
#include "stage1.h"
#include "frontend.h"
#include "log.h"
#include "lomount.h"

char * extract_list_directory(char * direct)
{
	char ** full = list_directory(direct);
	char tmp[2000] = "";
	int i;
	for (i=0; i<5 ; i++) {
		if (!full || !*full)
			break;
		strcat(tmp, *full);
		strcat(tmp, "\n");
		full++;
	}
	return strdup(tmp);
}

enum return_type try_with_directory(char *directory, char *method_live, char *method_iso) {
	char location_full[500];
        char * loopdev = NULL;
	struct stat statbuf;
	enum return_type results;

	unlink(IMAGE_LOCATION);
	strcpy(location_full, directory);

#ifndef MANDRAKE_MOVE
	if (!stat(directory, &statbuf) && S_ISDIR(statbuf.st_mode)) {
		char **file;
		char *stage2_isos[100] = { "Use directory as a mirror tree", "-----" };
		int stage2_iso_number = 2;

		log_message("\"%s\" exists and is a directory, looking for iso files", directory);

		for (file = list_directory(directory); *file; file++) {
			char isofile[500], install_location[600];

			if (strstr(*file, ".iso") != *file + strlen(*file) - 4)
				/* file doesn't end in .iso, skipping */
				continue;
			
			strcpy(isofile, directory);
			strcat(isofile, "/");
			strcat(isofile, *file);

			if (lomount(isofile, IMAGE_LOCATION, &loopdev, 0)) {
				log_message("unable to mount iso file \"%s\", skipping", isofile);
				continue;
			}

			strcpy(install_location, IMAGE_LOCATION);

			if (IS_SPECIAL_STAGE2 || ramdisk_possible())
				strcat(install_location, get_ramdisk_realname()); /* RAMDISK install */
			else
				strcat(install_location, LIVE_LOCATION); /* LIVE install */

			if (access(install_location, R_OK)) {
				log_message("ISO image \"%s\" doesn't contain stage2 installer", isofile);
			} else {
				log_message("stage2 installer found in ISO image \"%s\"", isofile);
				stage2_isos[stage2_iso_number++] = strdup(*file);
			}

 			umount(IMAGE_LOCATION);
			del_loop(loopdev);
		}

		stage2_isos[stage2_iso_number] = NULL;

		if (stage2_iso_number > 2) {
			do {
				results = ask_from_list("Please choose the ISO image to be used to install the "
							DISTRIB_NAME " Distribution.",
							stage2_isos, file);
				if (results == RETURN_BACK) {
					return RETURN_BACK;
				} else if (results == RETURN_OK) {
					if (!strcmp(*file, stage2_isos[0])) {
						/* use directory as a mirror tree */
						continue;
					} else if (!strcmp(*file, stage2_isos[1])) {
						/* the separator has been selected */
						results = RETURN_ERROR;
						continue;
					} else {
						/* use selected ISO image */
						strcat(location_full, "/");
						strcat(location_full, *file);
						log_message("installer will use ISO image \"%s\"", location_full);
					}
				}
			} while (results == RETURN_ERROR);
		} else {
			log_message("no ISO image found in \"%s\" directory", location_full);
		}
	}
#endif

	if (!stat(location_full, &statbuf) && !S_ISDIR(statbuf.st_mode)) {
		log_message("%s exists and is not a directory, assuming this is an ISO image", location_full);
		if (lomount(location_full, IMAGE_LOCATION, &loopdev, 0)) {
			stg1_error_message("Could not mount file %s as an ISO image of the " DISTRIB_NAME " Distribution.", location_full);
			return RETURN_ERROR;
		}
		add_to_env("ISOPATH", location_full);
		add_to_env("METHOD", method_iso);
	} else {
		log_message("assuming %s is a mirror tree", location_full);
		symlink(location_full, IMAGE_LOCATION);
		add_to_env("METHOD", method_live);
	}
#ifndef MANDRAKE_MOVE
	if (IS_SPECIAL_STAGE2 || ramdisk_possible()) {
		/* RAMDISK install */
		if (access(IMAGE_LOCATION RAMDISK_LOCATION, R_OK)) {
			stg1_error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				      "(I need the subdirectory " RAMDISK_LOCATION ")\n"
				      "Here's a short extract of the files in the directory:\n"
				      "%s", extract_list_directory(IMAGE_LOCATION));
			del_loop(loopdev);
			return RETURN_ERROR;
		}
		if (load_ramdisk() != RETURN_OK) {
			stg1_error_message("Could not load program into memory.");
			del_loop(loopdev);
			return RETURN_ERROR;
		}
	} else {
#endif
		/* LIVE install */
#ifdef MANDRAKE_MOVE
		if (access(IMAGE_LOCATION "/live_tree/etc/fstab", R_OK) && access(IMAGE_LOCATION "/live_tree.clp", R_OK)) {
#else
		if (access(IMAGE_LOCATION LIVE_LOCATION, R_OK)) {
#endif
			stg1_error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				      "(I need the subdirectory " LIVE_LOCATION ")\n"
				      "Here's a short extract of the files in the directory:\n"
				      "%s", extract_list_directory(IMAGE_LOCATION));
			del_loop(loopdev);
			return RETURN_ERROR;
		}
#ifndef MANDRAKE_MOVE
		char p;
		if (readlink(IMAGE_LOCATION LIVE_LOCATION "/usr/bin/runinstall2", &p, 1) != 1) {
			stg1_error_message("The " DISTRIB_NAME " Distribution seems to be copied on a Windows partition. "
				      "You need more memory to perform an installation from a Windows partition. "
				      "Another solution if to copy the " DISTRIB_NAME " Distribution on a Linux partition.");
			del_loop(loopdev);
			return RETURN_ERROR;
		}
		log_message("found the " DISTRIB_NAME " Installation, good news!");
	}
#endif

	if (IS_RESCUE)
                del_loop(loopdev);

	return RETURN_OK;
}
