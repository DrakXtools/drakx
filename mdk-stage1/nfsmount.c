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

/* this is based on work from redhat, made it lighter (gc)
 */


/* MODIFIED for Red Hat Linux installer
 * msw@redhat.com
 * o always mounts without lockd
 * o uses our own host resolution
 */

/*
 * nfsmount.c -- Linux NFS mount
 * Copyright (C) 1993 Rick Sladkey <jrs@world.std.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * Wed Feb  8 12:51:48 1995, biro@yggdrasil.com (Ross Biro): allow all port
 * numbers to be specified on the command line.
 *
 * Fri, 8 Mar 1996 18:01:39, Swen Thuemmler <swen@uni-paderborn.de>:
 * Omit the call to connect() for Linux version 1.3.11 or later.
 *
 * Wed Oct  1 23:55:28 1997: Dick Streefland <dick_streefland@tasking.com>
 * Implemented the "bg", "fg" and "retry" mount options for NFS.
 */

/*
 * nfsmount.c,v 1.1.1.1 1993/11/18 08:40:51 jrs Exp
 */

#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <netdb.h>
#include <sys/mount.h>
#include <rpc/rpc.h>
#include <rpc/pmap_prot.h>
#include <rpc/pmap_clnt.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include "linux-2.2/nfs.h"
#include "linux-2.2/nfs_mount.h" //#include "mount_constants.h"


#include "dns.h"
#include "log.h"

#include "nfsmount.h"


bool_t
xdr_fhandle(XDR *xdrs, fhandle objp)
{
	 if (!xdr_opaque(xdrs, objp, FHSIZE)) {
		 return (FALSE);
	 }
	return (TRUE);
}

bool_t
xdr_fhstatus(XDR *xdrs, fhstatus *objp)
{

	 if (!xdr_u_int(xdrs, &objp->fhs_status)) {
		 return (FALSE);
	 }
	switch (objp->fhs_status) {
	case 0:
		 if (!xdr_fhandle(xdrs, objp->fhstatus_u.fhs_fhandle)) {
			 return (FALSE);
		 }
		break;
	default:
		break;
	}
	return (TRUE);
}

bool_t
xdr_dirpath(XDR *xdrs, dirpath *objp)
{

	 if (!xdr_string(xdrs, objp, MNTPATHLEN)) {
		 return (FALSE);
	 }
	return (TRUE);
}


static int nfs_mount_version = 3; /* kernel >= 2.1.32 */   /* *********** TODO for kernel 2.4, nfs-mount version 4 */


int nfsmount_prepare(const char *spec, int *flags, char **mount_opts)
{
	char hostdir[1024];
	CLIENT *mclient;
	char *hostname, *dirname;
	fhandle root_fhandle;
	struct timeval total_timeout;
	enum clnt_stat clnt_stat;
	static struct nfs_mount_data data;
	struct sockaddr_in server_addr;
	struct sockaddr_in mount_server_addr;
	int msock, fsock;
	struct timeval retry_timeout;
	struct fhstatus status;
	char *s;
	int port;

	msock = fsock = -1;
	mclient = NULL;

	strncpy(hostdir, spec, sizeof(hostdir));
	if ((s = (strchr(hostdir, ':')))) {
		hostname = hostdir;
		dirname = s + 1;
		*s = '\0';
	} else {
		log_message("nfsmount: format not host:dir");
		goto fail;
	}

	server_addr.sin_family = AF_INET;

	/* first, try as IP address */
	if (!inet_aton(hostname, &server_addr.sin_addr)) {
		/* failure, try as machine name */
		if (mygethostbyname(hostname, &server_addr.sin_addr)) {
			log_message("nfsmount: can't get address for %s", hostname);
			goto fail;
		} else
			server_addr.sin_family = AF_INET;
	}

	memcpy (&mount_server_addr, &server_addr, sizeof (mount_server_addr));



	/* Set default options.
	 * rsize/wsize (and bsize, for ver >= 3) are left 0 in order to
	 * let the kernel decide.
	 * timeo is filled in after we know whether it'll be TCP or UDP. */
	memset(&data, 0, sizeof(data));
	data.retrans	= 3;
	data.acregmin	= 3;
	data.acregmax	= 60;
	data.acdirmin	= 30;
	data.acdirmax	= 60;
#if NFS_MOUNT_VERSION >= 2
	data.namlen	= NAME_MAX;
#endif

#if NFS_MOUNT_VERSION >= 3
	if (nfs_mount_version >= 3)
	        data.flags |= NFS_MOUNT_NONLM; /* HACK HACK msw */
#endif

	/* Adjust options if none specified */
	if (!data.timeo)
		data.timeo = 7;  /* udp */


	data.version = nfs_mount_version;
	*mount_opts = (char *) &data;

	if (*flags & MS_REMOUNT)
		return 0;


	retry_timeout.tv_sec = 3;
	retry_timeout.tv_usec = 0;
	total_timeout.tv_sec = 20;
	total_timeout.tv_usec = 0;


	/* contact the mount daemon via TCP */
	mount_server_addr.sin_port = htons(0);
	msock = RPC_ANYSOCK;
	mclient = clnttcp_create(&mount_server_addr, MOUNTPROG, MOUNTVERS, &msock, 0, 0);
	
	/* if this fails, contact the mount daemon via UDP */
	if (!mclient) {
		mount_server_addr.sin_port = htons(0);
		msock = RPC_ANYSOCK;
		mclient = clntudp_create(&mount_server_addr, MOUNTPROG, MOUNTVERS, retry_timeout, &msock);
	}
	if (mclient) {
				/* try to mount hostname:dirname */
		mclient->cl_auth = authunix_create_default();
		clnt_stat = clnt_call(mclient, MOUNTPROC_MNT,
				      (xdrproc_t) xdr_dirpath, (caddr_t) &dirname,
				      (xdrproc_t) xdr_fhstatus, (caddr_t) &status,
				      total_timeout);
		if (clnt_stat != RPC_SUCCESS) {
			if (errno != ECONNREFUSED) {
				log_message(clnt_sperror(mclient, "mount"));
				goto fail;	/* don't retry */
			}
			log_message(clnt_sperror(mclient, "mount"));
			auth_destroy(mclient->cl_auth);
			clnt_destroy(mclient);
			mclient = 0;
			close(msock);
		}
	} else
		goto fail;

	if (status.fhs_status != 0) {
		log_message("nfsmount prepare failed, reason given by server: %d", status.fhs_status);
		goto fail;
	}

	memcpy((char *) &root_fhandle, (char *) status.fhstatus_u.fhs_fhandle, sizeof (root_fhandle));

	/* create nfs socket for kernel */

	fsock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (fsock < 0) {
		log_perror("nfs socket");
		goto fail;
	}
	if (bindresvport(fsock, 0) < 0) {
		log_perror("nfs bindresvport");
		goto fail;
	}
	server_addr.sin_port = PMAPPORT;
	port = pmap_getport(&server_addr, NFS_PROGRAM, NFS_VERSION, IPPROTO_UDP);
	if (port == 0)
		port = NFS_PORT;
#ifdef NFS_MOUNT_DEBUG
	else
		log_message("used portmapper to find NFS port\n");
	log_message("using port %d for nfs deamon\n", port);
#endif
	server_addr.sin_port = htons(port);

	/* prepare data structure for kernel */

	data.fd = fsock;
	memcpy((char *) &data.root, (char *) &root_fhandle, sizeof (root_fhandle));
	memcpy((char *) &data.addr, (char *) &server_addr, sizeof(data.addr));
	strncpy(data.hostname, hostname, sizeof(data.hostname));

	/* clean up */

	auth_destroy(mclient->cl_auth);
	clnt_destroy(mclient);
	close(msock);
	return 0;

	/* abort */

 fail:
	if (msock != -1) {
		if (mclient) {
			auth_destroy(mclient->cl_auth);
			clnt_destroy(mclient);
		}
		close(msock);
	}
	if (fsock != -1)
		close(fsock);

	return -1;
}	

