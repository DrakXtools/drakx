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

#ifndef _DIRECTORY_H_
#define _DIRECTORY_H_

char * extract_list_directory(char * direct);
enum return_type try_with_directory(char *location_full, char *method_live, char *method_iso);

#endif
