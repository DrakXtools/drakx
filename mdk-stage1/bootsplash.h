/*
 * Pixel (pixel@mandrakesoft.com)
 *
 * Copyright 2004 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#ifndef _BOOTSPLASH_H_
#define _BOOTSPLASH_H_

#ifdef ENABLE_BOOTSPLASH
void exit_bootsplash(void);
void tell_bootsplash(char *cmd);
#else
#define exit_bootsplash()
#endif

#endif
