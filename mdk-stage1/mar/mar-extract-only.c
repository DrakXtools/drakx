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

#include "mar-extract-only.h"
#include "mar.h"

#ifdef _STANDALONE_
void
zerr(BZFILE * f) /* decrease code size */
{
	fprintf(stderr, BZ2_bzerror(f, &z_errnum));
}

inline void
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
zerr(BZFILE * f) /* decrease code size */
{
	log_message(BZ2_bzerror(f, &z_errnum));
}
#endif /* _STANDALONE_ */


static int
mar_open_file(char *filename, struct mar_stream *s)
{
	int end_filetable = 0;
	struct mar_element * previous_element = NULL;

	/* mar_zfile */
	s->mar_zfile = BZ2_bzopen(filename, "rb");
	if (!s->mar_zfile)
	{
		log_perror(filename);
		return -1;
	}

	while (end_filetable == 0)
	{
		char buf[512];
		int ptr = 0;
		/* read filename */
		do
		{
			if (BZ2_bzread(s->mar_zfile, &(buf[ptr]), sizeof(char)) != sizeof(char))
			{
				zerr(s->mar_zfile);
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
			if (BZ2_bzread(s->mar_zfile, &(e->file_length), sizeof(int)) != sizeof(int))
			{
				zerr(s->mar_zfile);
				return -1;
			}
			/* read data_offset */
			if (BZ2_bzread(s->mar_zfile, &(e->data_offset), sizeof(int)) != sizeof(int))
			{
				zerr(s->mar_zfile);
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


char **
mar_list_contents(char * mar_filename)
{
	struct mar_stream s;
	struct mar_element * elem;
	char * tmp_contents[500];
	char ** answ;
	int i = 0;

	if (mar_open_file(mar_filename, &s))
		return NULL;

	elem = s.first_element;
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
mar_extract_file(char *mar_filename, char *filename_to_extract, char *dest_dir)
{
	struct mar_stream s;
	struct mar_element * elem;

	if (mar_open_file(mar_filename, &s))
		return -1;

	elem = s.first_element;
	while (elem)
	{
		if (strcmp(elem->filename, filename_to_extract) == 0)
		{
			char garb_buf[4096];
			char *buf;
			char *dest_file;
			int fd;
			size_t i;
			dest_file = (char *) alloca(strlen(dest_dir) + strlen(filename_to_extract) + 1);
			strcpy(dest_file, dest_dir);
			strcat(dest_file, filename_to_extract);
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
			i = elem->data_offset;
			while (i > 0) {
				int to_read = i > sizeof(garb_buf) ? sizeof(garb_buf) : i;
				if (BZ2_bzread(s.mar_zfile, garb_buf, to_read) != to_read) {
					log_message("MAR: unexpected EOF in stream");
					return -1;
				}
				i -= to_read;
			}
			if (BZ2_bzread(s.mar_zfile, buf, elem->file_length) != elem->file_length)
			{
				zerr(s.mar_zfile);
				return -1;
			}
			if (write(fd, buf, elem->file_length) != elem->file_length)
			{
				log_perror(dest_file);
				return -1;
			}
			close(fd); /* do not check return value for code size */
			BZ2_bzclose(s.mar_zfile);
			return 0;
		}
		elem = elem->next_element;
	}
	BZ2_bzclose(s.mar_zfile);
	return 1; /* 1 for file_not_found_in_archive */
}


