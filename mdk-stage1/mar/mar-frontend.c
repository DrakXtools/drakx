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
 * This code includes the extracting and creating features.
 *
 */

#include "mar.h"
#include "mar-extract-only.h"

void
mar_list_files(struct mar_stream *s)
{
	struct mar_element * elem = s->first_element;
	printf("%-20s%8s\n", "FILENAME", "LENGTH");
	while (elem)
	{
		printf("%-20s%8d\n", elem->filename, elem->file_length);
		elem = elem->next_element;
	}
}

int
file_size(char *filename)
{
	struct stat buf;
	if (stat(filename, &buf) != 0)
	{
		perror(filename);
		return -1;
	}
	return buf.st_size;
}


/* Yes I don't use the datastructure I directly write the final fileformat in memory then write down it.
 * Yes it's bad.
 */
/* ``files'' is a NULL-terminated array of char* */

int
mar_create_file(char *dest_file, char **files)
{
	int filenum = 0;
	int current_offset_filetable;
	int current_offset_rawdata;
	char * temp_marfile_buffer;
	int total_length;

	/* calculate offset of ``raw_files_data'' */
	current_offset_rawdata = sizeof(int) + sizeof(char); /* crc32, ``char 0'' */
	while (files[filenum])
	{
		current_offset_rawdata += 2*sizeof(int) /* file_length, data_offset */ + strlen(files[filenum]) + 1;
		filenum++;
	}
	DEBUG_MAR(printf("D: mar::create_marfile number-of-files %d offset-data-start %d\n", filenum, current_offset_rawdata););

	/* calculate length of final uncompressed marfile, for malloc */
	total_length = current_offset_rawdata; /* first part of the marfile: the crc plus filetable */
	filenum = 0;
	while (files[filenum])
	{
		int fsiz = file_size(files[filenum]);
		if (fsiz == -1)
			return -1;
		total_length += fsiz;
		filenum++;
	}
	temp_marfile_buffer = (char *) alloca(total_length); /* create the whole file in-memory  */
	DEBUG_MAR(printf("D: mar::create_marfile total-length %d\n", total_length););

	current_offset_filetable = sizeof(int); /* first file is after the crc */
	filenum = 0;
	while (files[filenum])
	{
		FILE * f = fopen(files[filenum], "rb");
		int fsize;
		if (!f)
		{
			perror(files[filenum]);
			return -1;
		}

		/* filename */
		strcpy(&(temp_marfile_buffer[current_offset_filetable]), files[filenum]);
		current_offset_filetable += strlen(files[filenum]) + 1;

		/* file_length */
		fsize = file_size(files[filenum]);
		if (fsize == -1) return -1;
		memcpy(&temp_marfile_buffer[current_offset_filetable], &fsize, sizeof(int));
		current_offset_filetable += sizeof(int);

		/* data_offset */
		memcpy(&temp_marfile_buffer[current_offset_filetable], &current_offset_rawdata, sizeof(int));
		current_offset_filetable += sizeof(int);

		/* data_raw_data */
		if (fread(&temp_marfile_buffer[current_offset_rawdata], 1, fsize, f) != fsize)
		{
			perror(files[filenum]);
			return -1;
		}
		fclose(f);

		current_offset_rawdata += fsize;

		filenum++;
	}

	/* write down ``char 0'' to terminate file table */
	memset(&temp_marfile_buffer[current_offset_filetable], 0, sizeof(char));

	/* calculate crc with all the data we now got */
	{
		int current_crc = 0;
		int i;
		for (i=sizeof(int); i<total_length ; i++)
			current_crc += temp_marfile_buffer[i];
		memcpy(&temp_marfile_buffer[0], &current_crc, sizeof(int));
		DEBUG_MAR(printf("D: mar::create_marfile computed-crc %d\n", current_crc););
	}

	/* ok, buffer is ready, let's write it on-disk */
	{
		gzFile f = gzopen(dest_file, "wb");
		if (!f)
		{
			perror(dest_file);
			return -1;
		}
		if (gzwrite(f, temp_marfile_buffer, total_length) != total_length)
		{
			fprintf(stderr, gzerror(f, &gz_errnum));
			return -1;
		}
		gz_errnum = gzclose(f);
	}

	return 0;
}


void
print_usage(char *progname)
{
	printf("Usage: %s [-lxc] [files..]\n", progname);
	exit(0);
}

int
main(int argc, char **argv)
{
	if (argc <= 2)
		print_usage(argv[0]);
	
	if (argc >= 3)
	{
		if (strcmp(argv[1], "-l") == 0)
		{
			struct mar_stream s;
			if (mar_open_file(argv[2], &s) != 0)
			{
				fprintf(stderr, "E: open-marfile-failed\n");
				exit(-1);
			}
			mar_list_files(&s);
			exit(0);
		}
		if ((strcmp(argv[1], "-x") == 0) && argc >= 4)
		{
			struct mar_stream s;
			int i = 3;
			if (mar_open_file(argv[2], &s) != 0)
				exit(-1);
			while (i < argc)
			{
				int res = mar_extract_file(&s, argv[i], "./");
				if (res == 1)
					fprintf(stderr, "W: file-not-found-in-archive %s\n", argv[i]);
				if (res == -1)
					exit(-1);
				i++;
			}
			exit(0);
		}
		if ((strcmp(argv[1], "-c") == 0) && argc >= 4)
		{
			char **files = (char **) malloc(((argc-3)+1) * sizeof(char *));
			int i = 3;
			while (i < argc)
			{
				files[i-3] = strdup(argv[i]);
				i++;
			}
			files[argc-3] = NULL;
			{
				int results;
				results = mar_create_file(argv[2], files);
				if (results != 0)
					fprintf(stderr, "E: create-marfile-failed\n");
				exit(results);
			}
					
		}
	}
	
	return 0;
}
