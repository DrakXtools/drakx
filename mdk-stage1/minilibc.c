/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
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


#define MINILIBC_INTERNAL

#include "minilibc.h"

int atexit (void (*__func) (void) __attribute__ ((unused)))
{
	return 0;
}

void exit()
{
	_do_exit(0);
	for (;;); /* Shut up gcc */
}


char ** _environ = NULL;
int errno = 0;

void _init (int __status __attribute__ ((unused)))
{
}

void __libc_init_first (int __status __attribute__ ((unused)))
{
}

void __libc_csu_fini(int __status __attribute__ ((unused)))
{
}

void __libc_csu_init(int __status __attribute__ ((unused)))
{
}


int __libc_start_main (int (*main) (int, char **, char **), int argc,
		       char **argv, void (*init) (void) __attribute__ ((unused)), void (*fini) (void) __attribute__ ((unused)),
		       void (*rtld_fini) (void) __attribute__ ((unused)), void *stack_end __attribute__ ((unused)))
{
	exit ((*main) (argc, argv, NULL));
	/* never get here */
	return 0;
}

void _fini (int __status __attribute__ ((unused)))
{
}

inline int socket(int a, int b, int c)
{
	unsigned long args[] = { a, b, c };
	
	return socketcall(SYS_SOCKET, args);
}

inline int bind(int a, void * b, int c)
{
	unsigned long args[] = { a, (long) b, c };
	
	return socketcall(SYS_BIND, args);
}

inline int listen(int a, int b)
{
	unsigned long args[] = { a, b, 0 };
	
	return socketcall(SYS_LISTEN, args);
}

inline int accept(int a, void * addr, void * addr2)
{
	unsigned long args[] = { a, (long) addr, (long) addr2 };
	
	return socketcall(SYS_ACCEPT, args);
}


void sleep(int secs)
{
	struct timeval tv;
	
	tv.tv_sec = secs;
	tv.tv_usec = 0;
	
	select(0, NULL, NULL, NULL, &tv);
}


int strlen(const char * string)
{
	int i = 0;
	
	while (*string++) i++;
	
	return i;
}

char * strncpy(char * dst, const char * src, int len)
{
	char * chptr = dst;
	int i = 0;
	
	while (*src && i < len) *dst++ = *src++, i++;
	if (i < len) *dst = '\0';
	
	return chptr;
}

char * strcpy(char * dst, const char * src)
{
	char * chptr = dst;
	
	while (*src) *dst++ = *src++;
	*dst = '\0';
	
	return chptr;
}

void * memcpy(void * dst, const void * src, size_t count)
{
	char * a = dst;
	const char * b = src;
	
	while (count--)
		*a++ = *b++;
	
	return dst;
}


int strcmp(const char * a, const char * b)
{
	int i, j;  
	
	i = strlen(a); j = strlen(b);
	if (i < j)
		return -1;
	else if (j < i)
	return 1;

	while (*a && (*a == *b)) a++, b++;
	
	if (!*a) return 0;
	
	if (*a < *b)
		return -1;
	else
		return 1;
}

int strncmp(const char * a, const char * b, int len)
{
	char buf1[1000], buf2[1000];
	
	strncpy(buf1, a, len);
	strncpy(buf2, b, len);
	buf1[len] = '\0';
	buf2[len] = '\0';
	
	return strcmp(buf1, buf2);
}

char * strchr(char * str, int ch)
{
	char * chptr;
	
	chptr = str;
	while (*chptr)
	{
		if (*chptr == ch) return chptr;
		chptr++;
	}

	return NULL;
}


char * strstr(char *haystack, char *needle)
{
	char * tmp = haystack;
	while ((tmp = strchr(tmp, needle[0])) != NULL) {
		int i = 1;
		while (i < strlen(tmp) && i < strlen(needle) && tmp[i] == needle[i])
			i++;
		if (needle[i] == '\0')
			return tmp;
		tmp++;
	}
	return NULL;
}


/* Minimum printf which handles only characters, %d's and %s's */
void printf(char * fmt, ...)
{
	char buf[2048];
	char * start = buf;
	char * chptr = buf;
	va_list args;
	char * strarg;
	int numarg;

	strncpy(buf, fmt, sizeof(buf));
	va_start(args, fmt);

	while (start)
	{
		while (*chptr != '%' && *chptr) chptr++;
		
		if (*chptr == '%')
		{
			*chptr++ = '\0';
			print_str_init(1, start);
			
			switch (*chptr++)
			{
			case 's': 
				strarg = va_arg(args, char *);
				print_str_init(1, strarg);
				break;
				
			case 'd':
				numarg = va_arg(args, int);
				print_int_init(1, numarg);
				break;
			}
			
			start = chptr;
		}
		else
		{
			print_str_init(1, start);
			start = NULL;
		}
	}
}

