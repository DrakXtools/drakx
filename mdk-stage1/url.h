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
 * Portions from Erik Troan <ewt@redhat.com> and Matt Wilson <msw@redhat.com>
 *
 * Copyright 1999 Red Hat, Inc.
 *
 */

#ifndef _URL_H_
#define _URL_H_

int ftp_open_connection(char * host, char * name, char * password, char * proxy);
int ftp_get_filesize(int sock, char * remotename);
int ftp_start_download(int sock, char * remotename, int * size);
int ftp_end_data_command(int sock);
char *str_ftp_error(int error);

int http_download_file(char * hostname, char * remotename, int * size, char * proxyprotocol, char * proxyname, char * proxyport);


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
