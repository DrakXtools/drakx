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
 * mar - The Mandrake Archiver
 *
 * An archiver that supports compression (through bzlib).
 *
 * Designed to be small so these bad designs are inside:
 *  . archive and compression are mixed together
 *  . create the mar file in-memory
 *  . does not free memory
 *
 */

#ifndef MAR_H
#define MAR_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>

#include <bzlib.h>

/*
 * Format of a mar file:
 *
 * ASCIIZ filename         \           |
 * int file_length         | repeated  | bzipped
 * int pointer_in_archive  /           |
 * char 0                              |
 * raw_files_data                      /
 *
 */

struct mar_element
{
	char * filename;             /* filename (ASCIIZ) of the element */
	int file_length;             /* length (in bytes) of the raw data of the element */
	int data_offset;             /* seek start of the raw data in the underlying mar stream */
	struct mar_element * next_element;  /* pointer to the next element in the mar stream; NULL if last */
};

struct mar_stream
{
	struct mar_element * first_element;  /* pointer to the first element inside the mar stream */
	BZFILE * mar_zfile;            /* associated zfile (opened) */
};

int z_errnum;

#define DEBUG_MAR(x)

#endif
