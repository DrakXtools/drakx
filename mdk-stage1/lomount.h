/*
 * Guillaume Cottenceau (gc@mandriva.com)
 *
 * Copyright 2000 Mandriva
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#ifndef LOMOUNT_H
#define LOMOUNT_H

int lomount(const char *loopfile, const char *where, const char **loopdev, int compressed);
void del_loop(const char *loopdev);

#endif
