/*
 * libsysfs.h
 *
 * Header Definitions for libsysfs
 *
 * Copyright (C) IBM Corp. 2004-2005
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
#ifndef _LIBSYSFS_H_
#define _LIBSYSFS_H_

#include <sys/types.h>
#include <string.h>

#define SYSFS_FSTYPE_NAME	"sysfs"
#define SYSFS_PROC_MNTS		"/proc/mounts"
#define SYSFS_BUS_NAME		"bus"
#define SYSFS_CLASS_NAME	"class"
#define SYSFS_BLOCK_NAME	"block"
#define SYSFS_DEVICES_NAME	"devices"
#define SYSFS_DRIVERS_NAME	"drivers"
#define SYSFS_MODULE_NAME	"module"
#define SYSFS_NAME_ATTRIBUTE	"name"
#define SYSFS_MOD_PARM_NAME	"parameters"
#define SYSFS_MOD_SECT_NAME	"sections"
#define SYSFS_UNKNOWN		"unknown"
#define SYSFS_PATH_ENV		"SYSFS_PATH"

#define SYSFS_PATH_MAX		256
#define	SYSFS_NAME_LEN		64
#define SYSFS_BUS_ID_SIZE	32

/* mount path for sysfs, can be overridden by exporting SYSFS_PATH */
#define SYSFS_MNT_PATH		"/sys"

enum sysfs_attribute_method {
	SYSFS_METHOD_SHOW =	0x01,	/* attr can be read by user */
	SYSFS_METHOD_STORE =	0x02,	/* attr can be changed by user */
};

/*
 * NOTE:
 * 1. We have the statically allocated "name" as the first element of all
 * the structures. This feature is used in the "sorter" function for dlists
 * 2. As is the case with attrlist
 * 3. As is the case with path
 */
struct sysfs_attribute {
	char name[SYSFS_NAME_LEN];
	char path[SYSFS_PATH_MAX];
	char *value;
	unsigned short len;			/* value length */
	enum sysfs_attribute_method method;	/* show and store */
};

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Function Prototypes
 */
extern int sysfs_get_name_from_path(const char *path, char *name, size_t len);

/* sysfs directory and file access */
extern void sysfs_close_attribute(struct sysfs_attribute *sysattr);
extern struct sysfs_attribute *sysfs_open_attribute(const char *path);
extern int sysfs_read_attribute(struct sysfs_attribute *sysattr);
extern int sysfs_write_attribute(struct sysfs_attribute *sysattr,
		const char *new_value, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* _LIBSYSFS_H_ */
