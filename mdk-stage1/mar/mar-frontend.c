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

char * fnf_tag = "FILE_NOT_FOUND&";

int
mar_create_file(char *dest_file, char **files)
{
	int filenum = 0;
	int current_offset_filetable = 0;
	int current_delta_rawdata = 0;
	int filetable_size;
	char * temp_marfile_buffer;
	int total_length = 0;

	filetable_size = sizeof(char); /* ``char 0'' */
	while (files[filenum])
	{
		int fsiz = file_size(files[filenum]);
		if (fsiz == -1)
			files[filenum] = fnf_tag;
		else {
			filetable_size += 2*sizeof(int) /* file_length, data_offset */ + strlen(files[filenum]) + 1;
			total_length += fsiz;
		}
		filenum++;
	}

	total_length += filetable_size;

	temp_marfile_buffer = (char *) malloc(total_length); /* create the whole file in-memory (not with alloca! it can be bigger than typical limit for stack of programs (ulimit -s) */
	DEBUG_MAR(printf("D: mar::create_marfile total-length %d\n", total_length););

	filenum = 0;
	while (files[filenum])
	{
		if (strcmp(files[filenum], fnf_tag)) {
			FILE * f = fopen(files[filenum], "r");
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
			memcpy(&temp_marfile_buffer[current_offset_filetable], &current_delta_rawdata, sizeof(int));
			current_offset_filetable += sizeof(int);
			
			/* data_raw_data */
			if (fread(&temp_marfile_buffer[current_delta_rawdata + filetable_size], 1, fsize, f) != (size_t)fsize)
			{
				perror(files[filenum]);
				return -1;
			}
			fclose(f);

			current_delta_rawdata += fsize;
		}

		filenum++;
	}

	/* write down ``char 0'' to terminate file table */
	memset(&temp_marfile_buffer[current_offset_filetable], 0, sizeof(char));

	/* ok, buffer is ready, let's write it on-disk */
	{
		BZFILE * f = BZ2_bzopen(dest_file, "w9");
		if (!f)
		{
			perror(dest_file);
			return -1;
		}
		if (BZ2_bzwrite(f, temp_marfile_buffer, total_length) != total_length)
		{
			fprintf(stderr, BZ2_bzerror(f, &z_errnum));
			return -1;
		}
		BZ2_bzclose(f);
	}

	printf("mar: created archive %s (%d files, length %d)\n", dest_file, filenum, total_length);
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
			char ** contents = mar_list_contents(argv[2]);
			if (contents)
				while (contents && *contents) {
					printf("\t%s\n", *contents);
					contents++;
				}
			exit(0);
		}
		if ((strcmp(argv[1], "-x") == 0) && argc == 4)
		{
			int res = mar_extract_file(argv[2], argv[3], "./");
			if (res == 1)
				fprintf(stderr, "W: file-not-found-in-archive %s\n", argv[3]);
			if (res == -1)
				exit(-1);
			exit(0);
		}
		if ((strcmp(argv[1], "-c") == 0) && argc >= 4)
		{
			char **files = (char **) alloca(((argc-3)+1) * sizeof(char *));
			int i = 3;
			while (i < argc)
			{
				files[i-3] = argv[i];
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
