/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * View the homepage: http://us.mandrakesoft.com/~gc/html/stage1.html
 *
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
 *  Portions from GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2000  Free Software Foundation, Inc.
 *
 *  Itself based on etherboot-4.6.4 by Martin Renters.
 *
 */

#ifndef _DHCP_H_
#define _DHCP_H_

#include "stage1.h"
#include "network.h"

enum return_type perform_dhcp(struct interface_info * intf);

extern char * dhcp_hostname;

#endif
