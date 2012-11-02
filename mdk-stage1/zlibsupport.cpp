/* Support for compressed modules.  Willy Tarreau <willy@meta-x.org>
 * did the support for modutils, Andrey Borzenkov <arvidjaar@mail.ru>
 * ported it to module-init-tools, and I said it was too ugly to live
 * and rewrote it 8).
 *
 * (C) 2003 Rusty Russell, IBM Corporation.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdio.h>
#include <errno.h>

#include "zlibsupport.h"

#define CONFIG_USE_LIBLZMA
#ifdef CONFIG_USE_ZLIB
#include <zlib.h>
#ifdef CONFIG_USE_LIBLZMA
#include <lzma.h>

typedef struct lzma_file {
	uint8_t buf[1<<14];
	lzma_stream strm;
	FILE *fp;
	lzma_bool eof;
} lzma_FILE;
#else
typedef unsigned char lzma_bool;
typedef	int lzma_ret;
#define	LZMA_OK 0
#endif

typedef enum xFile_e {
	XF_NONE,
	XF_GZIP,
	XF_XZ,
	XF_FAIL
} xFile_t;

typedef struct xFile_s {
	xFile_t type;
	lzma_bool eof;
	union {
		gzFile gz;
#ifdef CONFIG_USE_LIBLZMA
		lzma_FILE *xz;
#endif
	} f;
	FILE *fp;
} xFile;

#ifdef CONFIG_USE_LIBLZMA
static lzma_FILE *lzma_open(lzma_ret *lzma_error, FILE *fp)
{
	lzma_ret *ret = lzma_error;
	lzma_FILE *lzma_file;
	lzma_stream tmp = LZMA_STREAM_INIT;

	lzma_file = calloc(1, sizeof(*lzma_file));

	lzma_file->fp = fp;
	lzma_file->eof = 0;
	lzma_file->strm = tmp;

	*ret = lzma_auto_decoder(&lzma_file->strm, -1, 0);

	if (*ret != LZMA_OK) {
		(void) fclose(lzma_file->fp);
		free(lzma_file);
		return NULL;
	}
	return lzma_file;
}

static ssize_t lzma_read(lzma_ret *lzma_error, lzma_FILE *lzma_file, void *buf, size_t len)
{
	lzma_ret *ret = lzma_error;
	lzma_bool eof = 0;

	if (!lzma_file)
		return -1;
	if (lzma_file->eof)
		return 0;

	lzma_file->strm.next_out = buf;
	lzma_file->strm.avail_out = len;
	for (;;) {
		if (!lzma_file->strm.avail_in) {
			lzma_file->strm.next_in = (uint8_t *)lzma_file->buf;
			lzma_file->strm.avail_in = fread(lzma_file->buf, 1, sizeof(lzma_file->buf), lzma_file->fp);
			if (!lzma_file->strm.avail_in)
				eof = 1;
		}
		*ret = lzma_code(&lzma_file->strm, LZMA_RUN);
		if (*ret == LZMA_STREAM_END) {
			lzma_file->eof = 1;
			return len - lzma_file->strm.avail_out;
		}
		if (*ret != LZMA_OK)
			return -1;
		if (!lzma_file->strm.avail_out)
			return len;
		if (eof)
			return -1;
	}
}
#endif

static xFile xOpen(int fd, const char *filename) {
	xFile xF = {XF_FAIL, 0, {NULL}, NULL};
	lzma_ret ret = LZMA_OK;
	unsigned char buf[8];

	if (fd == -1 && filename != NULL)
		if ((fd = open(filename, O_RDONLY)) < 0)
			return xF;
	if (read(fd, buf, sizeof(buf)) < 0)
		return xF;
	lseek(fd, 0, SEEK_SET);
	if (filename != NULL) {
		close(fd);
		fd = -1;
	}
	if (buf[0] == 0xFD && buf[1] == '7' && buf[2] == 'z' &&
			buf[3] == 'X' && buf[4] == 'Z' && buf[5] == 0x00)
		xF.type = XF_XZ;
	else if (buf[0] == 0x1F && buf[1] == 0x8B)
		xF.type = XF_GZIP;
	else
		xF.type = XF_NONE;

	switch(xF.type) {
		case XF_GZIP:
			xF.f.gz = (fd == -1 && filename != NULL) ? gzopen(filename, "rb") : gzdopen(fd, "rb");
			if(xF.f.gz == NULL)
				xF.type = XF_FAIL;
			break;
		case XF_NONE:
			xF.fp = (fd == -1 && filename != NULL) ? fopen(filename, "rb") : fdopen(fd, "rb");
			break;
#ifdef CONFIG_USE_LIBLZMA
		case XF_XZ:
			xF.fp = (fd == -1 && filename != NULL) ? fopen(filename, "rb") : fdopen(fd, "rb");
			if(xF.fp == NULL)
				xF.type = XF_FAIL;
			if(xF.type == XF_NONE || xF.type == XF_FAIL) break;
			xF.f.xz = lzma_open(&ret, xF.fp);
			if(ret != LZMA_OK)
				xF.type = XF_FAIL;
			break;
#endif
		default:
			break;
	}

	return xF;
}

static int xClose(xFile *xF) {
	int ret = -1;
	switch(xF->type) {
		case XF_GZIP:
			ret = gzclose(xF->f.gz);
			break;
#ifdef CONFIG_USE_LIBLZMA
		case XF_XZ:
			lzma_end(&xF->f.xz->strm);
			free(xF->f.xz);
#endif
		case XF_NONE:
			ret = fclose(xF->fp);
			break;
		default:
			break;
	}
	return ret;
}

static ssize_t xRead(xFile *xF, lzma_ret *ret, void *buf, size_t len) {
	ssize_t sz;
	switch(xF->type) {
		case XF_GZIP:
			sz = gzread(xF->f.gz, buf, len);
			xF->eof = gzeof(xF->f.gz);
			break;
#ifdef CONFIG_USE_LIBLZMA
		case XF_XZ:
			sz = lzma_read(ret, xF->f.xz, buf, len);
			xF->eof = xF->f.xz->eof;
			break;
#endif
		case XF_NONE:
			sz = fread(buf, 1, len, xF->fp);
			xF->eof = feof(xF->fp);
			break;
		default:
			sz = -1;
			break;
	}
	return sz;
}

void *grab_contents(xFile *xF, unsigned long *size)
{
	unsigned int max = 16384;
	void *buffer = calloc(1, max);
	lzma_ret ret;

	if (!buffer)
		return NULL;

	*size = 0;
	while ((ret = xRead(xF, &ret, buffer + *size, max - *size)) > 0) {
		*size += ret;
		if (*size == max) {
			void *p;

			p = realloc(buffer, max *= 2);
			if (!p)
				goto out_err;

			buffer = p;
		}
	}
	if (ret < 0)
		goto out_err;

	return buffer;

out_err:
	free(buffer);
	return NULL;
}


/* gzopen handles uncompressed files transparently. */
void *grab_file(const char *filename, unsigned long *size)
{
	xFile xF;
	void *buffer;

	xF = xOpen(-1, filename);
	if (xF.type == XF_FAIL)
		return NULL;
	buffer = grab_contents(&xF, size);
	xClose(&xF);
	return buffer;
}

void release_file(void *data, unsigned long size)
{
	free(data);
}
#else /* ... !CONFIG_USE_ZLIB */

void *grab_fd(int fd, unsigned long *size)
{
	struct stat st;
	void *map;
	int ret;

	ret = fstat(fd, &st);
	if (ret < 0)
		return NULL;
	*size = st.st_size;
	map = mmap(0, *size, PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (map == MAP_FAILED)
		map = NULL;
	return map;
}

void *grab_file(const char *filename, unsigned long *size)
{
	int fd;
	void *map;

	fd = open(filename, O_RDONLY, 0);
	if (fd < 0)
		return NULL;
	map = grab_fd(fd, size);
	close(fd);
	return map;
}

void release_file(void *data, unsigned long size)
{
	munmap(data, size);
}
#endif
