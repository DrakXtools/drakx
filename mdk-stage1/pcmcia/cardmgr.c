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

/* Code comes from /anonymous@projects.sourceforge.net:/pub/pcmcia-cs/pcmcia-cs-3.1.23.tar.bz2
 *
 *   Licence of this code follows:

    PCMCIA Card Manager daemon

    cardmgr.c 1.150 2000/12/14 17:12:59

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
    terms of the GNU Public License version 2 (the "GPL"), in which
    case the provisions of the GPL are applicable instead of the
    above.  If you wish to allow the use of your version of this file
    only under the terms of the GPL and not to allow others to use
    your version of this file under the MPL, indicate your decision
    by deleting the provisions above and replace them with the notice
    and other provisions required by the GPL.  If you do not delete
    the provisions above, a recipient may use your version of this
    file under either the MPL or the GPL.
    
 */


#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/file.h>

#include <pcmcia/version.h>
#include <pcmcia/config.h>
#include <pcmcia/cs_types.h>
#include <pcmcia/cs.h>
#include <pcmcia/cistpl.h>
#include <pcmcia/ds.h>

#include "../log.h"
#include "modules.h"

#include "cardmgr.h"
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
#define SOCKET_BOUND	0x04

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

static char *configpath = "/etc/pcmcia";

/* Default path for socket info table */
static char *stabfile;

/*====================================================================*/

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

static int open_dev(dev_t dev, int mode)
{
	char *fn;
	int fd;
	if ((fn = tmpnam(NULL)) == NULL)
		return -1;
	if (mknod(fn, mode, dev) != 0)
		return -1;
	fd = open(fn, (mode&S_IWRITE) ? O_RDWR : O_RDONLY);
	if (fd < 0)
		fd = open(fn, O_NONBLOCK|((mode&S_IWRITE) ? O_RDWR : O_RDONLY));
	unlink(fn);
	return fd;
}

static int open_sock(int sock, int mode)
{
	dev_t dev = (major<<8) + sock;
	return open_dev(dev, mode);
}

/*======================================================================

    xlate_scsi_name() is a sort-of-hack used to deduce the minor
    device numbers of SCSI devices, from the information available to
    the low-level driver.
    
======================================================================*/


#include <linux/major.h>
#include <scsi/scsi.h>

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


/*====================================================================*/

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
	if (flock(fileno(f), LOCK_EX) != 0) {
		log_message("CM: flock(stabfile) failed: %m");
		return;
	}
	for (i = 0; i < sockets; i++) {
		s = &socket[i];
		if (!(s->state & SOCKET_PRESENT))
			fprintf(f, "Socket %d: empty\n", i);
		else if (!s->card)
			fprintf(f, "Socket %d: unsupported card\n", i);
		else {
			fprintf(f, "Socket %d: %s\n", i, s->card->name);
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

/*====================================================================*/

typedef struct {
	u_short vendor, device;
} pci_id_t;


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
	config_info_t config;
	int i, ret, match;
	int has_cis = 0;

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

		match = 0;
		for (card = root_card; card; card = card->next) {
			switch (card->ident_type) {
		
			case VERS_1_IDENT:
				if (vers == NULL)
					break;
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
					break;
				match = 1;
				break;

			case MANFID_IDENT:
				if ((manfid.manf == card->id.manfid.manf) &&
				    (manfid.card == card->id.manfid.card))
					match = 1;
				break;
		
			case TUPLE_IDENT:
				arg.tuple.DesiredTuple = card->id.tuple.code;
				arg.tuple.Attributes = 0;
				ret = ioctl(s->fd, DS_GET_FIRST_TUPLE, &arg);
				if (ret != 0) break;
				arg.tuple.TupleOffset = card->id.tuple.ofs;
				ret = ioctl(s->fd, DS_GET_TUPLE_DATA, &arg);
				if (ret != 0) break;
				if (strncmp((char *)arg.tuple_parse.data,
					    card->id.tuple.info,
					    strlen(card->id.tuple.info)) != 0)
					break;
				match = 1;
				break;

			default:
				/* Skip */
				break;
			}
			if (match) break;
		}
	}

	/* Check PCI vendor/device info */
	status.Function = config.Function = config.ConfigBase = 0;
	if ((ioctl(s->fd, DS_GET_CONFIGURATION_INFO, &config) == 0) &&
	    (config.IntType == INT_CARDBUS)) {
		pci_id.vendor = config.ConfigBase & 0xffff;
		pci_id.device = config.ConfigBase >> 16;
		if (!card) {
			for (card = root_card; card; card = card->next)
				if ((card->ident_type == PCI_IDENT) &&
				    (pci_id.vendor == card->id.manfid.manf) &&
				    (pci_id.device == card->id.manfid.card))
					break;
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
		return card;
	}

	status.Function = 0;
	if (!blank_card || (status.CardState & CS_EVENT_CB_DETECT) ||
	    manfid.manf || manfid.card || pci_id.vendor || vers) {
		log_message("CM: unsupported card in socket %d", ns);
		return NULL;
	} else {
		card = blank_card;
		log_message("CM: socket %d: %s", ns, card->name);
		return card;
	}
}


static void cardmgr_fail(void)
{
	log_message("CM: cardmgr: failed");
}
	
/*====================================================================*/

static int load_config(void)
{
	if (chdir(configpath)) {
		log_message("CM: chdir to %s failed: %m", configpath);
		return -1;
	}

	if (parse_configfile("config"))
		return -1;

	if (!root_device)
		log_message("CM: no device drivers defined");

	if (!root_card && !root_func)
		log_message("CM: no cards defined");

	return 0;
}


/*====================================================================*/

static void install_module(char *mod, char *opts)
{
	my_insmod(mod, ANY_DRIVER_TYPE, opts);
}

/*====================================================================*/

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
				log_message("CM:   %s memory region at 0x%lx: %s",
					    attr ? "Attribute" : "Common", (long unsigned int) region.CardOffset,
					    mtd->name);
				/* Bind MTD to this region */
				strcpy(mtd_info.dev_info, s->mtd[i]->module);
				mtd_info.Attributes = region.Attributes;
				mtd_info.CardOffset = region.CardOffset;
				if (ioctl(s->fd, DS_BIND_MTD, &mtd_info) != 0) {
					log_message(  "bind MTD '%s' to region at 0x%lx failed: %m",
						      (char *)mtd_info.dev_info, (long unsigned int) region.CardOffset);
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
	if (s->card && (s->card != blank_card))
		return;
    
	log_message("CM: initializing socket %d", sn);
	card = lookup_card(sn);
	/* Make sure we've learned something new before continuing */
	if (card == s->card)
		return;
	s->card = card;
	card->refs++;
	if (card->cis_file)
		update_cis(s);

	dev = card->device;

	/* Set up MTD's */
	for (i = 0; i < card->bindings; i++)
		if (dev[i]->needs_mtd)
			break;

	if (i < card->bindings)
		bind_mtd(sn);

	/* Install kernel modules */
	for (i = 0; i < card->bindings; i++) {
		dev[i]->refs++;
		for (j = 0; j < dev[i]->modules; j++)
			install_module(dev[i]->module[j], dev[i]->opts[j]);
	}
    
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
				write_stab();
				return;
			}
		}

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
			write_stab();
			return;
		}
		tail = &s->bind[i];
		while (ret == 0) {
			bind_info_t *old;
			if ((strlen(bind->name) > 3) && (bind->name[2] == '#'))
				xlate_scsi_name(bind);
			old = *tail = bind; tail = (bind_info_t **)&bind->next;
			bind = (bind_info_t *)malloc(sizeof(bind_info_t));
			memcpy(bind, old, sizeof(bind_info_t));
			ret = ioctl(s->fd, DS_GET_NEXT_DEVICE, bind);
		}
		*tail = NULL; free(bind);
		write_stab();
	}
}

/*====================================================================*/

static void wait_for_pending(void)
{
	cs_status_t status;
	int i;
	status.Function = 0;
	for (;;) {
		usleep(100000);
		for (i = 0; i < sockets; i++)
			if ((ioctl(socket[i].fd, DS_GET_STATUS, &status) == 0) && (status.CardState & CS_EVENT_CARD_INSERTION))
				break;
		if (i == sockets)
			break;
	}
}

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
    
/*====================================================================*/

static int init_sockets(void)
{
	int fd, i;
	servinfo_t serv;

	major = lookup_dev("pcmcia");
	if (major < 0) {
		if (major == -ENODEV)
			log_message("CM: no pcmcia driver in /proc/devices");
		else
			log_message("CM: could not open /proc/devices: %m");
		return -1;
	}

	for (fd = -1, i = 0; i < MAX_SOCKS; i++) {
		fd = open_sock(i, S_IFCHR|S_IREAD|S_IWRITE);
		if (fd < 0)
			break;
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
		log_message("CM: found %d sockets", sockets);

	if (ioctl(socket[0].fd, DS_GET_CARD_SERVICES_INFO, &serv) == 0) {
		if (serv.Revision != CS_RELEASE_CODE)
			log_message("CM: warning, Card Services release does not match kernel");
	} else {
		log_message("CM: could not get CS revision info!");
		return -1;
	}
	adjust_resources();
	return 0;
}

/*====================================================================*/

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
			log_message("CM: read(%d): %m\n", i);
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
