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

#ifndef _PCMCIA_CARDMGR_INTERFACE_H_
#define _PCMCIA_CARDMGR_INTERFACE_H_

char * pcmcia_probe(void);
void pcmcia_socket_startup(int socket_no);

#endif
