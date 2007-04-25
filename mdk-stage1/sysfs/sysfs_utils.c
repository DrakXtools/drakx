/*
 * sysfs_utils.c
 *
 * System utility functions for libsysfs
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
 * sysfs_get_name_from_path: returns last name from a "/" delimited path
 * @path: path to get name from
 * @name: where to put name
 * @len: size of name
 */
int sysfs_get_name_from_path(const char *path, char *name, size_t len)
{
	char tmp[SYSFS_PATH_MAX];
	char *n = NULL;

	if (!path || !name || len == 0) {
		errno = EINVAL;
		return -1;
	}
	memset(tmp, 0, SYSFS_PATH_MAX);
	safestrcpy(tmp, path);
	n = strrchr(tmp, '/');
	if (n == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (*(n+1) == '\0') {
		*n = '\0';
		n = strrchr(tmp, '/');
		if (n == NULL) {
			errno = EINVAL;
			return -1;
		}
	}
	n++;
	safestrcpymax(name, n, len);
	return 0;
}
