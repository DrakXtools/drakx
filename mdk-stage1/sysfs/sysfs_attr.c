/*
 * sysfs_dir.c
 *
 * Directory utility functions for libsysfs
 *
 * Copyright (C) IBM Corp. 2003-2005
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 */
#include "libsysfs.h"
#include "sysfs.h"

/**
 * sysfs_close_attribute: closes and cleans up attribute
 * @sysattr: attribute to close.
 */
void sysfs_close_attribute(struct sysfs_attribute *sysattr)
{
	if (sysattr) {
		if (sysattr->value)
			free(sysattr->value);
		free(sysattr);
	}
}

/**
 * alloc_attribute: allocates and initializes attribute structure
 * returns struct sysfs_attribute with success and NULL with error.
 */
static struct sysfs_attribute *alloc_attribute(void)
{
	return (struct sysfs_attribute *)
			calloc(1, sizeof(struct sysfs_attribute));
}

/**
 * sysfs_open_attribute: creates sysfs_attribute structure
 * @path: path to attribute.
 * returns sysfs_attribute struct with success and NULL with error.
 */
struct sysfs_attribute *sysfs_open_attribute(const char *path)
{
	struct sysfs_attribute *sysattr = NULL;
	struct stat fileinfo;

	if (!path) {
		errno = EINVAL;
		return NULL;
	}
	sysattr = alloc_attribute();
	if (!sysattr) {
		dprintf("Error allocating attribute at %s\n", path);
		return NULL;
	}
	if (sysfs_get_name_from_path(path, sysattr->name,
				SYSFS_NAME_LEN) != 0) {
		dprintf("Error retrieving attrib name from path: %s\n", path);
		sysfs_close_attribute(sysattr);
		return NULL;
	}
	safestrcpy(sysattr->path, path);
	if ((stat(sysattr->path, &fileinfo)) != 0) {
		dprintf("Stat failed: No such attribute?\n");
		sysattr->method = 0;
		free(sysattr);
		sysattr = NULL;
	} else {
		if (fileinfo.st_mode & S_IRUSR)
			sysattr->method |= SYSFS_METHOD_SHOW;
		if (fileinfo.st_mode & S_IWUSR)
			sysattr->method |= SYSFS_METHOD_STORE;
	}

	return sysattr;
}

/**
 * sysfs_read_attribute: reads value from attribute
 * @sysattr: attribute to read
 * returns 0 with success and -1 with error.
 */
int sysfs_read_attribute(struct sysfs_attribute *sysattr)
{
	char *fbuf = NULL;
	char *vbuf = NULL;
	ssize_t length = 0;
	long pgsize = 0;
	int fd;

	if (!sysattr) {
		errno = EINVAL;
		return -1;
	}
	if (!(sysattr->method & SYSFS_METHOD_SHOW)) {
		dprintf("Show method not supported for attribute %s\n",
			sysattr->path);
		errno = EACCES;
		return -1;
	}
	pgsize = getpagesize();
	fbuf = (char *)calloc(1, pgsize+1);
	if (!fbuf) {
		dprintf("calloc failed\n");
		return -1;
	}
	if ((fd = open(sysattr->path, O_RDONLY)) < 0) {
		dprintf("Error reading attribute %s\n", sysattr->path);
		free(fbuf);
		return -1;
	}
	length = read(fd, fbuf, pgsize);
	if (length < 0) {
		dprintf("Error reading from attribute %s\n", sysattr->path);
		close(fd);
		free(fbuf);
		return -1;
	}
	if (sysattr->len > 0) {
		if ((sysattr->len == length) &&
				(!(strncmp(sysattr->value, fbuf, length)))) {
			close(fd);
			free(fbuf);
			return 0;
		}
		free(sysattr->value);
	}
	sysattr->len = length;
	close(fd);
	vbuf = (char *)realloc(fbuf, length+1);
	if (!vbuf) {
		dprintf("realloc failed\n");
		free(fbuf);
		return -1;
	}
	sysattr->value = vbuf;

	return 0;
}

/**
 * sysfs_write_attribute: write value to the attribute
 * @sysattr: attribute to write
 * @new_value: value to write
 * @len: length of "new_value"
 * returns 0 with success and -1 with error.
 */
int sysfs_write_attribute(struct sysfs_attribute *sysattr,
		const char *new_value, size_t len)
{
	int fd;
	int length;

	if (!sysattr || !new_value || len == 0) {
		errno = EINVAL;
		return -1;
	}

	if (!(sysattr->method & SYSFS_METHOD_STORE)) {
		dprintf ("Store method not supported for attribute %s\n",
			sysattr->path);
		errno = EACCES;
		return -1;
	}
	if (sysattr->method & SYSFS_METHOD_SHOW) {
		/*
		 * read attribute again to see if we can get an updated value
		 */
		if ((sysfs_read_attribute(sysattr))) {
			dprintf("Error reading attribute\n");
			return -1;
		}
		if ((strncmp(sysattr->value, new_value, sysattr->len)) == 0 &&
				(len == sysattr->len)) {
			dprintf("Attr %s already has the requested value %s\n",
					sysattr->name, new_value);
			return 0;
		}
	}
	/*
	 * open O_WRONLY since some attributes have no "read" but only
	 * "write" permission
	 */
	if ((fd = open(sysattr->path, O_WRONLY)) < 0) {
		dprintf("Error reading attribute %s\n", sysattr->path);
		return -1;
	}

	length = write(fd, new_value, len);
	if (length < 0) {
		dprintf("Error writing to the attribute %s - invalid value?\n",
			sysattr->name);
		close(fd);
		return -1;
	} else if ((unsigned int)length != len) {
		dprintf("Could not write %zd bytes to attribute %s\n",
					len, sysattr->name);
		/*
		 * since we could not write user supplied number of bytes,
		 * restore the old value if one available
		 */
		if (sysattr->method & SYSFS_METHOD_SHOW) {
			length = write(fd, sysattr->value, sysattr->len);
			close(fd);
			return -1;
		}
	}

	/*
	 * Validate length that has been copied. Alloc appropriate area
	 * in sysfs_attribute. Verify first if the attribute supports reading
	 * (show method). If it does not, do not bother
	 */
	if (sysattr->method & SYSFS_METHOD_SHOW) {
		if (length != sysattr->len) {
			sysattr->value = (char *)realloc
				(sysattr->value, length);
			sysattr->len = length;
			safestrcpymax(sysattr->value, new_value, length);
		} else {
			/*"length" of the new value is same as old one */
			safestrcpymax(sysattr->value, new_value, length);
		}
	}

	close(fd);
	return 0;
}

