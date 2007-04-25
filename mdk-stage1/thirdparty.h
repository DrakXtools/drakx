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

#ifndef _THIRDPARTY_H_
#define _THIRDPARTY_H_

#define THIRDPARTY_DIRECTORY "/install/thirdparty"

/* load third party modules present on install media
 * use to_load and to_detect files in /install/thirdparty
 * do not prompt user
 */
void thirdparty_load_media_modules(void);

/* load modules if to_load or to_detect files are present
 * prompt user if no to_load file is present
 */
void thirdparty_load_modules(void);

/* destroy all data structures related to the thirdparty module */
void thirdparty_destroy(void);

#endif
