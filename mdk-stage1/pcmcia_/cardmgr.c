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
 *
 * Code comes from /anonymous@projects.sourceforge.net:/pub/pcmcia-cs/pcmcia-cs-3.1.29.tar.bz2
 *
 *   Licence of this code follows:
 *
 */
/*======================================================================

    PCMCIA Card Manager daemon

    cardmgr.c 1.161 2001/08/24 12:19:19

    The contents of this file are subject to the Mozilla Public
    License Version 1.1 (the "License"); you may not use this file
    except in compliance with the License. You may obtain a copy of
    the License at http://www.mozilla.org/MPL/

    Software distributed under the License is distributed on an "AS
    IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
    implied. See the License for the specific language governing
    rights and limitations under the License.

    The initial developer of the original code is David A. Hinds
    <dahinds@users.sourceforge.net>.  Portions created by David A. Hinds
    are Copyright (C) 1999 David A. Hinds.  All Rights Reserved.

    Alternatively, the contents of this file may be used under the
    terms of the GNU General Public License version 2 (the "GPL"), in
    which case the provisions of the GPL are applicable instead of the
    above.  If you wish to allow the use of your version of this file
    only under the terms of the GPL and not to allow others to use
    your version of this file under the MPL, indicate your decision
    by deleting the provisions above and replace them with the notice
    and other provisions required by the GPL.  If you do not delete
    the provisions above, a recipient may use your version of this
    file under either the MPL or the GPL.
    
======================================================================*/

#ifndef __linux__
#include <pcmcia/u_compat.h>
#endif

#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
//mdk-stage1// #include <syslog.h>
//mdk-stage1// #include <getopt.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/file.h>

#include <pcmcia_/version.h>
//mdk-stage1// #include <pcmcia/config.h>
#include <pcmcia_/cs_types.h>
#include <pcmcia_/cs.h>
#include <pcmcia_/cistpl.h>
#include <pcmcia_/ds.h>

#include "cardmgr.h"

#include "../log.h"
#include "modules.h"
#include "pcmcia.h"

/*====================================================================*/

typedef struct socket_info_t {
    int			fd;
    int			state;
    card_info_t		*card;
    bind_info_t		*bind[MAX_BINDINGS];
    mtd_ident_t		*mtd[2*CISTPL_MAX_DEVICES];
} socket_info_t;

#define SOCKET_PRESENT	0x01
#define SOCKET_READY	0x02
#define SOCKET_HOTPLUG	0x04

/* Linked list of resource adjustments */
struct adjust_list_t *root_adjust = NULL;

/* Linked list of device definitions */
struct device_info_t *root_device = NULL;

/* Special pointer to "anonymous" card definition */
struct card_info_t *blank_card = NULL;

/* Linked list of card definitions */
struct card_info_t *root_card = NULL;

/* Linked list of function definitions */
struct card_info_t *root_func = NULL;

/* Linked list of MTD definitions */
struct mtd_ident_t *root_mtd = NULL;

/* Default MTD */
struct mtd_ident_t *default_mtd = NULL;

static int sockets;
static struct socket_info_t socket[MAX_SOCKS];

/* Default path for config file, device scripts */
#ifdef ETC
static char *configpath = ETC;
#else
static char *configpath = "/etc/pcmcia";
#endif

/* Default path for pid file */
//mdk-stage1// static char *pidfile = "/var/run/cardmgr.pid";

#ifdef __linux__
/* Default path for finding modules */
//mdk-stage1// static char *modpath = NULL;
#endif

/* Default path for socket info table */
static char *stabfile;

/* If set, don't generate beeps when cards are inserted */
//mdk-stage1// static int be_quiet = 0;

/* If set, use modprobe instead of insmod */
//mdk-stage1// static int do_modprobe = 0;

/* If set, configure already inserted cards, then exit */
//mdk-stage1// static int one_pass = 0;

/* Extra message logging? */
//mdk-stage1// static int verbose = 0;

/*====================================================================*/

#ifdef __linux__

static int major = 0;

static int lookup_dev(char *name)
{
    FILE *f;
    int n;
    char s[32], t[32];
    
    f = fopen("/proc/devices", "r");
    if (f == NULL)
	return -errno;
    while (fgets(s, 32, f) != NULL) {
	if (sscanf(s, "%d %s", &n, t) == 2)
	    if (strcmp(name, t) == 0)
		break;
    }
    fclose(f);
    if (strcmp(name, t) == 0)
	return n;
    else
	return -ENODEV;
}

int open_dev(dev_t dev, int mode)
{
    char * fn = "/tmp/cardmgr_tmp";
    int fd;

    unlink(fn);
	if (mknod(fn, mode, dev) != 0)
		return -1;
    fd = open(fn, (mode&S_IWRITE)?O_RDWR:O_RDONLY);
    if (fd < 0)
	fd = open(fn, O_NONBLOCK|((mode&S_IWRITE)?O_RDWR:O_RDONLY));
    unlink(fn);
    return fd;
}

#endif /* __linux__ */

int open_sock(int sock, int mode)
{
#ifdef __linux__
    dev_t dev = (major<<8)+sock;
    return open_dev(dev, mode);
#endif
#ifdef __BEOS__
    int fd;
    char fn[B_OS_NAME_LENGTH];
    sprintf(fn, "/dev/pcmcia/sock%d", sock);
    return open(fn, (mode & S_IWRITE) ? O_RDWR: O_RDONLY);
#endif
}

/*======================================================================

    xlate_scsi_name() is a sort-of-hack used to deduce the minor
    device numbers of SCSI devices, from the information available to
    the low-level driver.
    
======================================================================*/

#ifdef __linux__

#include <linux/major.h>
#include <scsi/scsi.h>
//mdk-stage1// #define VERSION(v,p,s) (((v)<<16)+(p<<8)+s)
//mdk-stage1// #if (LINUX_VERSION_CODE < VERSION(2,1,126))
//mdk-stage1// #define SCSI_DISK0_MAJOR SCSI_DISK_MAJOR
//mdk-stage1// #endif

static int xlate_scsi_name(bind_info_t *bind)
{
    int i, fd, mode, minor;
    u_long arg[2], id1, id2;

    id1 = strtol(bind->name+3, NULL, 16);
    if ((bind->major == SCSI_DISK0_MAJOR) ||
	(bind->major == SCSI_CDROM_MAJOR))
	mode = S_IREAD|S_IFBLK;
    else
	mode = S_IREAD|S_IFCHR;
    
    for (i = 0; i < 16; i++) {
	minor = (bind->major == SCSI_DISK0_MAJOR) ? (i<<4) : i;
	fd = open_dev((bind->major<<8)+minor, mode);
	if (fd < 0)
	    continue;
	if (ioctl(fd, SCSI_IOCTL_GET_IDLUN, arg) == 0) {
	    id2 = (arg[0]&0x0f) + ((arg[0]>>4)&0xf0) +
		((arg[0]>>8)&0xf00) + ((arg[0]>>12)&0xf000);
	    if (id1 == id2) {
		close(fd);
		switch (bind->major) {
		case SCSI_DISK0_MAJOR:
		case SCSI_GENERIC_MAJOR:
		    sprintf(bind->name+2, "%c", 'a'+i); break;
		case SCSI_CDROM_MAJOR:
		    sprintf(bind->name, "scd%d", i); break;
		case SCSI_TAPE_MAJOR:
		    sprintf(bind->name+2, "%d", i); break;
		}
		bind->minor = minor;
		return 0;
	    }
	}
	close(fd);
    }
    return -1;
}
#endif

/*====================================================================*/

#define BEEP_TIME 150
#define BEEP_OK   1000
#define BEEP_WARN 2000
#define BEEP_ERR  4000

#ifdef __linux__

//mdk-stage1// #include <sys/kd.h>
//mdk-stage1// 
static void beep(unsigned int ms, unsigned int freq)
{
//mdk-stage1//     int fd, arg;
//mdk-stage1// 
//mdk-stage1//     if (be_quiet)
//mdk-stage1// 	return;
//mdk-stage1//     fd = open("/dev/console", O_RDWR);
//mdk-stage1//     if (fd < 0)
//mdk-stage1// 	return;
//mdk-stage1//     arg = (ms << 16) | freq;
//mdk-stage1//     ioctl(fd, KDMKTONE, arg);
//mdk-stage1//     close(fd);
//mdk-stage1//     usleep(ms*1000);
}

#endif /* __linux__ */

#ifdef __BEOS__
static void beep(unsigned int ms, unsigned int freq)
{
    if (!be_quiet) system("/bin/beep");
}
#endif

/*====================================================================*/

//mdk-stage1// static void write_pid(void)
//mdk-stage1// {
//mdk-stage1//     FILE *f;
//mdk-stage1//     f = fopen(pidfile, "w");
//mdk-stage1//     if (f == NULL)
//mdk-stage1// 	syslog(LOG_WARNING, "could not open %s: %m", pidfile);
//mdk-stage1//     else {
//mdk-stage1// 	fprintf(f, "%d\n", getpid());
//mdk-stage1// 	fclose(f);
//mdk-stage1//     }
//mdk-stage1// }

static void write_stab(void)
{
    int i, j, k;
    FILE *f;
    socket_info_t *s;
    bind_info_t *bind;

    f = fopen(stabfile, "w");
    if (f == NULL) {
	log_message("CM: fopen(stabfile) failed: %m");
	return;
    }
#ifndef __BEOS__
    if (flock(fileno(f), LOCK_EX) != 0) {
	log_message("CM: flock(stabfile) failed: %m");
	return;
    }
#endif
    for (i = 0; i < sockets; i++) {
	s = &socket[i];
	fprintf(f, "Socket %d: ", i);
	if (!(s->state & SOCKET_PRESENT)) {
	    fprintf(f, "empty\n");
	} else if (s->state & SOCKET_HOTPLUG) {
	    fprintf(f, "CardBus hotplug device\n");
	} else if (!s->card) {
	    fprintf(f, "unsupported card\n");
	} else {
	    fprintf(f, "%s\n", s->card->name);
	    for (j = 0; j < s->card->bindings; j++)
		for (k = 0, bind = s->bind[j];
		     bind != NULL;
		     k++, bind = bind->next) {
		    char *class = s->card->device[j]->class;
		    fprintf(f, "%d\t%s\t%s\t%d\t%s",
			    i, (class ? class : "none"),
			    bind->dev_info, k, bind->name);
		    if (bind->major)
			fprintf(f, "\t%d\t%d\n",
				bind->major, bind->minor);
		    else
			fputc('\n', f);
		}
	}
    }
    fflush(f);
#ifndef __BEOS__
    flock(fileno(f), LOCK_UN);
#endif
    fclose(f);
}

/*====================================================================*/

static int get_tuple(int ns, cisdata_t code, ds_ioctl_arg_t *arg)
{
    socket_info_t *s = &socket[ns];
    
    arg->tuple.DesiredTuple = code;
    arg->tuple.Attributes = 0;
    if (ioctl(s->fd, DS_GET_FIRST_TUPLE, arg) != 0)
	return -1;
    arg->tuple.TupleOffset = 0;
    if (ioctl(s->fd, DS_GET_TUPLE_DATA, arg) != 0) {
	log_message("CM: error reading CIS data on socket %d: %m", ns);
	return -1;
    }
    if (ioctl(s->fd, DS_PARSE_TUPLE, arg) != 0) {
	log_message("CM: error parsing CIS on socket %d: %m", ns);
	return -1;
    }
    return 0;
}

/*======================================================================

    Code to fetch a 2.4 kernel's hot plug PCI driver list

    This is distasteful but is the best I could come up with.

======================================================================*/

#ifdef __linux__

typedef struct pci_id {
    u_short vendor, device;
    struct pci_id *next;
} pci_id_t;

static int get_pci_id(int ns, pci_id_t *id)
{
    socket_info_t *s = &socket[ns];
    config_info_t config;

    config.Function = config.ConfigBase = 0;
    if ((ioctl(s->fd, DS_GET_CONFIGURATION_INFO, &config) != 0) ||
	(config.IntType != INT_CARDBUS) || !config.ConfigBase)
	return 0;
    id->vendor = config.ConfigBase & 0xffff;
    id->device = config.ConfigBase >> 16;
    return 1;
}

#endif /* __linux__ */

/*====================================================================*/

//mdk-stage1// static void log_card_info(cistpl_vers_1_t *vers,
//mdk-stage1// 			  cistpl_manfid_t *manfid,
//mdk-stage1// 			  cistpl_funcid_t *funcid,
//mdk-stage1// 			  pci_id_t *pci_id)
//mdk-stage1// {
//mdk-stage1//     char v[256] = "";
//mdk-stage1//     int i;
//mdk-stage1//     static char *fn[] = {
//mdk-stage1// 	"multi", "memory", "serial", "parallel", "fixed disk",
//mdk-stage1// 	"video", "network", "AIMS", "SCSI"
//mdk-stage1//     };
//mdk-stage1//     
//mdk-stage1//     if (vers) {
//mdk-stage1// 	for (i = 0; i < vers->ns; i++)
//mdk-stage1// 	    sprintf(v+strlen(v), "%s\"%s\"",
//mdk-stage1// 		    (i>0) ? ", " : "", vers->str+vers->ofs[i]);
//mdk-stage1// 	syslog(LOG_INFO, "  product info: %s", v);
//mdk-stage1//     } else {
//mdk-stage1// 	syslog(LOG_INFO, "  no product info available");
//mdk-stage1//     }
//mdk-stage1//     *v = '\0';
//mdk-stage1//     if (manfid->manf != 0)
//mdk-stage1// 	sprintf(v, "  manfid: 0x%04x, 0x%04x",
//mdk-stage1// 		manfid->manf, manfid->card);
//mdk-stage1//     if (funcid->func != 0xff)
//mdk-stage1// 	sprintf(v+strlen(v), "  function: %d (%s)", funcid->func,
//mdk-stage1// 		fn[funcid->func]);
//mdk-stage1//     if (strlen(v) > 0) syslog(LOG_INFO, "%s", v);
//mdk-stage1//     if (pci_id->vendor != 0)
//mdk-stage1// 	syslog(LOG_INFO, "  PCI id: 0x%04x, 0x%04x",
//mdk-stage1// 	       pci_id->vendor, pci_id->device);
//mdk-stage1// }

static card_info_t *lookup_card(int ns)
{
    socket_info_t *s = &socket[ns];
    card_info_t *card = NULL;
    ds_ioctl_arg_t arg;
    cistpl_vers_1_t *vers = NULL;
    cistpl_manfid_t manfid = { 0, 0 };
    pci_id_t pci_id = { 0, 0 };
    cistpl_funcid_t funcid = { 0xff, 0xff };
    cs_status_t status;
    int i, ret, has_cis = 0;

    /* Do we have a CIS structure? */
    ret = ioctl(s->fd, DS_VALIDATE_CIS, &arg);
    has_cis = ((ret == 0) && (arg.cisinfo.Chains > 0));
    
    /* Try to read VERS_1, MANFID tuples */
    if (has_cis) {
	/* rule of thumb: cards with no FUNCID, but with common memory
	   device geometry information, are probably memory cards */
	if (get_tuple(ns, CISTPL_FUNCID, &arg) == 0)
	    memcpy(&funcid, &arg.tuple_parse.parse.funcid,
		   sizeof(funcid));
	else if (get_tuple(ns, CISTPL_DEVICE_GEO, &arg) == 0)
	    funcid.func = CISTPL_FUNCID_MEMORY;
	if (get_tuple(ns, CISTPL_MANFID, &arg) == 0)
	    memcpy(&manfid, &arg.tuple_parse.parse.manfid,
		   sizeof(manfid));
	if (get_tuple(ns, CISTPL_VERS_1, &arg) == 0)
	    vers = &arg.tuple_parse.parse.version_1;

	for (card = root_card; card; card = card->next) {

	    if (card->ident_type &
		~(VERS_1_IDENT|MANFID_IDENT|TUPLE_IDENT))
		continue;

	    if (card->ident_type & VERS_1_IDENT) {
		if (vers == NULL)
		    continue;
		for (i = 0; i < card->id.vers.ns; i++) {
		    if (strcmp(card->id.vers.pi[i], "*") == 0)
			continue;
		    if (i >= vers->ns)
			break;
		    if (strcmp(card->id.vers.pi[i],
			       vers->str+vers->ofs[i]) != 0)
			break;
		}
		if (i < card->id.vers.ns)
		    continue;
	    }
	    
	    if (card->ident_type & MANFID_IDENT) {
		if ((manfid.manf != card->manfid.manf) ||
		    (manfid.card != card->manfid.card))
		    continue;
	    }
		
	    if (card->ident_type & TUPLE_IDENT) {
		arg.tuple.DesiredTuple = card->id.tuple.code;
		arg.tuple.Attributes = 0;
		ret = ioctl(s->fd, DS_GET_FIRST_TUPLE, &arg);
		if (ret != 0) continue;
		arg.tuple.TupleOffset = card->id.tuple.ofs;
		ret = ioctl(s->fd, DS_GET_TUPLE_DATA, &arg);
		if (ret != 0) continue;
		if (strncmp((char *)arg.tuple_parse.data,
			    card->id.tuple.info,
			    strlen(card->id.tuple.info)) != 0)
		    continue;
	    }

	    break; /* we have a match */
	}
    }

    /* Check PCI vendor/device info */
    status.Function = 0;
    ioctl(s->fd, DS_GET_STATUS, &status);
    if (status.CardState & CS_EVENT_CB_DETECT) {
	if (get_pci_id(ns, &pci_id)) {
	    if (!card) {
		for (card = root_card; card; card = card->next)
		    if ((card->ident_type == PCI_IDENT) &&
			(pci_id.vendor == card->manfid.manf) &&
			(pci_id.device == card->manfid.card))
			break;
	    }
	} else {
	    /* this is a 2.4 kernel; hotplug handles these cards */
	    s->state |= SOCKET_HOTPLUG;
	    log_message("CM: socket %d: CardBus hotplug device", ns);
	    //beep(BEEP_TIME, BEEP_OK);
	    return NULL;
	}
    }

    /* Try for a FUNCID match */
    if (!card && (funcid.func != 0xff)) {
	for (card = root_func; card; card = card->next)
	    if (card->id.func.funcid == funcid.func)
		break;
    }

    if (card) {
	log_message("CM: socket %d: %s", ns, card->name);
 	beep(BEEP_TIME, BEEP_OK);
//mdk-stage1// 	if (verbose) log_card_info(vers, &manfid, &funcid, &pci_id);
	return card;
    }

    if (!blank_card || (status.CardState & CS_EVENT_CB_DETECT) ||
	manfid.manf || manfid.card || pci_id.vendor || vers) {
	log_message("CM: unsupported card in socket %d", ns);
//mdk-stage1// 	if (one_pass) return NULL;
	beep(BEEP_TIME, BEEP_ERR);
//mdk-stage1// 	log_card_info(vers, &manfid, &funcid, &pci_id);
	return NULL;
    } else {
	card = blank_card;
	log_message("CM: socket %d: %s", ns, card->name);
 	beep(BEEP_TIME, BEEP_WARN);
	return card;
    }
}

/*====================================================================*/

static int load_config(void)
{
    if (chdir(configpath) != 0) {
	    log_message("CM: chdir to %s failed: %m", configpath);
	    return -1;
    }
    if (parse_configfile("config") != 0) {
	    log_message("CM: parsing of config file failed: %m");
	    return -1;
    }
    if (root_device == NULL)
		log_message("CM: no device drivers defined");
    if ((root_card == NULL) && (root_func == NULL))
		log_message("CM: no cards defined");
    return 0;
}

//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static void free_card(card_info_t *card)
//mdk-stage1// {
//mdk-stage1//     if (card && (--card->refs == 0)) {
//mdk-stage1// 	int i;
//mdk-stage1// 	free(card->name);
//mdk-stage1// 	switch(card->ident_type) {
//mdk-stage1// 	case VERS_1_IDENT:
//mdk-stage1// 	    for (i = 0; i < card->id.vers.ns; i++)
//mdk-stage1// 		free(card->id.vers.pi[i]);
//mdk-stage1// 	break;
//mdk-stage1// 	case TUPLE_IDENT:
//mdk-stage1// 	    free(card->id.tuple.info);
//mdk-stage1// 	    break;
//mdk-stage1// 	default:
//mdk-stage1// 	    break;
//mdk-stage1// 	}
//mdk-stage1// 	free(card);
//mdk-stage1//     }
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// static void free_device(device_info_t *dev)
//mdk-stage1// {
//mdk-stage1//     if (dev && (--dev->refs == 0)) {
//mdk-stage1// 	int i;
//mdk-stage1// 	for (i = 0; i < dev->modules; i++) {
//mdk-stage1// 	    free(dev->module[i]);
//mdk-stage1// 	    if (dev->opts[i]) free(dev->opts[i]);
//mdk-stage1// 	}
//mdk-stage1// 	if (dev->class) free(dev->class);
//mdk-stage1// 	free(dev);
//mdk-stage1//     }
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// static void free_mtd(mtd_ident_t *mtd)
//mdk-stage1// {
//mdk-stage1//     if (mtd && (--mtd->refs == 0)) {
//mdk-stage1// 	free(mtd->name);
//mdk-stage1// 	free(mtd->module);
//mdk-stage1// 	free(mtd);
//mdk-stage1//     }
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// static void free_config(void)
//mdk-stage1// {
//mdk-stage1//     while (root_adjust != NULL) {
//mdk-stage1// 	adjust_list_t *adj = root_adjust;
//mdk-stage1// 	root_adjust = root_adjust->next;
//mdk-stage1// 	free(adj);
//mdk-stage1//     }
//mdk-stage1//     
//mdk-stage1//     while (root_device != NULL) {
//mdk-stage1// 	device_info_t *dev = root_device;
//mdk-stage1// 	root_device = root_device->next;
//mdk-stage1// 	free_device(dev);
//mdk-stage1//     }
//mdk-stage1// 
//mdk-stage1//     while (root_card != NULL) {
//mdk-stage1// 	card_info_t *card = root_card;
//mdk-stage1// 	root_card = root_card->next;
//mdk-stage1// 	free_card(card);
//mdk-stage1//     }
//mdk-stage1//     
//mdk-stage1//     while (root_func != NULL) {
//mdk-stage1// 	card_info_t *card = root_func;
//mdk-stage1// 	root_func = root_func->next;
//mdk-stage1// 	free_card(card);
//mdk-stage1//     }
//mdk-stage1//     blank_card = NULL;
//mdk-stage1//     
//mdk-stage1//     while (root_mtd != NULL) {
//mdk-stage1// 	mtd_ident_t *mtd = root_mtd;
//mdk-stage1// 	root_mtd = root_mtd->next;
//mdk-stage1// 	free_mtd(mtd);
//mdk-stage1//     }
//mdk-stage1//     default_mtd = NULL;
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static int execute(char *msg, char *cmd)
//mdk-stage1// {
//mdk-stage1//     int ret;
//mdk-stage1//     FILE *f;
//mdk-stage1//     char line[256];
//mdk-stage1// 
//mdk-stage1//     syslog(LOG_INFO, "executing: '%s'", cmd);
//mdk-stage1//     strcat(cmd, " 2>&1");
//mdk-stage1//     f = popen(cmd, "r");
//mdk-stage1//     while (fgets(line, 255, f)) {
//mdk-stage1// 	line[strlen(line)-1] = '\0';
//mdk-stage1// 	syslog(LOG_INFO, "+ %s", line);
//mdk-stage1//     }
//mdk-stage1//     ret = pclose(f);
//mdk-stage1//     if (WIFEXITED(ret)) {
//mdk-stage1// 	if (WEXITSTATUS(ret))
//mdk-stage1// 	    syslog(LOG_INFO, "%s exited with status %d",
//mdk-stage1// 		   msg, WEXITSTATUS(ret));
//mdk-stage1// 	return WEXITSTATUS(ret);
//mdk-stage1//     } else
//mdk-stage1// 	syslog(LOG_INFO, "%s exited on signal %d",
//mdk-stage1// 	       msg, WTERMSIG(ret));
//mdk-stage1//     return -1;
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static int execute_on_dev(char *action, char *class, char *dev)
//mdk-stage1// {
//mdk-stage1//     /* Fixed length strings are ok here */
//mdk-stage1//     char msg[128], cmd[128];
//mdk-stage1// 
//mdk-stage1//     sprintf(msg, "%s cmd", action);
//mdk-stage1//     sprintf(cmd, "./%s %s %s", class, action, dev);
//mdk-stage1//     return execute(msg, cmd);
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// static int execute_on_all(char *cmd, char *class, int sn, int fn)
//mdk-stage1// {
//mdk-stage1//     socket_info_t *s = &socket[sn];
//mdk-stage1//     bind_info_t *bind;
//mdk-stage1//     int ret = 0;
//mdk-stage1//     for (bind = s->bind[fn]; bind != NULL; bind = bind->next)
//mdk-stage1// 	if (bind->name[0] && (bind->name[2] != '#'))
//mdk-stage1// 	    ret |= execute_on_dev(cmd, class, bind->name);
//mdk-stage1//     return ret;
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// #ifdef __linux__
//mdk-stage1// 
//mdk-stage1// typedef struct module_list_t {
//mdk-stage1//     char *mod;
//mdk-stage1//     int usage;
//mdk-stage1//     struct module_list_t *next;
//mdk-stage1// } module_list_t;
//mdk-stage1// 
//mdk-stage1// static module_list_t *module_list = NULL;
//mdk-stage1// 
//mdk-stage1// static int try_insmod(char *mod, char *opts)
//mdk-stage1// {
//mdk-stage1//     char *cmd = malloc(strlen(mod) + strlen(modpath) +
//mdk-stage1// 		       (opts ? strlen(opts) : 0) + 30);
//mdk-stage1//     int ret;
//mdk-stage1// 
//mdk-stage1//     strcpy(cmd, "insmod ");
//mdk-stage1//     if (strchr(mod, '/') != NULL)
//mdk-stage1// 	sprintf(cmd+7, "%s/%s.o", modpath, mod);
//mdk-stage1//     else
//mdk-stage1// 	sprintf(cmd+7, "%s/pcmcia/%s.o", modpath, mod);
//mdk-stage1//     if (access(cmd+7, R_OK) != 0) {
//mdk-stage1// 	syslog(LOG_INFO, "module %s not available", cmd+7);
//mdk-stage1// 	free(cmd);
//mdk-stage1// 	return -1;
//mdk-stage1//     }
//mdk-stage1//     if (opts) {
//mdk-stage1// 	strcat(cmd, " ");
//mdk-stage1// 	strcat(cmd, opts);
//mdk-stage1//     }
//mdk-stage1//     ret = execute("insmod", cmd);
//mdk-stage1//     free(cmd);
//mdk-stage1//     return ret;
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// static int try_modprobe(char *mod, char *opts)
//mdk-stage1// {
//mdk-stage1//     char *cmd = malloc(strlen(mod) + (opts ? strlen(opts) : 0) + 20);
//mdk-stage1//     char *s = strrchr(mod, '/');
//mdk-stage1//     int ret;
//mdk-stage1// 
//mdk-stage1//     sprintf(cmd, "modprobe %s", (s) ? s+1 : mod);
//mdk-stage1//     if (opts) {
//mdk-stage1// 	strcat(cmd, " ");
//mdk-stage1// 	strcat(cmd, opts);
//mdk-stage1//     }
//mdk-stage1//     ret = execute("modprobe", cmd);
//mdk-stage1//     free(cmd);
//mdk-stage1//     return ret;
//mdk-stage1// }

static void install_module(char *mod, char *opts)
{
	my_insmod(mod, ANY_DRIVER_TYPE, opts);
//mdk-stage1//     module_list_t *ml;
//mdk-stage1// 
//mdk-stage1//     for (ml = module_list; ml != NULL; ml = ml->next)
//mdk-stage1// 	if (strcmp(mod, ml->mod) == 0) break;
//mdk-stage1//     if (ml == NULL) {
//mdk-stage1// 	ml = (module_list_t *)malloc(sizeof(struct module_list_t));
//mdk-stage1// 	ml->mod = mod;
//mdk-stage1// 	ml->usage = 0;
//mdk-stage1// 	ml->next = module_list;
//mdk-stage1// 	module_list = ml;
//mdk-stage1//     }
//mdk-stage1//     ml->usage++;
//mdk-stage1//     if (ml->usage != 1)
//mdk-stage1// 	return;
//mdk-stage1// 
//mdk-stage1// #ifdef __linux__
//mdk-stage1//     if (access("/proc/bus/pccard/drivers", R_OK) == 0) {
//mdk-stage1// 	FILE *f = fopen("/proc/bus/pccard/drivers", "r");
//mdk-stage1// 	if (f) {
//mdk-stage1// 	    char a[61], s[33];
//mdk-stage1// 	    while (fgets(a, 60, f)) {
//mdk-stage1// 		int is_kernel;
//mdk-stage1// 		sscanf(a, "%s %d", s, &is_kernel);
//mdk-stage1// 		if (strcmp(s, mod) != 0) continue;
//mdk-stage1// 		/* If it isn't a module, we won't try to rmmod */
//mdk-stage1// 		ml->usage += is_kernel;
//mdk-stage1// 		fclose(f);
//mdk-stage1// 		return;
//mdk-stage1// 	    }
//mdk-stage1// 	    fclose(f);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1// #endif
//mdk-stage1// 
//mdk-stage1//     if (do_modprobe) {
//mdk-stage1// 	if (try_modprobe(mod, opts) != 0)
//mdk-stage1// 	    try_insmod(mod, opts);
//mdk-stage1//     } else {
//mdk-stage1// 	if (try_insmod(mod, opts) != 0)
//mdk-stage1// 	    try_modprobe(mod, opts);
//mdk-stage1//     }
}

//mdk-stage1// static void remove_module(char *mod)
//mdk-stage1// {
//mdk-stage1//     char *s, cmd[128];
//mdk-stage1//     module_list_t *ml;
//mdk-stage1// 
//mdk-stage1//     for (ml = module_list; ml != NULL; ml = ml->next)
//mdk-stage1// 	if (strcmp(mod, ml->mod) == 0) break;
//mdk-stage1//     if (ml != NULL) {
//mdk-stage1// 	ml->usage--;
//mdk-stage1// 	if (ml->usage == 0) {
//mdk-stage1// 	    /* Strip off leading path names */
//mdk-stage1// 	    s = strrchr(mod, '/');
//mdk-stage1// 	    s = (s) ? s+1 : mod;
//mdk-stage1// 	    sprintf(cmd, do_modprobe ? "modprobe -r %s" : "rmmod %s", s);
//mdk-stage1// 	    execute(do_modprobe ? "modprobe" : "rmmod", cmd);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// #endif /* __linux__ */
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// #ifdef __BEOS__
//mdk-stage1// 
//mdk-stage1// #define install_module(a,b)
//mdk-stage1// #define remove_module(a)
//mdk-stage1// 
//mdk-stage1// static void republish_driver(char *mod)
//mdk-stage1// {
//mdk-stage1//     int fd = open("/dev", O_RDWR);
//mdk-stage1//     write(fd, mod, strlen(mod));
//mdk-stage1//     close(fd);
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// #endif /* __BEOS__ */
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/

static mtd_ident_t *lookup_mtd(region_info_t *region)
{
    mtd_ident_t *mtd;
    int match = 0;
    
    for (mtd = root_mtd; mtd; mtd = mtd->next) {
	switch (mtd->mtd_type) {
	case JEDEC_MTD:
	    if ((mtd->jedec_mfr == region->JedecMfr) &&
		(mtd->jedec_info == region->JedecInfo)) {
		match = 1;
		break;
	    }
	case DTYPE_MTD:
	    break;
	default:
	    break;
	}
	if (match) break;
    }
    if (mtd)
	return mtd;
    else
	return default_mtd;
}

/*====================================================================*/

static void bind_mtd(int sn)
{
    socket_info_t *s = &socket[sn];
    region_info_t region;
    bind_info_t bind;
    mtd_info_t mtd_info;
    mtd_ident_t *mtd;
    int i, attr, ret, nr;

    nr = 0;
    for (attr = 0; attr < 2; attr++) {
	region.Attributes = attr;
	ret = ioctl(s->fd, DS_GET_FIRST_REGION, &region);
	while (ret == 0) {
	    mtd = lookup_mtd(&region);
	    if (mtd) {
		/* Have we seen this MTD before? */
		for (i = 0; i < nr; i++)
		    if (s->mtd[i] == mtd) break;
		if (i == nr) {
		    install_module(mtd->module, mtd->opts);
		    s->mtd[nr] = mtd;
		    mtd->refs++;
		    nr++;
		}
		log_message("CM: %s memory region at 0x%x: %s",
		       attr ? "Attribute" : "Common", region.CardOffset,
		       mtd->name);
		/* Bind MTD to this region */
		strcpy(mtd_info.dev_info, s->mtd[i]->module);
		mtd_info.Attributes = region.Attributes;
		mtd_info.CardOffset = region.CardOffset;
		if (ioctl(s->fd, DS_BIND_MTD, &mtd_info) != 0) {
		    log_message("CM: bind MTD '%s' to region at 0x%x failed: %m",
			   (char *)mtd_info.dev_info, region.CardOffset);
		}
	    }
	    ret = ioctl(s->fd, DS_GET_NEXT_REGION, &region);
	}
    }
    s->mtd[nr] = NULL;
    
    /* Now bind each unique MTD as a normal client of this socket */
    for (i = 0; i < nr; i++) {
	strcpy(bind.dev_info, s->mtd[i]->module);
	bind.function = 0;
	if (ioctl(s->fd, DS_BIND_REQUEST, &bind) != 0)
	    log_message("CM: bind MTD '%s' to socket %d failed: %m",
		   (char *)bind.dev_info, sn);
    }
}

/*====================================================================*/

static void update_cis(socket_info_t *s)
{
    cisdump_t cis;
    FILE *f = fopen(s->card->cis_file, "r");
    if (f == NULL)
	log_message("CM: could not open '%s': %m", s->card->cis_file);
    else {
	cis.Length = fread(cis.Data, 1, CISTPL_MAX_CIS_SIZE, f);
	fclose(f);
	if (ioctl(s->fd, DS_REPLACE_CIS, &cis) != 0)
	    log_message("CM: could not replace CIS: %m");
    }
}

/*====================================================================*/

static void do_insert(int sn)
{
    socket_info_t *s = &socket[sn];
    card_info_t *card;
    device_info_t **dev;
    bind_info_t *bind, **tail;
    int i, j, ret;

    /* Already identified? */
    if ((s->card != NULL) && (s->card != blank_card))
	return;

    log_message("CM: initializing socket %d", sn);
    card = lookup_card(sn);
    if (s->state & SOCKET_HOTPLUG) {
	write_stab();
	return;
    }
    /* Make sure we've learned something new before continuing */
    if (card == s->card)
	return;
    s->card = card;
    card->refs++;
    if (card->cis_file) update_cis(s);

    dev = card->device;

    /* Set up MTD's */
    for (i = 0; i < card->bindings; i++)
	if (dev[i]->needs_mtd)
	    break;
    if (i < card->bindings)
	bind_mtd(sn);

#ifdef __linux__
    /* Install kernel modules */
    for (i = 0; i < card->bindings; i++) {
	dev[i]->refs++;
	for (j = 0; j < dev[i]->modules; j++)
	    install_module(dev[i]->module[j], dev[i]->opts[j]);
    }
#endif
    
    /* Bind drivers by their dev_info identifiers */
    for (i = 0; i < card->bindings; i++) {
	bind = calloc(1, sizeof(bind_info_t));
	strcpy((char *)bind->dev_info, (char *)dev[i]->dev_info);
	if (strcmp(bind->dev_info, "cb_enabler") == 0)
	    bind->function = BIND_FN_ALL;
	else
	    bind->function = card->dev_fn[i];
	if (ioctl(s->fd, DS_BIND_REQUEST, bind) != 0) {
	    if (errno == EBUSY) {
		log_message("CM: '%s' already bound to socket %d",
		       (char *)bind->dev_info, sn);
	    } else {
		log_message("CM: bind '%s' to socket %d failed: %m",
		       (char *)bind->dev_info, sn);
		beep(BEEP_TIME, BEEP_ERR);
		write_stab();
		return;
	    }
	}

#ifdef __BEOS__
	republish_driver(dev[i]->module[0]);
#endif

	for (ret = j = 0; j < 10; j++) {
	    ret = ioctl(s->fd, DS_GET_DEVICE_INFO, bind);
	    if ((ret == 0) || (errno != EAGAIN))
		break;
	    usleep(100000);
	}
	if (ret != 0) {
	    log_message("CM: get dev info on socket %d failed: %m",
		   sn);
	    ioctl(s->fd, DS_UNBIND_REQUEST, bind);
	    beep(BEEP_TIME, BEEP_ERR);
	    write_stab();
	    return;
	}
	tail = &s->bind[i];
	while (ret == 0) {
	    bind_info_t *old;
#ifdef __linux__
	    if ((strlen(bind->name) > 3) && (bind->name[2] == '#'))
		xlate_scsi_name(bind);
#endif
	    old = *tail = bind; tail = (bind_info_t **)&bind->next;
	    bind = (bind_info_t *)malloc(sizeof(bind_info_t));
	    memcpy(bind, old, sizeof(bind_info_t));
	    ret = ioctl(s->fd, DS_GET_NEXT_DEVICE, bind);
	}
	*tail = NULL; free(bind);
	write_stab();
    }

//mdk-stage1//     /* Run "start" commands */
//mdk-stage1//     for (i = ret = 0; i < card->bindings; i++)
//mdk-stage1// 	if (dev[i]->class)
//mdk-stage1// 	    ret |= execute_on_all("start", dev[i]->class, sn, i);
//mdk-stage1//     beep(BEEP_TIME, (ret) ? BEEP_ERR : BEEP_OK);
    
}

//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static int do_check(int sn)
//mdk-stage1// {
//mdk-stage1//     socket_info_t *s = &socket[sn];
//mdk-stage1//     card_info_t *card;
//mdk-stage1//     device_info_t **dev;
//mdk-stage1//     int i, ret;
//mdk-stage1// 
//mdk-stage1//     card = s->card;
//mdk-stage1//     if (card == NULL)
//mdk-stage1// 	return 0;
//mdk-stage1//     
//mdk-stage1//     /* Run "check" commands */
//mdk-stage1//     dev = card->device;
//mdk-stage1//     for (i = 0; i < card->bindings; i++) {
//mdk-stage1// 	if (dev[i]->class) {
//mdk-stage1// 	    ret = execute_on_all("check", dev[i]->class, sn, i);
//mdk-stage1// 	    if (ret != 0)
//mdk-stage1// 		return CS_IN_USE;
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1//     return 0;
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static void do_remove(int sn)
//mdk-stage1// {
//mdk-stage1//     socket_info_t *s = &socket[sn];
//mdk-stage1//     card_info_t *card;
//mdk-stage1//     device_info_t **dev;
//mdk-stage1//     bind_info_t *bind;
//mdk-stage1//     int i, j;
//mdk-stage1// 
//mdk-stage1//     if (verbose) syslog(LOG_INFO, "shutting down socket %d", sn);
//mdk-stage1// 
//mdk-stage1//     card = s->card;
//mdk-stage1//     if (card == NULL)
//mdk-stage1// 	goto done;
//mdk-stage1// 
//mdk-stage1//     /* Run "stop" commands */
//mdk-stage1//     dev = card->device;
//mdk-stage1//     for (i = 0; i < card->bindings; i++) {
//mdk-stage1// 	if (dev[i]->class) {
//mdk-stage1// 	    execute_on_all("stop", dev[i]->class, sn, i);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1// 
//mdk-stage1//     /* unbind driver instances */
//mdk-stage1//     for (i = 0; i < card->bindings; i++) {
//mdk-stage1// 	if (s->bind[i]) {
//mdk-stage1// 	    if (ioctl(s->fd, DS_UNBIND_REQUEST, s->bind[i]) != 0)
//mdk-stage1// 		syslog(LOG_INFO, "unbind '%s' from socket %d failed: %m",
//mdk-stage1// 		       (char *)s->bind[i]->dev_info, sn);
//mdk-stage1// 	    while (s->bind[i]) {
//mdk-stage1// 		bind = s->bind[i];
//mdk-stage1// 		s->bind[i] = bind->next;
//mdk-stage1// 		free(bind);
//mdk-stage1// 	    }
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1//     for (i = 0; (s->mtd[i] != NULL); i++) {
//mdk-stage1// 	bind_info_t b;
//mdk-stage1// 	strcpy(b.dev_info, s->mtd[i]->module);
//mdk-stage1// 	b.function = 0;
//mdk-stage1// 	if (ioctl(s->fd, DS_UNBIND_REQUEST, &b) != 0)
//mdk-stage1// 	    syslog(LOG_INFO, "unbind MTD '%s' from socket %d failed: %m",
//mdk-stage1// 		   s->mtd[i]->module, sn);
//mdk-stage1//     }
//mdk-stage1// 
//mdk-stage1//     /* remove kernel modules in inverse order */
//mdk-stage1//     for (i = 0; i < card->bindings; i++) {
//mdk-stage1// 	for (j = dev[i]->modules-1; j >= 0; j--)
//mdk-stage1// 	    remove_module(dev[i]->module[j]);
//mdk-stage1// 	free_device(dev[i]);
//mdk-stage1//     }
//mdk-stage1//     /* Remove any MTD's bound to this socket */
//mdk-stage1//     for (i = 0; (s->mtd[i] != NULL); i++) {
//mdk-stage1// 	remove_module(s->mtd[i]->module);
//mdk-stage1// 	free_mtd(s->mtd[i]);
//mdk-stage1// 	s->mtd[i] = NULL;
//mdk-stage1//     }
//mdk-stage1// 
//mdk-stage1// done:
//mdk-stage1//     beep(BEEP_TIME, BEEP_OK);
//mdk-stage1//     free_card(card);
//mdk-stage1//     s->card = NULL;
//mdk-stage1//     write_stab();
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static void do_suspend(int sn)
//mdk-stage1// {
//mdk-stage1//     socket_info_t *s = &socket[sn];
//mdk-stage1//     card_info_t *card;
//mdk-stage1//     device_info_t **dev;
//mdk-stage1//     int i, ret;
//mdk-stage1//     
//mdk-stage1//     card = s->card;
//mdk-stage1//     if (card == NULL)
//mdk-stage1// 	return;
//mdk-stage1//     dev = card->device;
//mdk-stage1//     for (i = 0; i < card->bindings; i++) {
//mdk-stage1// 	if (dev[i]->class) {
//mdk-stage1// 	    ret = execute_on_all("suspend", dev[i]->class, sn, i);
//mdk-stage1// 	    if (ret != 0)
//mdk-stage1// 		beep(BEEP_TIME, BEEP_ERR);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static void do_resume(int sn)
//mdk-stage1// {
//mdk-stage1//     socket_info_t *s = &socket[sn];
//mdk-stage1//     card_info_t *card;
//mdk-stage1//     device_info_t **dev;
//mdk-stage1//     int i, ret;
//mdk-stage1//     
//mdk-stage1//     card = s->card;
//mdk-stage1//     if (card == NULL)
//mdk-stage1// 	return;
//mdk-stage1//     dev = card->device;
//mdk-stage1//     for (i = 0; i < card->bindings; i++) {
//mdk-stage1// 	if (dev[i]->class) {
//mdk-stage1// 	    ret = execute_on_all("resume", dev[i]->class, sn, i);
//mdk-stage1// 	    if (ret != 0)
//mdk-stage1// 		beep(BEEP_TIME, BEEP_ERR);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1// }

/*====================================================================*/

static void wait_for_pending(void)
{
    cs_status_t status;
    int i;
    status.Function = 0;
    for (;;) {
	usleep(100000);
	for (i = 0; i < sockets; i++)
	    if ((ioctl(socket[i].fd, DS_GET_STATUS, &status) == 0) &&
		(status.CardState & CS_EVENT_CARD_INSERTION))
		break;
	if (i == sockets) break;
    }
}

//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static void free_resources(void)
//mdk-stage1// {
//mdk-stage1//     adjust_list_t *al;
//mdk-stage1//     int fd = socket[0].fd;
//mdk-stage1// 
//mdk-stage1//     for (al = root_adjust; al; al = al->next) {
//mdk-stage1// 	if (al->adj.Action == ADD_MANAGED_RESOURCE) {
//mdk-stage1// 	    al->adj.Action = REMOVE_MANAGED_RESOURCE;
//mdk-stage1// 	    ioctl(fd, DS_ADJUST_RESOURCE_INFO, &al->adj);
//mdk-stage1// 	} else if ((al->adj.Action == REMOVE_MANAGED_RESOURCE) &&
//mdk-stage1// 		   (al->adj.Resource == RES_IRQ)) {
//mdk-stage1// 	    al->adj.Action = ADD_MANAGED_RESOURCE;
//mdk-stage1// 	    ioctl(fd, DS_ADJUST_RESOURCE_INFO, &al->adj);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1//     
//mdk-stage1// }

/*====================================================================*/

static void adjust_resources(void)
{
    adjust_list_t *al;
    int ret;
    char tmp[64];
    int fd = socket[0].fd;
    
    for (al = root_adjust; al; al = al->next) {
	ret = ioctl(fd, DS_ADJUST_RESOURCE_INFO, &al->adj);
	if (ret != 0) {
	    switch (al->adj.Resource) {
	    case RES_MEMORY_RANGE:
		sprintf(tmp, "memory %#lx-%#lx",
			al->adj.resource.memory.Base,
			al->adj.resource.memory.Base +
			al->adj.resource.memory.Size - 1);
		break;
	    case RES_IO_RANGE:
		sprintf(tmp, "IO ports %#x-%#x",
			al->adj.resource.io.BasePort,
			al->adj.resource.io.BasePort +
			al->adj.resource.io.NumPorts - 1);
		break;
	    case RES_IRQ:
		sprintf(tmp, "irq %u", al->adj.resource.irq.IRQ);
		break;
	    }
	    log_message("CM: could not adjust resource: %s: %m", tmp);
	}
    }
}
    
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// static int cleanup_files = 0;
//mdk-stage1// 
//mdk-stage1// static void fork_now(void)
//mdk-stage1// {
//mdk-stage1//     int ret;
//mdk-stage1//     if ((ret = fork()) > 0) {
//mdk-stage1// 	cleanup_files = 0;
//mdk-stage1// 	exit(0);
//mdk-stage1//     }
//mdk-stage1//     if (ret == -1)
//mdk-stage1// 	syslog(LOG_ERR, "forking: %m");
//mdk-stage1//     if (setsid() < 0)
//mdk-stage1// 	syslog(LOG_ERR, "detaching from tty: %m");
//mdk-stage1// }    
//mdk-stage1// 
//mdk-stage1// static void done(void)
//mdk-stage1// {
//mdk-stage1//     syslog(LOG_INFO, "exiting");
//mdk-stage1//     if (cleanup_files) {
//mdk-stage1// 	unlink(pidfile);
//mdk-stage1// 	unlink(stabfile);
//mdk-stage1//     }
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// /* most recent signal */
//mdk-stage1// static int caught_signal = 0;
//mdk-stage1// 
//mdk-stage1// static void catch_signal(int sig)
//mdk-stage1// {
//mdk-stage1//     caught_signal = sig;
//mdk-stage1//     if (signal(sig, catch_signal) == SIG_ERR)
//mdk-stage1// 	syslog(LOG_INFO, "signal(%d): %m", sig);
//mdk-stage1// }
//mdk-stage1// 
//mdk-stage1// static void handle_signal(void)
//mdk-stage1// {
//mdk-stage1//     int i;
//mdk-stage1//     switch (caught_signal) {
//mdk-stage1//     case SIGTERM:
//mdk-stage1//     case SIGINT:
//mdk-stage1// 	for (i = 0; i < sockets; i++)
//mdk-stage1// 	    if ((socket[i].state & SOCKET_PRESENT) &&
//mdk-stage1// 		(do_check(i) == 0)) do_remove(i);
//mdk-stage1// 	free_resources();
//mdk-stage1// 	exit(0);
//mdk-stage1// 	break;
//mdk-stage1//     case SIGHUP:
//mdk-stage1// 	free_resources();
//mdk-stage1// 	free_config();
//mdk-stage1// 	syslog(LOG_INFO, "re-loading config file");
//mdk-stage1// 	load_config();
//mdk-stage1// 	adjust_resources();
//mdk-stage1// 	break;
//mdk-stage1// #ifdef SIGPWR
//mdk-stage1//     case SIGPWR:
//mdk-stage1// 	break;
//mdk-stage1// #endif
//mdk-stage1//     }
//mdk-stage1// }

/*====================================================================*/

static int init_sockets(void)
{
    int fd, i;
    servinfo_t serv;

#ifdef __linux__
    major = lookup_dev("pcmcia");
    if (major < 0) {
	if (major == -ENODEV)
	    log_message("CM: no pcmcia driver in /proc/devices");
	else
	    log_message("CM: could not open /proc/devices: %m");
	return -1;
    }
#endif
    for (fd = -1, i = 0; i < MAX_SOCKS; i++) {
	fd = open_sock(i, S_IFCHR|S_IREAD|S_IWRITE);
	if (fd < 0) break;
	socket[i].fd = fd;
	socket[i].state = 0;
    }
    if ((fd < 0) && (errno != ENODEV) && (errno != ENOENT))
	log_message("CM: open_sock(socket %d) failed: %m", i);
    sockets = i;
    if (sockets == 0) {
	log_message("CM: no sockets found!");
	return -1;
    } else
	log_message("CM: watching %d sockets", sockets);

    if (ioctl(socket[0].fd, DS_GET_CARD_SERVICES_INFO, &serv) == 0) {
	if (serv.Revision != CS_RELEASE_CODE)
	    log_message("CM: warning, Card Services release does not match kernel (generally harmless)");
    } else {
	log_message("CM: could not get CS revision info!");
	return -1;
    }
    adjust_resources();
    return 0;
}

//mdk-stage1// /*====================================================================*/
//mdk-stage1// 
//mdk-stage1// int main(int argc, char *argv[])
//mdk-stage1// {
//mdk-stage1//     int optch, errflg;
//mdk-stage1//     int i, max_fd, ret, event, pass;
//mdk-stage1//     int delay_fork = 0;
//mdk-stage1//     struct timeval tv;
//mdk-stage1//     fd_set fds;
//mdk-stage1// 
//mdk-stage1//     if (access("/var/lib/pcmcia", R_OK) == 0) {
//mdk-stage1// 	stabfile = "/var/lib/pcmcia/stab";
//mdk-stage1//     } else {
//mdk-stage1// 	stabfile = "/var/run/stab";
//mdk-stage1//     }
//mdk-stage1// 
//mdk-stage1//     errflg = 0;
//mdk-stage1//     while ((optch = getopt(argc, argv, "Vqdvofc:m:p:s:")) != -1) {
//mdk-stage1// 	switch (optch) {
//mdk-stage1// 	case 'V':
//mdk-stage1// 	    fprintf(stderr, "cardmgr version " CS_RELEASE "\n");
//mdk-stage1// 	    return 0;
//mdk-stage1// 	    break;
//mdk-stage1// 	case 'q':
//mdk-stage1// 	    be_quiet = 1; break;
//mdk-stage1// 	case 'v':
//mdk-stage1// 	    verbose = 1; break;
//mdk-stage1// 	case 'o':
//mdk-stage1// 	    one_pass = 1; break;
//mdk-stage1// 	case 'f':
//mdk-stage1// 	    delay_fork = 1; break;
//mdk-stage1// 	case 'c':
//mdk-stage1// 	    configpath = strdup(optarg); break;
//mdk-stage1// #ifdef __linux__
//mdk-stage1// 	case 'd':
//mdk-stage1// 	    do_modprobe = 1; break;
//mdk-stage1// 	case 'm':
//mdk-stage1// 	    modpath = strdup(optarg); break;
//mdk-stage1// #endif
//mdk-stage1// 	case 'p':
//mdk-stage1// 	    pidfile = strdup(optarg); break;
//mdk-stage1// 	case 's':
//mdk-stage1// 	    stabfile = strdup(optarg); break;
//mdk-stage1// 	default:
//mdk-stage1// 	    errflg = 1; break;
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1//     if (errflg || (optind < argc)) {
//mdk-stage1// 	fprintf(stderr, "usage: %s [-V] [-q] [-v] [-d] [-o] [-f] "
//mdk-stage1// 		"[-c configpath] [-m modpath]\n               "
//mdk-stage1// 		"[-p pidfile] [-s stabfile]\n", argv[0]);
//mdk-stage1// 	exit(EXIT_FAILURE);
//mdk-stage1//     }
//mdk-stage1// 
//mdk-stage1// #ifdef DEBUG
//mdk-stage1//     openlog("cardmgr", LOG_PID|LOG_PERROR, LOG_DAEMON);
//mdk-stage1// #else
//mdk-stage1//     openlog("cardmgr", LOG_PID|LOG_CONS, LOG_DAEMON);
//mdk-stage1//     close(0); close(1); close(2);
//mdk-stage1//     if (!delay_fork && !one_pass)
//mdk-stage1// 	fork_now();
//mdk-stage1// #endif
//mdk-stage1//     
//mdk-stage1//     syslog(LOG_INFO, "starting, version is " CS_RELEASE);
//mdk-stage1//     atexit(&done);
//mdk-stage1//     putenv("PATH=/bin:/sbin:/usr/bin:/usr/sbin");
//mdk-stage1//     if (verbose)
//mdk-stage1// 	putenv("VERBOSE=1");
//mdk-stage1// 
//mdk-stage1// #ifdef __linux__
//mdk-stage1//     if (modpath == NULL) {
//mdk-stage1// 	if (access("/lib/modules/preferred", X_OK) == 0)
//mdk-stage1// 	    modpath = "/lib/modules/preferred";
//mdk-stage1// 	else {
//mdk-stage1// 	    struct utsname utsname;
//mdk-stage1// 	    if (uname(&utsname) != 0) {
//mdk-stage1// 		syslog(LOG_ERR, "uname(): %m");
//mdk-stage1// 		exit(EXIT_FAILURE);
//mdk-stage1// 	    }
//mdk-stage1// 	    modpath = (char *)malloc(strlen(utsname.release)+14);
//mdk-stage1// 	    sprintf(modpath, "/lib/modules/%s", utsname.release);
//mdk-stage1// 	}
//mdk-stage1//     }
//mdk-stage1//     if (access(modpath, X_OK) != 0)
//mdk-stage1// 	syslog(LOG_INFO, "cannot access %s: %m", modpath);
//mdk-stage1//     /* We default to using modprobe if it is available */
//mdk-stage1//     do_modprobe |= (access("/sbin/modprobe", X_OK) == 0);
//mdk-stage1// #endif /* __linux__ */
//mdk-stage1//     
//mdk-stage1//     load_config();
//mdk-stage1//     
//mdk-stage1//     if (init_sockets() != 0)
//mdk-stage1// 	exit(EXIT_FAILURE);
//mdk-stage1// 
//mdk-stage1//     /* If we've gotten this far, then clean up pid and stab at exit */
//mdk-stage1//     write_pid();
//mdk-stage1//     write_stab();
//mdk-stage1//     cleanup_files = 1;
//mdk-stage1//     
//mdk-stage1//     if (signal(SIGHUP, catch_signal) == SIG_ERR)
//mdk-stage1// 	syslog(LOG_ERR, "signal(SIGHUP): %m");
//mdk-stage1//     if (signal(SIGTERM, catch_signal) == SIG_ERR)
//mdk-stage1// 	syslog(LOG_ERR, "signal(SIGTERM): %m");
//mdk-stage1//     if (signal(SIGINT, catch_signal) == SIG_ERR)
//mdk-stage1// 	syslog(LOG_ERR, "signal(SIGINT): %m");
//mdk-stage1// #ifdef SIGPWR
//mdk-stage1//     if (signal(SIGPWR, catch_signal) == SIG_ERR)
//mdk-stage1// 	syslog(LOG_ERR, "signal(SIGPWR): %m");
//mdk-stage1// #endif
//mdk-stage1//     
//mdk-stage1//     for (i = max_fd = 0; i < sockets; i++)
//mdk-stage1// 	max_fd = (socket[i].fd > max_fd) ? socket[i].fd : max_fd;
//mdk-stage1// 
//mdk-stage1//     /* First select() call: poll, don't wait */
//mdk-stage1//     tv.tv_sec = tv.tv_usec = 0;
//mdk-stage1// 
//mdk-stage1//     /* Wait for sockets in setup-pending state to settle */
//mdk-stage1//     if (one_pass || delay_fork)
//mdk-stage1// 	wait_for_pending();
//mdk-stage1//     
//mdk-stage1//     for (pass = 0; ; pass++) {
//mdk-stage1// 	FD_ZERO(&fds);
//mdk-stage1// 	for (i = 0; i < sockets; i++)
//mdk-stage1// 	    FD_SET(socket[i].fd, &fds);
//mdk-stage1// 
//mdk-stage1// 	while ((ret = select(max_fd+1, &fds, NULL, NULL,
//mdk-stage1// 			     ((pass == 0) ? &tv : NULL))) < 0) {
//mdk-stage1// 	    if (errno == EINTR) {
//mdk-stage1// 		handle_signal();
//mdk-stage1// 	    } else {
//mdk-stage1// 		syslog(LOG_ERR, "select(): %m");
//mdk-stage1// 		exit(EXIT_FAILURE);
//mdk-stage1// 	    }
//mdk-stage1// 	}
//mdk-stage1// 
//mdk-stage1// 	for (i = 0; i < sockets; i++) {
//mdk-stage1// 	    if (!FD_ISSET(socket[i].fd, &fds))
//mdk-stage1// 		continue;
//mdk-stage1// 	    ret = read(socket[i].fd, &event, 4);
//mdk-stage1// 	    if ((ret == -1) && (errno != EAGAIN))
//mdk-stage1// 		syslog(LOG_INFO, "read(%d): %m\n", i);
//mdk-stage1// 	    if (ret != 4)
//mdk-stage1// 		continue;
//mdk-stage1// 	    
//mdk-stage1// 	    switch (event) {
//mdk-stage1// 	    case CS_EVENT_CARD_REMOVAL:
//mdk-stage1// 		socket[i].state = 0;
//mdk-stage1// 		do_remove(i);
//mdk-stage1// 		break;
//mdk-stage1// 	    case CS_EVENT_EJECTION_REQUEST:
//mdk-stage1// 		ret = do_check(i);
//mdk-stage1// 		if (ret == 0) {
//mdk-stage1// 		    socket[i].state = 0;
//mdk-stage1// 		    do_remove(i);
//mdk-stage1// 		}
//mdk-stage1// 		write(socket[i].fd, &ret, 4);
//mdk-stage1// 		break;
//mdk-stage1// 	    case CS_EVENT_CARD_INSERTION:
//mdk-stage1// 	    case CS_EVENT_INSERTION_REQUEST:
//mdk-stage1// 		socket[i].state |= SOCKET_PRESENT;
//mdk-stage1// 	    case CS_EVENT_CARD_RESET:
//mdk-stage1// 		socket[i].state |= SOCKET_READY;
//mdk-stage1// 		do_insert(i);
//mdk-stage1// 		break;
//mdk-stage1// 	    case CS_EVENT_RESET_PHYSICAL:
//mdk-stage1// 		socket[i].state &= ~SOCKET_READY;
//mdk-stage1// 		break;
//mdk-stage1// 	    case CS_EVENT_PM_SUSPEND:
//mdk-stage1// 		do_suspend(i);
//mdk-stage1// 		break;
//mdk-stage1// 	    case CS_EVENT_PM_RESUME:
//mdk-stage1// 		do_resume(i);
//mdk-stage1// 		break;
//mdk-stage1// 	    }
//mdk-stage1// 	    
//mdk-stage1// 	}
//mdk-stage1// 
//mdk-stage1// 	if (one_pass)
//mdk-stage1// 	    exit(EXIT_SUCCESS);
//mdk-stage1// 	if (delay_fork) {
//mdk-stage1// 	    fork_now();
//mdk-stage1// 	    write_pid();
//mdk-stage1// 	}
//mdk-stage1// 	
//mdk-stage1//     } /* repeat */
//mdk-stage1//     return 0;
//mdk-stage1// }



static void cardmgr_fail(void)
{
	log_message("CM: cardmgr: failed");
}

int cardmgr_call(void)
{
	int i, max_fd, ret, event;
	struct timeval tv;
	fd_set fds;
	
	stabfile = "/var/run/stab";
	
	log_message("CM: cardmgr/hacked starting, version is " CS_RELEASE);
	
	if (load_config()) {
		cardmgr_fail();
		return -1;
	}
	
	if (init_sockets()) {
		cardmgr_fail();
		return -1;
	}
	
	/* If we've gotten this far, then clean up pid and stab at exit */
	write_stab();
    
	for (i = max_fd = 0; i < sockets; i++)
		max_fd = (socket[i].fd > max_fd) ? socket[i].fd : max_fd;

	/* First select() call: poll, don't wait */
	tv.tv_sec = tv.tv_usec = 0;

	/* Wait for sockets in setup-pending state to settle */
	wait_for_pending();
    

	FD_ZERO(&fds);
	for (i = 0; i < sockets; i++)
		FD_SET(socket[i].fd, &fds);

	if (select(max_fd+1, &fds, NULL, NULL, &tv) < 0) {
		log_perror("CM: select fails");
		return -1;
	}

	for (i = 0; i < sockets; i++) {
		if (!FD_ISSET(socket[i].fd, &fds))
			continue;
		ret = read(socket[i].fd, &event, 4);
		if ((ret == -1) && (errno != EAGAIN))
			log_message("CM: read(%d): %m", i);
		if (ret != 4)
			continue;
	    
		switch (event) {
		case CS_EVENT_CARD_INSERTION:
		case CS_EVENT_INSERTION_REQUEST:
			socket[i].state |= SOCKET_PRESENT;
		case CS_EVENT_CARD_RESET:
			socket[i].state |= SOCKET_READY;
			do_insert(i);
			break;
		case CS_EVENT_RESET_PHYSICAL:
			socket[i].state &= ~SOCKET_READY;
			break;
		}
	    
	}

	return 0;
	
}
