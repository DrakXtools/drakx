/* Copyright 1999-2003 Red Hat, Inc.
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#ifndef _KUDZU_H_
#define _KUDZU_H_

/* kudzu: it grows on you */

/* level of debugging output */
//#undef DEBUG_LEVEL
#define DEBUG_LEVEL 2

#ifdef DEBUG_LEVEL
#define DEBUG(s...) fprintf(stderr,s)
#else
#define DEBUG(s...) ;
#endif

#endif
