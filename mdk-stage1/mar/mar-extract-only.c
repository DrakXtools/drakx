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

#ifdef _STANDALONE_
void
gzerr(gzFile f) /* decrease code size */
{
	fprintf(stderr, gzerror(f, &gz_errnum));
}
void
log_perror(char *msg)
{
	perror(msg);
}
void
log_message(char *msg)
{
	fprintf(stderr, msg);
}
#else /* _STANDALONE_ */
#include "../log.h"
void
gzerr(gzFile f) /* decrease code size */
{
	log_message(gzerror(f, &gz_errnum));
}
#endif /* _STANDALONE_ */


char **
mar_list_contents(struct mar_stream *s)
{
	struct mar_element * elem = s->first_element;
	char * tmp_contents[500];
	char ** answ;
	int i = 0;
	while (elem)
	{
		tmp_contents[i++] = strdup(elem->filename);
		elem = elem->next_element;
	}
	tmp_contents[i++] = NULL;
	answ = (char **) malloc(sizeof(char *) * i);
	memcpy(answ, tmp_contents, sizeof(char *) * i);
	return answ;
}

int
mar_calc_integrity(struct mar_stream *s)
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
		while (bytes > 0)
		{
			bytes--;
			current_crc += buf[bytes];
		}
	}
	return current_crc;
}


int
mar_extract_file(struct mar_stream *s, char *filename, char *dest_dir)
{
	struct mar_element * elem = s->first_element;
	while (elem)
	{
		if (strcmp(elem->filename, filename) == 0)
		{
			char *buf;
			char *dest_file;
			int fd;
			dest_file = (char *) alloca(strlen(dest_dir) + strlen(filename) + 1);
			strcpy(dest_file, dest_dir);
			strcat(dest_file, filename);
			fd = creat(dest_file, 00660);
			if (fd == -1)
			{
				log_perror(dest_file);
				return -1;
			}
			buf = (char *) alloca(elem->file_length);
			if (!buf)
			{
				log_perror(dest_file);
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
				log_perror(dest_file);
				return -1;
			}
			close(fd); /* do not check return value for code size */
			return 0;
		}
		elem = elem->next_element;
	}
	return 1; /* 1 for file_not_found_in_archive */
}


int
mar_open_file(char *filename, struct mar_stream *s)
{
	int end_filetable = 0;
	struct mar_element * previous_element = NULL;

	/* mar_gzfile */
	s->mar_gzfile = gzopen(filename, "rb");
	if (!s->mar_gzfile)
	{
		log_perror(filename);
		return -1;
	}

	/* crc32 */
	if (gzread(s->mar_gzfile, &(s->crc32), sizeof(int)) != sizeof(int))
	{
		gzerr(s->mar_gzfile);
		return -1;
	}

	/* verify integrity */
	if (s->crc32 != mar_calc_integrity(s))
		log_message("ERROR! mar_open_file: CRC check failed (trying to continue)");

	if (gzseek(s->mar_gzfile, sizeof(int), SEEK_SET) != sizeof(int))
	{
		gzerr(s->mar_gzfile);
		return -1;
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
				return -1;
			}
			ptr++;
		} while ((buf[ptr-1] != 0) && (ptr < 512));
		/* ptr == 1 when we arrive on the "char 0" of the end of the filetable */
		if (ptr > 1)
		{
			struct mar_element * e = (struct mar_element *) malloc(sizeof(struct mar_element));
			e->filename = strdup(buf);
			/* read file_length */
			if (gzread(s->mar_gzfile, &(e->file_length), sizeof(int)) != sizeof(int))
			{
				gzerr(s->mar_gzfile);
				return -1;
			}
			/* read data_offset */
			if (gzread(s->mar_gzfile, &(e->data_offset), sizeof(int)) != sizeof(int))
			{
				gzerr(s->mar_gzfile);
				return -1;
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

	return 0;
}

