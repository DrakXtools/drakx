/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 * Olivier Blin (oblin@mandrakesoft.com)
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

#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <string.h>
#include <libgen.h>
#include "stage1.h"
#include "frontend.h"
#include "log.h"
#include "tools.h"
#include "utils.h"
#include "lomount.h"

char * extract_list_directory(char * direct)
{
	char ** full = list_directory(direct);
	char tmp[20000] = "";
	int i;
	for (i=0; i<50 ; i++) {
		if (!full || !*full)
			break;
		strcat(tmp, *full);
		strcat(tmp, "\n");
		full++;
	}
	return strdup(tmp);
}

static void choose_iso_in_directory(char *directory, char *location_full) 
{
	char **file;
	char *stage2_isos[100] = { "Use directory as a mirror tree", "-----" };
	int stage2_iso_number = 2;

	log_message("\"%s\" exists and is a directory, looking for iso files", directory);

	for (file = list_directory(directory); *file; file++) {
		char isofile[500];
		char * loopdev = NULL;

		if (strstr(*file, ".iso") != *file + strlen(*file) - 4)
			/* file doesn't end in .iso, skipping */
			continue;
			
		strcpy(isofile, directory);
		strcat(isofile, "/");
		strcat(isofile, *file);

		if (lomount(isofile, LOOP_LOCATION, &loopdev, 0)) {
			log_message("unable to mount iso file \"%s\", skipping", isofile);
			continue;
		}
		symlink(LOOP_LOCATION_REL "/" ARCH, IMAGE_LOCATION);

		if (image_has_stage2()) {
			log_message("stage2 installer found in ISO image \"%s\"", isofile);
			stage2_isos[stage2_iso_number++] = strdup(*file);
		} else {
			log_message("ISO image \"%s\" doesn't contain stage2 installer", isofile);
		}

		unlink(IMAGE_LOCATION);
		umount(LOOP_LOCATION);
		del_loop(loopdev);
	}

	stage2_isos[stage2_iso_number] = NULL;

	if (stage2_iso_number > 2) {
		enum return_type results;
		do {
			results = ask_from_list("Please choose the ISO image to be used to install the "
						DISTRIB_NAME " Distribution.",
						stage2_isos, file);
			if (results == RETURN_BACK) {
				return;
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


enum return_type try_with_directory(char *directory, char *method_live, char *method_iso) {
	char location_full[500];
        char * loopdev = NULL;
	struct stat statbuf;
	enum return_type ret = RETURN_OK;

	unlink(IMAGE_LOCATION);
	strcpy(location_full, directory);

	if (!stat(directory, &statbuf) && S_ISDIR(statbuf.st_mode)) {
		choose_iso_in_directory(directory, location_full);
	}

	loopdev = NULL;
	if (!stat(location_full, &statbuf) && !S_ISDIR(statbuf.st_mode)) {
		log_message("%s exists and is not a directory, assuming this is an ISO image", location_full);
		if (lomount(location_full, LOOP_LOCATION, &loopdev, 0)) {
			stg1_error_message("Could not mount file %s as an ISO image of the " DISTRIB_NAME " Distribution.", location_full);
			return RETURN_ERROR;
		}
		symlink(LOOP_LOCATION_REL "/" ARCH, IMAGE_LOCATION);
		add_to_env("ISOPATH", location_full);
		add_to_env("METHOD", method_iso);
	} else {
		create_IMAGE_LOCATION(location_full);
		add_to_env("METHOD", method_live);
	}

	if (access(IMAGE_LOCATION "/" COMPRESSED_LOCATION_REL, R_OK)) {
		stg1_error_message("I can't find the " DISTRIB_NAME " Distribution in the specified directory. "
				   "(I need the subdirectory " COMPRESSED_LOCATION_REL ")\n"
				   "Here's a short extract of the files in the directory:\n"
				   "%s", extract_list_directory(IMAGE_LOCATION));
		ret = RETURN_BACK;
	} else if (may_load_compressed_image() != RETURN_OK) {
		stg1_error_message("Could not load program into memory.");
		ret = RETURN_ERROR;
	}

	if (ret == RETURN_OK)
		log_message("found the " DISTRIB_NAME " Installation, good news!");

	if (!KEEP_MOUNTED || ret != RETURN_OK) {
		/* in rescue mode, we don't need the media anymore */
		umount(LOOP_LOCATION);
		del_loop(loopdev);
	}	

	return ret;
}
