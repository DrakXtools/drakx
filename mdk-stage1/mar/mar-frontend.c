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

void list_files(mar_stream *s)
{
	mar_element * elem = s->first_element;
	printf("%-20s%8s\n", "FILENAME", "LENGTH");
	while (elem != NULL)
	{
		printf("%-20s%8d\n", elem->filename, elem->file_length);
		elem = elem->next_element;
	}
}


int file_size(char *filename)
{
	FILE * f = fopen(filename, "rb");
	int size;
	DEBUG_MAR(printf("D: mar::file_size filename %s\n", filename););
	if (f == NULL)
	{
		perror(filename);
		return -1;
	}
	if (fseek(f, 0L, SEEK_END) == -1)
	{
		perror(filename);
		return -1;
	}
	size = ftell(f);
	if (size == -1)
	{
		perror(filename);
		return -1;
	}
	if (fclose(f) != 0)
	{
		perror(filename);
		return -1;
	}
	return size;
}


/* Yes I don't use the datastructure I directly write the final fileformat in memory then write down it.
 * Yes it's bad.
 */
/* ``files'' is a NULL-terminated array of char* */

int create_marfile(char *dest_file, char **files)
{
	int filenum = 0;
	int current_offset_filetable;
	int current_offset_rawdata;
	char * temp_marfile_buffer;
	int total_length;

	/* calculate offset of ``raw_files_data'' */
	current_offset_rawdata = sizeof(int) + sizeof(char); /* crc32, ``char 0'' */
	while (files[filenum] != NULL)
	{
		current_offset_rawdata += 2*sizeof(int) /* file_length, data_offset */ + strlen(files[filenum]) + 1;
		filenum++;
	}
	DEBUG_MAR(printf("D: mar::create_marfile number-of-files %d offset-data-start %d\n", filenum, current_offset_rawdata););

	/* calculate length of final uncompressed marfile, for malloc */
	total_length = current_offset_rawdata; /* first part of the marfile: the crc plus filetable */
	filenum = 0;
	while (files[filenum] != NULL)
	{
		int fsiz = file_size(files[filenum]);
		if (fsiz == -1)
			return -1;
		total_length += fsiz;
		filenum++;
	}
	temp_marfile_buffer = (void *) malloc(total_length); /* create the whole file in-memory  */
	DEBUG_MAR(printf("D: mar::create_marfile total-length %d\n", total_length););

	current_offset_filetable = sizeof(int); /* first file is after the crc */
	filenum = 0;
	while (files[filenum] != NULL)
	{
		FILE * f = fopen(files[filenum], "rb");
		int fsize;
		if (f == NULL)
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
		if (f == NULL)
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

//	  /* uncompressed write
//	    
//		  int fd = creat(dest_file, 00660);
//		  if (fd == -1)
//		  {
//			  perror("E: mar::create_marfile::creat");
//			  return -1;
//		  }
//		  if (write(fd, temp_marfile_buffer, total_length) != total_length)
//		  {
//			  perror("E: mar::create_marfile::write");
//			  return -1;
//		  }
//		  if (close(fd) != 0)
//		  {
//			  perror("E: mar::create_marfile::close");
//			  return -1;
//		  }
//	  */

	return 0;
}


void print_usage(char *progname)
{
	printf("Usage: %s [-lxc] [files..]\n", progname);
	exit(0);
}

int main(int argc, char **argv)
{
	if (argc <= 2)
		print_usage(argv[0]);

	if (argc >= 3)
	{
		if (strcmp(argv[1], "-l") == 0)
		{
			mar_stream *s = open_marfile(argv[2]);
			if (s == NULL)
				exit(-1);
			list_files(s);
			if (s->crc32 == calc_integrity(s))
				printf("CRC OK\n");
			else
				printf("CRC FAILED!\n");
			exit(0);
		}
		if ((strcmp(argv[1], "-x") == 0) && argc >= 4)
		{
			mar_stream *s = open_marfile(argv[2]);
			int i = 3;
			if (s == NULL)
				exit(-1);
			while (i < argc)
			{
				int res = extract_file(s, argv[i], "./");
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
			exit(create_marfile(argv[2], files));
		}
	}
	
	return 0;
}
  /*	mar_stream *s;
	int res;
	char *files[4];

	char * file1 = "Makefile";
	char * file2 = "mar.c";
	char * file3 = "mar.h";

	files[0] = file1;
	files[1] = file2;
	files[2] = file3;
	files[3] = NULL;

	create_marfile("test.mar", files);


	s = open_marfile("test.mar");

	if (s == NULL)
		exit(-1);
	
	res = extract_file(s, "Makefile", "t/");
	printf("return-code %d\n", res);

	exit(0);
}
	char plop[20];
	int i,j;
	bzero(plop, 20);
	j = 4096;
	memcpy(&plop[2], &j, sizeof(j));
	for (i=0; i<20; i++) printf("offset %d, contains char %d\n", i, plop[i]);
	exit(-1);

	s.first_element = &e1;
//	s.crc32 = calc_integrity(&s);

	e1.filename = "bonjour";
	e1.file_length = 4;
	e1.next_element = &e2;
	e2.filename = "deuz";
	e2.file_length = 54;
	e2.next_element = NULL;

	list_files(&s);
//	if (verify_integrity(&s)) { printf("CRC OK\n"); } else { printf("CRC FAILS!\n"); }
	return 0;
}

*/
