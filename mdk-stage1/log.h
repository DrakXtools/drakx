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
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */


#ifndef _LOG_H_
#define _LOG_H_

#include <stdarg.h>

void log_message(const char * s, ...) __attribute__ ((format (printf, 1, 2)));
void vlog_message(const char * s, va_list args);
void log_perror(const char *msg);
void open_log(void);
void close_log(void);

#endif
