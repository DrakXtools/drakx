/*
 *	The PCI Library -- Portable interface to pread() and pwrite()
 *
 *	Copyright (c) 1997--2003 Martin Mares <mj@ucw.cz>
 *
 *	Can be freely distributed and used under the terms of the GNU GPL.
 */

/*
 *  We'd like to use pread/pwrite for configuration space accesses, but
 *  unfortunately it isn't simple at all since all libc's until glibc 2.1
 *  don't define it.
 */

#ifndef PCI_HAVE_DO_READ
#define do_read(d,f,b,l,p) pread(f,b,l,p)
#define do_write(d,f,b,l,p) pwrite(f,b,l,p)
#endif
