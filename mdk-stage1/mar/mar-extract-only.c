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
 * mar - The Mandrake Archiver
 *
 * An archiver that supports compression (through zlib).
 *
 */

/*
 * This code should suffice for stage1 on-the-fly uncompression of kernel modules.
 * (and it DOES perform tests and return values, blaaaah..)
 */

#include "mar.h"


void
gzerr(gzFile f) /* decrease code size */
{
	fprintf(stderr, gzerror(f, &gz_errnum));
}

int
calc_integrity(mar_stream *s)
{
	char buf[4096];
	int current_crc = 0;
	if (gzseek(s->mar_gzfile, sizeof(int), SEEK_SET) != sizeof(int))
	{
		gzerr(s->mar_gzfile);
		return -1;
	}
	while (!gzeof(s->mar_gzfile))
	{
		int bytes = gzread(s->mar_gzfile, buf, sizeof(buf));
		if (bytes == -1)
		{
			gzerr(s->mar_gzfile);
			return -1;
		}
		DEBUG_MAR(printf("D: mar::calc_integrity more-bytes-to-handle-for-crc %d\n", bytes););
		while (bytes > 0)
		{
			bytes--;
			current_crc += buf[bytes];
		}
	}
	DEBUG_MAR(printf("D: mar::calc_integrity computed-crc %d\n", current_crc););
	return current_crc;
}


int
extract_file(mar_stream *s, char *filename, char *dest_dir)
{
	mar_element * elem = s->first_element;
	while (elem)
	{
		if (strcmp(elem->filename, filename) == 0)
		{
			char *buf;
			char *dest_file;
			int fd;
			dest_file = (char *) malloc(strlen(dest_dir) + strlen(filename) + 1);
			strcpy(dest_file, dest_dir);
			strcat(dest_file, filename);
			fd = creat(dest_file, 00660);
			if (fd == -1)
			{
				perror(dest_file);
				return -1;
			}
			buf = (char *) malloc(elem->file_length);
			if (!buf)
			{
				perror(dest_file);
				return -1;
			}
			if (gzseek(s->mar_gzfile, elem->data_offset, SEEK_SET) != elem->data_offset)
			{
				gzerr(s->mar_gzfile);
				return -1;
			}
			if (gzread(s->mar_gzfile, buf, elem->file_length) != elem->file_length)
			{
				gzerr(s->mar_gzfile);
				return -1;
			}
			if (write(fd, buf, elem->file_length) != elem->file_length)
			{
				perror(dest_file);
				return -1;
			}
			close(fd); /* do not check return value for code size */
			return 0;
		}
		elem = elem->next_element;
	}
	return 1; /* 1 for file_not_found_in_archive */
}


mar_stream *
open_marfile(char *filename)
{
	int end_filetable = 0;
	mar_stream * s = (mar_stream *) malloc(sizeof(mar_stream));
	mar_element * previous_element = NULL;

	/* mar_gzfile */
	s->mar_gzfile = gzopen(filename, "rb");
	if (!s->mar_gzfile)
	{
		perror(filename);
		return NULL;
	}

	/* crc32 */
	if (gzread(s->mar_gzfile, &(s->crc32), sizeof(int)) != sizeof(int))
	{
		gzerr(s->mar_gzfile);
		return NULL;
	}

	DEBUG_MAR(printf("D: mar::open_marfile crc-in-marfile %d\n", s->crc32););
	/* verify integrity */
	if (s->crc32 != calc_integrity(s))
	{
		fprintf(stderr, "E: mar::open_marfile CRC check failed\n");
		return NULL;
	}
	else
		if (gzseek(s->mar_gzfile, sizeof(int), SEEK_SET) != sizeof(int))
		{
			gzerr(s->mar_gzfile);
			return NULL;
		}

	while (end_filetable == 0)
	{
		char buf[512];
		int ptr = 0;
		/* read filename */
		do
		{
			if (gzread(s->mar_gzfile, &(buf[ptr]), sizeof(char)) != sizeof(char))
			{
				gzerr(s->mar_gzfile);
				return NULL;
			}
			ptr++;
		} while ((buf[ptr-1] != 0) && (ptr < 512));
		/* ptr == 1 when we arrive on the "char 0" of the end of the filetable */
		if (ptr > 1)
		{
			mar_element * e = (mar_element *) malloc(sizeof(mar_element));
			e->filename = strdup(buf);
			DEBUG_MAR(printf("D: mar::open_marfile processing-file %s\n", e->filename););
			/* read file_length */
			if (gzread(s->mar_gzfile, &(e->file_length), sizeof(int)) != sizeof(int))
			{
				gzerr(s->mar_gzfile);
				return NULL;
			}
			/* read data_offset */
			if (gzread(s->mar_gzfile, &(e->data_offset), sizeof(int)) != sizeof(int))
			{
				gzerr(s->mar_gzfile);
				return NULL;
			}
			/* write down chaining */
			if (previous_element)
				previous_element->next_element = e;
			else
				s->first_element = e;
			previous_element = e;
		}
		else
			end_filetable = 1;

	}
	/* chaining for last element */
	previous_element->next_element = NULL;

	return s;
}

