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
 * An archiver that supports compression (through zlib).
 *
 */

/*
 * Header for stage1 on-the-fly needs.
 */

#ifndef MAR_EXTRACT_ONLY_H
#define MAR_EXTRACT_ONLY_H

int mar_extract_file(char *mar_filename, char *filename_to_extract, char *dest_dir);
char ** mar_list_contents(char *mar_filename);

#endif
