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

/*
 * Portions from Erik Troan <ewt@redhat.com> and Matt Wilson <msw@redhat.com>
 *
 * Copyright 1999 Red Hat, Inc.
 *
 */

#ifndef _URL_H_
#define _URL_H_

int ftp_open_connection(const char * host, const char * name, const char * password, const char * proxy);
int ftp_get_filesize(int sock, const char * remotename);
int ftp_start_download(int sock, const char * remotename, int * size);
int ftp_end_data_command(int sock);
const char *str_ftp_error(int error);

int http_download_file(const char * hostname, const char * remotename, int * size, const char * proxyprotocol, const char * proxyname, const char * proxyport);


#define FTPERR_BAD_SERVER_RESPONSE   -1
#define FTPERR_SERVER_IO_ERROR       -2
#define FTPERR_SERVER_TIMEOUT        -3
#define FTPERR_BAD_HOST_ADDR         -4
#define FTPERR_BAD_HOSTNAME          -5
#define FTPERR_FAILED_CONNECT        -6
#define FTPERR_FILE_IO_ERROR         -7
#define FTPERR_PASSIVE_ERROR         -8
#define FTPERR_FAILED_DATA_CONNECT   -9
#define FTPERR_FILE_NOT_FOUND        -10
#define FTPERR_UNKNOWN               -100

#endif
