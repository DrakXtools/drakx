/*
 * Olivier Blin (oblin@mandriva.com)
 *
 * Copyright 2005 Mandriva
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#ifndef _WIRELESS_H_
#define _WIRELESS_H_

#include "frontend.h"

int wireless_open_socket();
int wireless_close_socket(int socket);
int wireless_is_aware(int socket, const char *ifname);
enum return_type configure_wireless(const char *ifname);

#endif
