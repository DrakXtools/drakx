 /*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2003 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * basing on nfsmount.c from util-linux-2.11z:
 * - use our logging facilities
 * - use our host resolving stuff
 * - remove unneeded code
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
 *
 * 1999-02-22 Arkadiusz Miśkiewicz <misiek@pld.ORG.PL>
 * - added Native Language Support
 * 
 * Modified by Olaf Kirch and Trond Myklebust for new NFS code,
 * plus NFSv3 stuff.
 *
 * 2003-04-14 David Black <david.black@xilinx.com>
 * - added support for multiple hostname NFS mounts
 */

/*
 * nfsmount.c,v 1.1.1.1 1993/11/18 08:40:51 jrs Exp
 */

#define HAVE_rpcsvc_nfs_prot_h
#define HAVE_inet_aton

#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <netdb.h>
#include <time.h>
#include <rpc/rpc.h>
#include <rpc/pmap_prot.h>
#include <rpc/pmap_clnt.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <values.h>

#include "nfsmount.h"

#ifdef HAVE_rpcsvc_nfs_prot_h
#include <rpcsvc/nfs_prot.h>
#else
#include <linux/nfs.h>
#define nfsstat nfs_stat
#endif

#include "nfs_mount4.h"

#include "log.h"
#include "dns.h"

#ifndef NFS_PORT
#define NFS_PORT 2049
#endif
#ifndef NFS_FHSIZE
#define NFS_FHSIZE 32
#endif

static char *nfs_strerror(int stat);

#define MAKE_VERSION(p,q,r)	(65536*(p) + 256*(q) + (r))

#define MAX_NFSPROT ((nfs_mount_version >= 4) ? 3 : 2)

bool_t
xdr_fhandle3 (XDR *xdrs, fhandle3 *objp)
{
	 if (!xdr_bytes (xdrs, (char **)&objp->fhandle3_val, (u_int *) &objp->fhandle3_len, FHSIZE3))
		 return FALSE;
	return TRUE;
}

bool_t
xdr_mountstat3 (XDR *xdrs, mountstat3 *objp)
{
	 if (!xdr_enum (xdrs, (enum_t *) objp))
		 return FALSE;
	return TRUE;
}

bool_t
xdr_mountres3_ok (XDR *xdrs, mountres3_ok *objp)
{
	 if (!xdr_fhandle3 (xdrs, &objp->fhandle))
		 return FALSE;
	 if (!xdr_array (xdrs, (char **)&objp->auth_flavours.auth_flavours_val, (u_int *) &objp->auth_flavours.auth_flavours_len, ~0,
		sizeof (int), (xdrproc_t) xdr_int))
		 return FALSE;
	return TRUE;
}

bool_t
xdr_mountres3 (XDR *xdrs, mountres3 *objp)
{
	 if (!xdr_mountstat3 (xdrs, &objp->fhs_status))
		 return FALSE;
	switch (objp->fhs_status) {
	case MNT_OK:
		 if (!xdr_mountres3_ok (xdrs, &objp->mountres3_u.mountinfo))
			 return FALSE;
		break;
	default:
		break;
	}
	return TRUE;
}

bool_t
xdr_dirpath (XDR *xdrs, dirpath *objp)
{
	 if (!xdr_string (xdrs, objp, MNTPATHLEN))
		 return FALSE;
	return TRUE;
}

bool_t
xdr_fhandle (XDR *xdrs, fhandle objp)
{
	 if (!xdr_opaque (xdrs, objp, FHSIZE))
		 return FALSE;
	return TRUE;
}

bool_t
xdr_fhstatus (XDR *xdrs, fhstatus *objp)
{
	 if (!xdr_u_int (xdrs, &objp->fhs_status))
		 return FALSE;
	switch (objp->fhs_status) {
	case 0:
		 if (!xdr_fhandle (xdrs, objp->fhstatus_u.fhs_fhandle))
			 return FALSE;
		break;
	default:
		break;
	}
	return TRUE;
}


static int
linux_version_code(void) {
	struct utsname my_utsname;
	int p, q, r;

	if (uname(&my_utsname) == 0) {
		p = atoi(strtok(my_utsname.release, "."));
		q = atoi(strtok(NULL, "."));
		r = atoi(strtok(NULL, "."));
		return MAKE_VERSION(p,q,r);
	}
	return 0;
}

/*
 * Unfortunately, the kernel prints annoying console messages
 * in case of an unexpected nfs mount version (instead of
 * just returning some error).  Therefore we'll have to try
 * and figure out what version the kernel expects.
 *
 * Variables:
 *	NFS_MOUNT_VERSION: these nfsmount sources at compile time
 *	nfs_mount_version: version this source and running kernel can handle
 */
static int
find_kernel_nfs_mount_version(void) {
	static int kernel_version = -1;
	int nfs_mount_version = NFS_MOUNT_VERSION;

	if (kernel_version == -1)
		kernel_version = linux_version_code();

	if (kernel_version) {
	     if (kernel_version < MAKE_VERSION(2,1,32))
		  nfs_mount_version = 1;
	     else if (kernel_version < MAKE_VERSION(2,2,18))
		  nfs_mount_version = 3;
	     else if (kernel_version < MAKE_VERSION(2,3,0))
		  nfs_mount_version = 4; /* since 2.2.18pre9 */
	     else if (kernel_version < MAKE_VERSION(2,3,99))
		  nfs_mount_version = 3;
	     else
		  nfs_mount_version = 4; /* since 2.3.99pre4 */
	}
	if (nfs_mount_version > NFS_MOUNT_VERSION)
	     nfs_mount_version = NFS_MOUNT_VERSION;
        log_message("nfsmount: kernel_nfs_mount_version: %d", nfs_mount_version);
	return nfs_mount_version;
}

static struct pmap *
get_mountport(struct sockaddr_in *server_addr,
      long unsigned prog,
      long unsigned version,
      long unsigned proto,
      long unsigned port,
      int nfs_mount_version)
{
	struct pmaplist *pmap;
	static struct pmap p = {0, 0, 0, 0};

	if (version > MAX_NFSPROT)
		version = MAX_NFSPROT;
	if (!prog)
		prog = MOUNTPROG;
	p.pm_prog = prog;
	p.pm_vers = version;
	p.pm_prot = proto;
	p.pm_port = port;

	server_addr->sin_port = PMAPPORT;
	pmap = pmap_getmaps(server_addr);

	while (pmap) {
		if (pmap->pml_map.pm_prog != prog)
			goto next;
		if (!version && p.pm_vers > pmap->pml_map.pm_vers)
			goto next;
		if (version > 2 && pmap->pml_map.pm_vers != version)
			goto next;
		if (version && version <= 2 && pmap->pml_map.pm_vers > 2)
			goto next;
		if (pmap->pml_map.pm_vers > MAX_NFSPROT ||
		    (proto && p.pm_prot && pmap->pml_map.pm_prot != proto) ||
		    (port && pmap->pml_map.pm_port != port))
			goto next;
		memcpy(&p, &pmap->pml_map, sizeof(p));
	next:
		pmap = pmap->pml_next;
	}
	if (!p.pm_vers)
		p.pm_vers = MOUNTVERS;
	if (!p.pm_prot)
		p.pm_prot = IPPROTO_TCP;
	return &p;
}



int nfsmount_prepare(const char *spec, char **mount_opts)
{
	char hostdir[1024];
	CLIENT *mclient;
	char *hostname, *dirname, *mounthost = NULL;
	struct timeval total_timeout;
	enum clnt_stat clnt_stat;
	static struct nfs_mount_data data;
	int nfs_mount_version;
	int val;
	struct sockaddr_in server_addr;
	struct sockaddr_in mount_server_addr;
	struct pmap *pm_mnt;
	int msock, fsock;
	struct timeval retry_timeout;
	union {
		struct fhstatus nfsv2;
		struct mountres3 nfsv3;
	} status;
	char *s;
	int port, mountport, proto, soft, intr;
	int posix, nocto, noac, broken_suid, nolock;
	int retry, tcp;
	int mountprog, mountvers, nfsprog, nfsvers;
	int retval;
	time_t t;
	time_t prevt;
	time_t timeout;

	nfs_mount_version = find_kernel_nfs_mount_version();

	retval = -1;
	msock = fsock = -1;
	mclient = NULL;
	if (strlen(spec) >= sizeof(hostdir)) {
		log_message("nfsmount: excessively long host:dir argument");
		goto fail;
	}
	strcpy(hostdir, spec);
	if ((s = strchr(hostdir, ':'))) {
		hostname = hostdir;
		dirname = s + 1;
		*s = '\0';
	} else {
		log_message("nfsmount: directory to mount not in host:dir format");
		goto fail;
	}

	server_addr.sin_family = AF_INET;
#ifdef HAVE_inet_aton
	if (!inet_aton(hostname, &server_addr.sin_addr))
#endif
	{
		if (mygethostbyname(hostname, &server_addr.sin_addr)) {
			log_message("nfsmount: can't get address for %s", hostname);
			goto fail;
		}
	}

	memcpy (&mount_server_addr, &server_addr, sizeof (mount_server_addr));



	/* Set default options.
	 * rsize/wsize are set to 8192 to enable nfs install on
	 * old i586 machines
	 * timeo is filled in after we know whether it'll be TCP or UDP. */
	memset(&data, 0, sizeof(data));
	data.rsize	= 8192;
	data.wsize	= 8192;
	data.retrans	= 30;
	data.acregmin	= 3;
	data.acregmax	= 60;
	data.acdirmin	= 30;
	data.acdirmax	= 60;
#if NFS_MOUNT_VERSION >= 2
	data.namlen	= NAME_MAX;
#endif

	soft = 1;
	intr = 0;
	posix = 0;
	nocto = 0;
	nolock = 1;
	broken_suid = 0;
	noac = 0;
	retry = 10000;		/* 10000 minutes ~ 1 week */
	tcp = 0;

	mountprog = MOUNTPROG;
	mountvers = 0;
	port = 0;
	mountport = 0;
	nfsprog = NFS_PROGRAM;
	nfsvers = 0;



retry_mount:
	proto = (tcp) ? IPPROTO_TCP : IPPROTO_UDP;

	data.flags = (soft ? NFS_MOUNT_SOFT : 0)
		| (intr ? NFS_MOUNT_INTR : 0)
		| (posix ? NFS_MOUNT_POSIX : 0)
		| (nocto ? NFS_MOUNT_NOCTO : 0)
		| (noac ? NFS_MOUNT_NOAC : 0);
#if NFS_MOUNT_VERSION >= 2
	if (nfs_mount_version >= 2)
		data.flags |= (tcp ? NFS_MOUNT_TCP : 0);
#endif
#if NFS_MOUNT_VERSION >= 3
	if (nfs_mount_version >= 3)
		data.flags |= (nolock ? NFS_MOUNT_NONLM : 0);
#endif
#if NFS_MOUNT_VERSION >= 4
	if (nfs_mount_version >= 4)
		data.flags |= (broken_suid ? NFS_MOUNT_BROKEN_SUID : 0);
#endif
	if (nfsvers > MAX_NFSPROT) {
		log_message("NFSv%d not supported!", nfsvers);
		return 0;
	}
	if (mountvers > MAX_NFSPROT) {
		log_message("NFSv%d not supported!", nfsvers);
		return 0;
	}
	if (nfsvers && !mountvers)
		mountvers = (nfsvers < 3) ? 1 : nfsvers;
	if (nfsvers && nfsvers < mountvers)
		mountvers = nfsvers;

	/* Adjust options if none specified */
	if (!data.timeo)
		data.timeo = tcp ? 70 : 7;

#ifdef NFS_MOUNT_DEBUG
	log_message("rsize = %d, wsize = %d, timeo = %d, retrans = %d",
	       data.rsize, data.wsize, data.timeo, data.retrans);
	log_message("acreg (min, max) = (%d, %d), acdir (min, max) = (%d, %d)",
	       data.acregmin, data.acregmax, data.acdirmin, data.acdirmax);
	log_message("port = %d, retry = %d, flags = %.8x",
	       port, retry, data.flags);
	log_message("mountprog = %d, mountvers = %d, nfsprog = %d, nfsvers = %d",
	       mountprog, mountvers, nfsprog, nfsvers);
	log_message("soft = %d, intr = %d, posix = %d, nocto = %d, noac = %d",
	       (data.flags & NFS_MOUNT_SOFT) != 0,
	       (data.flags & NFS_MOUNT_INTR) != 0,
	       (data.flags & NFS_MOUNT_POSIX) != 0,
	       (data.flags & NFS_MOUNT_NOCTO) != 0,
	       (data.flags & NFS_MOUNT_NOAC) != 0);
#if NFS_MOUNT_VERSION >= 2
	log_message("tcp = %d",
	       (data.flags & NFS_MOUNT_TCP) != 0);
#endif
#endif

	data.version = nfs_mount_version;
	*mount_opts = (char *) &data;


	/* create mount deamon client */
	/* See if the nfs host = mount host. */
	if (mounthost) {
		if (mounthost[0] >= '0' && mounthost[0] <= '9') {
			mount_server_addr.sin_family = AF_INET;
			mount_server_addr.sin_addr.s_addr = inet_addr(hostname);
		} else {
                        if (mygethostbyname(mounthost, &mount_server_addr.sin_addr)) {
				log_message("nfsmount: can't get address for %s", mounthost);
				goto fail;
			}
		}
	}

	/*
	 * The following loop implements the mount retries. On the first
	 * call, "running_bg" is 0. When the mount times out, and the
	 * "bg" option is set, the exit status EX_BG will be returned.
	 * For a backgrounded mount, there will be a second call by the
	 * child process with "running_bg" set to 1.
	 *
	 * The case where the mount point is not present and the "bg"
	 * option is set, is treated as a timeout. This is done to
	 * support nested mounts.
	 *
	 * The "retry" count specified by the user is the number of
	 * minutes to retry before giving up.
	 *
	 * Only the first error message will be displayed.
	 */
	retry_timeout.tv_sec = 3;
	retry_timeout.tv_usec = 0;
	total_timeout.tv_sec = 20;
	total_timeout.tv_usec = 0;
	timeout = time(NULL) + 60 * retry;
	prevt = 0;
	t = 30;
	val = 1;


			/* be careful not to use too many CPU cycles */
			if (t - prevt < 30)
				sleep(30);

			pm_mnt = get_mountport(&mount_server_addr,
					       mountprog,
					       mountvers,
					       proto,
					       mountport,
					       nfs_mount_version);

			/* contact the mount daemon via TCP */
			mount_server_addr.sin_port = htons(pm_mnt->pm_port);
			msock = RPC_ANYSOCK;

			switch (pm_mnt->pm_prot) {
			case IPPROTO_UDP:
				mclient = clntudp_create(&mount_server_addr,
							 pm_mnt->pm_prog,
							 pm_mnt->pm_vers,
							 retry_timeout,
							 &msock);
				if (mclient)
					break;
				mount_server_addr.sin_port =
					htons(pm_mnt->pm_port);
				msock = RPC_ANYSOCK;
			case IPPROTO_TCP:
				mclient = clnttcp_create(&mount_server_addr,
							 pm_mnt->pm_prog,
							 pm_mnt->pm_vers,
							 &msock, 0, 0);
				break;
			default:
				mclient = 0;
			}

			if (mclient) {
				/* try to mount hostname:dirname */
				mclient->cl_auth = authunix_create_default();

				/* make pointers in xdr_mountres3 NULL so
				 * that xdr_array allocates memory for us
				 */
				memset(&status, 0, sizeof(status));

				log_message("nfsmount: doing client call in nfs version: %ld", pm_mnt->pm_vers);
				if (pm_mnt->pm_vers == 3)
					clnt_stat = clnt_call(mclient,
						     MOUNTPROC3_MNT,
						     (xdrproc_t) xdr_dirpath,
						     (caddr_t) &dirname,
						     (xdrproc_t) xdr_mountres3,
						     (caddr_t) &status,
						     total_timeout);
				else
					clnt_stat = clnt_call(mclient,
						     MOUNTPROC_MNT,
						     (xdrproc_t) xdr_dirpath,
						     (caddr_t) &dirname,
						     (xdrproc_t) xdr_fhstatus,
						     (caddr_t) &status,
						     total_timeout);

				if (clnt_stat == RPC_SUCCESS)
                                        goto succeeded;

                                if (prevt == 0)
                                        log_message("could not call server: probably protocol or version error");
                                auth_destroy(mclient->cl_auth);
                                clnt_destroy(mclient);
                                mclient = 0;
                                close(msock);
			} else {
                                log_message("could not create rpc client: host probably not found or NFS server is down");
			}
			prevt = t;

		        goto fail;

 succeeded:
	nfsvers = (pm_mnt->pm_vers < 2) ? 2 : pm_mnt->pm_vers;

	if (nfsvers == 2) {
		if (status.nfsv2.fhs_status != 0) {
			log_message("nfsmount: %s:%s failed, reason given by server: %s",
                                    hostname, dirname, nfs_strerror(status.nfsv2.fhs_status));
			goto fail;
		}
		memcpy(data.root.data,
		       (char *) status.nfsv2.fhstatus_u.fhs_fhandle,
		       NFS_FHSIZE);
#if NFS_MOUNT_VERSION >= 4
		data.root.size = NFS_FHSIZE;
		memcpy(data.old_root.data,
		       (char *) status.nfsv2.fhstatus_u.fhs_fhandle,
		       NFS_FHSIZE);
#endif
	} else {
#if NFS_MOUNT_VERSION >= 4
		fhandle3 *fhandle;
		if (status.nfsv3.fhs_status != 0) {
			log_message("nfsmount: %s:%s failed, reason given by server: %s",
                                    hostname, dirname, nfs_strerror(status.nfsv3.fhs_status));
			goto fail;
		}
		fhandle = &status.nfsv3.mountres3_u.mountinfo.fhandle;
		memset(data.old_root.data, 0, NFS_FHSIZE);
		memset(&data.root, 0, sizeof(data.root));
		data.root.size = fhandle->fhandle3_len;
		memcpy(data.root.data,
		       (char *) fhandle->fhandle3_val,
		       fhandle->fhandle3_len);

		data.flags |= NFS_MOUNT_VER3;
#endif
	}

	/* create nfs socket for kernel */

	if (tcp) {
		if (nfs_mount_version < 3) {
	     		log_message("NFS over TCP is not supported.");
			goto fail;
		}
		fsock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	} else
		fsock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (fsock < 0) {
		log_perror("nfs socket");
		goto fail;
	}
	if (bindresvport(fsock, 0) < 0) {
		log_perror("nfs bindresvport");
		goto fail;
	}
	if (port == 0) {
		server_addr.sin_port = PMAPPORT;
		port = pmap_getport(&server_addr, nfsprog, nfsvers,
				    tcp ? IPPROTO_TCP : IPPROTO_UDP);
#if 1
		/* Here we check to see if user is mounting with the
		 * tcp option.  If so, and if the portmap returns a
		 * '0' for port (service unavailable), we then notify
		 * the user, and retry with udp.
		 */
		if (port == 0 && tcp == 1) {
			log_message("NFS server reported TCP not available, retrying with UDP...");
			tcp = 0;
			goto retry_mount;
		}
#endif

		if (port == 0)
			port = NFS_PORT;
#ifdef NFS_MOUNT_DEBUG
		else
			log_message("used portmapper to find NFS port");
#endif
	}
#ifdef NFS_MOUNT_DEBUG
	log_message("using port %d for nfs deamon", port);
#endif
	server_addr.sin_port = htons(port);
	/*
	 * connect() the socket for kernels 1.3.10 and below only,
	 * to avoid problems with multihomed hosts.
	 * --Swen
	 */
	if (linux_version_code() <= 66314
	    && connect(fsock, (struct sockaddr *) &server_addr,
		       sizeof (server_addr)) < 0) {
		log_perror("nfs connect");
		goto fail;
	}

	/* prepare data structure for kernel */

	data.fd = fsock;
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
	return retval;
}	

/*
 * We need to translate between nfs status return values and
 * the local errno values which may not be the same.
 *
 * Andreas Schwab <schwab@LS5.informatik.uni-dortmund.de>: change errno:
 * "after #include <errno.h> the symbol errno is reserved for any use,
 *  it cannot even be used as a struct tag or field name".
 */

#ifndef EDQUOT
#define EDQUOT	ENOSPC
#endif

static struct {
	enum nfsstat stat;
	int errnum;
} nfs_errtbl[] = {
	{ NFS_OK,		0		},
	{ NFSERR_PERM,		EPERM		},
	{ NFSERR_NOENT,		ENOENT		},
	{ NFSERR_IO,		EIO		},
	{ NFSERR_NXIO,		ENXIO		},
	{ NFSERR_ACCES,		EACCES		},
	{ NFSERR_EXIST,		EEXIST		},
	{ NFSERR_NODEV,		ENODEV		},
	{ NFSERR_NOTDIR,	ENOTDIR		},
	{ NFSERR_ISDIR,		EISDIR		},
#ifdef NFSERR_INVAL
	{ NFSERR_INVAL,		EINVAL		},	/* that Sun forgot */
#endif
	{ NFSERR_FBIG,		EFBIG		},
	{ NFSERR_NOSPC,		ENOSPC		},
	{ NFSERR_ROFS,		EROFS		},
	{ NFSERR_NAMETOOLONG,	ENAMETOOLONG	},
	{ NFSERR_NOTEMPTY,	ENOTEMPTY	},
	{ NFSERR_DQUOT,		EDQUOT		},
	{ NFSERR_STALE,		ESTALE		},
#ifdef EWFLUSH
	{ NFSERR_WFLUSH,	EWFLUSH		},
#endif
	/* Throw in some NFSv3 values for even more fun (HP returns these) */
	{ 71,			EREMOTE		},

	{ -1,			EIO		}
};

static char *nfs_strerror(int stat)
{
	int i;
	static char buf[256];

	for (i = 0; nfs_errtbl[i].stat != (unsigned)-1; i++) {
		if (nfs_errtbl[i].stat == (unsigned)stat)
			return strerror(nfs_errtbl[i].errnum);
	}
	sprintf(buf, "unknown nfs status return value: %d", stat);
	return buf;
}

