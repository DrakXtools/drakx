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

/*
 * mar - The Mandrake Archiver
 *
 * An archiver that supports compression (through zlib).
 *
 */

/*
 * Header for stage1 on-the-fly needs.
 */

#ifndef MAR_EXTRACT_ONLY_H
#define MAR_EXTRACT_ONLY_H

#include "mar.h"

int open_marfile(char *filename, struct mar_stream *s);
int extract_file(struct mar_stream *s, char *filename, char *dest_dir);
int calc_integrity(struct mar_stream *s);

#endif
