/* This file is inspired from source code of kudzu from Red Hat, Inc.
 * It has been modified to keep only "what is needed" in C, the prom_walk
 * has been rewritten in perl for convenience :-)
 *
 * Copyright notice from original version.
 * sbus.c: Probe for Sun SBUS and UPA framebuffers using OpenPROM,
 *         SBUS SCSI and Ethernet cards and SBUS or EBUS audio chips.
 *
 * Copyright (C) 1998, 1999 Jakub Jelinek (jj@ultra.linux.cz)
 *           (C) 1999 Red Hat, Inc.
 * 
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 *
 */

#ifdef __sparc__

#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <asm/openpromio.h>

static char *promdev = "/dev/openprom";
static int promfd = -1;
static int prom_current_node;
#define MAX_PROP        128
#define MAX_VAL         (4096-128-4)
static char buf[4096];
#define DECL_OP(size) struct openpromio *op = (struct openpromio *)buf; op->oprom_size = (size)

int prom_open()
{
    int prom_root_node;

    if (promfd == -1) {
        promfd = open(promdev, O_RDONLY);
	if (promfd == -1)
	    return 0;
    }
    prom_root_node = prom_getsibling(0);
    if (!prom_root_node) {
        close(promfd);
	promfd = -1;
	return 0;
    }
    return prom_root_node;
}

void prom_close()
{
    if (promfd != -1) {
        close(promfd);
	promfd = -1;
    }
}

int prom_getsibling(int node)
{
    DECL_OP(sizeof(int));
        
    if (node == -1) return 0;
    *(int *)op->oprom_array = node;
    if (ioctl (promfd, OPROMNEXT, op) < 0)
        return 0;
    prom_current_node = *(int *)op->oprom_array;
    return *(int *)op->oprom_array;
}

int prom_getchild(int node)
{
    DECL_OP(sizeof(int));
        
    if (!node || node == -1) return 0;
    *(int *)op->oprom_array = node;
    if (ioctl (promfd, OPROMCHILD, op) < 0)
        return 0;
    prom_current_node = *(int *)op->oprom_array;
    return *(int *)op->oprom_array;
}

char *prom_getopt(char *var, int *lenp)
{
    DECL_OP(MAX_VAL);
        
    strcpy (op->oprom_array, var);
    if (ioctl (promfd, OPROMGETOPT, op) < 0)
        return 0;
    if (lenp) *lenp = op->oprom_size;
    return op->oprom_array;
}

void prom_setopt(char *var, char *value) {
    DECL_OP(MAX_VAL);

    strcpy (op->oprom_array, var);
    strcpy (op->oprom_array + strlen (var) + 1, value);
    ioctl (promfd, OPROMSETOPT, op);
}

char *prom_getproperty(char *prop, int *lenp)
{
    DECL_OP(MAX_VAL);
        
    strcpy (op->oprom_array, prop);
    if (ioctl (promfd, OPROMGETPROP, op) < 0)
        return 0;
    if (lenp) *lenp = op->oprom_size;
    return op->oprom_array;
}

int prom_getbool(char *prop)
{
    DECL_OP(0);

    *(int *)op->oprom_array = 0;
    for (;;) {
        op->oprom_size = MAX_PROP;
	if (ioctl(promfd, OPROMNXTPROP, op) < 0)
	    return 0;
	if (!op->oprom_size)
	    return 0;
	if (!strcmp (op->oprom_array, prop))
	    return 1;
    }
}

int prom_pci2node(int bus, int devfn) {
    DECL_OP(2*sizeof(int));
    
    ((int *)op->oprom_array)[0] = bus;
    ((int *)op->oprom_array)[1] = devfn;
    if (ioctl (promfd, OPROMPCI2NODE, op) < 0)
        return 0;
    prom_current_node = *(int *)op->oprom_array;
    return *(int *)op->oprom_array;
}

#else
int prom_open() { return 0; }
void prom_close() {}
int prom_getsibling(int node) { return 0; }
int prom_getchild(int node) { return 0; }
char *prom_getopt(char *var, int *lenp) { return 0; /* NULL */ }
void prom_setopt(char *var, char *value) {}
char *prom_getproperty(char *prop, int *lenp) { return 0; /* NULL */ }
int prom_getbool(char *prop) { return 0; }
int prom_pci2node(int bus, int devfn) { return 0; }
#endif /* __sparc__ */
