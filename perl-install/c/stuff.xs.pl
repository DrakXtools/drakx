use Config;

print '
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <syslog.h>
#include <fcntl.h>
#include <resolv.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/mount.h>
#undef __USE_MISC
#include <linux/if.h>
#include <linux/wireless.h>
#include <linux/keyboard.h>
#include <linux/kd.h>
#include <linux/hdreg.h>
#include <linux/vt.h>
#include <linux/fd.h>
#include <linux/cdrom.h>
#include <linux/loop.h>
#include <linux/blkpg.h>
#include <linux/iso_fs.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <linux/sockios.h>

// for ethtool structs:
typedef unsigned long long u64;
typedef __uint32_t u32;
typedef __uint16_t u16;
typedef __uint8_t u8;

#include <linux/ethtool.h>

// for UPS on USB:
# define HID_MAX_USAGES 1024
#include <linux/hiddev.h>

#include <libldetect.h>

#include <string.h>

#define SECTORSIZE 512

';

$Config{archname} =~ /i.86/ and print '
char *pcmcia_probe(void);
';

print '

/* log_message and log_perror are used in stage1 pcmcia probe */
void log_message(const char * s, ...) {
   va_list args;
   va_list args_copy;
   FILE * logtty = fopen("/dev/tty3", "w");
   if (!logtty)
      return;
   fprintf(logtty, "* ");
   va_start(args, s);
   vfprintf(logtty, s, args);
   fprintf(logtty, "\n");
   fclose(logtty);
   va_end(args);

   logtty = fopen("/tmp/ddebug.log", "a");
   if (!logtty)
      return;
   fprintf(logtty, "* ");
   va_copy(args_copy, args);
   va_start(args_copy, s);
   vfprintf(logtty, s, args_copy);
   fprintf(logtty, "\n");
   fclose(logtty);
   va_end(args_copy);
}
void log_perror(const char *msg) {
   log_message("%s: %s", msg, strerror(errno));
}


';

print '

int length_of_space_padded(char *str, int len) {
  while (len >= 0 && str[len-1] == \' \')
    --len;
  return len;
}

MODULE = c::stuff		PACKAGE = c::stuff

';

$Config{archname} =~ /i.86/ and print '
char *
pcmcia_probe()
';

print '
int
del_partition(hd, part_number)
  int hd
  int part_number
  CODE:
  {
    struct blkpg_partition p = { 0, 0, part_number, "", "" };
    struct blkpg_ioctl_arg s = { BLKPG_DEL_PARTITION, 0, sizeof(struct blkpg_partition), (void *) &p };
    RETVAL = ioctl(hd, BLKPG, &s) == 0;
  }
  OUTPUT:
  RETVAL

int
add_partition(hd, part_number, start_sector, size_sector)
  int hd
  int part_number
  unsigned long start_sector
  unsigned long size_sector
  CODE:
  {
    long long start = (long long) start_sector * 512;
    long long size = (long long) size_sector * 512;
    struct blkpg_partition p = { start, size, part_number, "", "" };
    struct blkpg_ioctl_arg s = { BLKPG_ADD_PARTITION, 0, sizeof(struct blkpg_partition), (void *) &p };
    RETVAL = ioctl(hd, BLKPG, &s) == 0;
  }
  OUTPUT:
  RETVAL

int
is_secure_file(filename)
  char * filename
  CODE:
  {
    int fd;
    unlink(filename); /* in case it exists and we manage to remove it */
    RETVAL = (fd = open(filename, O_RDWR | O_CREAT | O_EXCL, 0600)) != -1;
    if (RETVAL) close(fd);
  }
  OUTPUT:
  RETVAL

void
init_setlocale()
   CODE:
   setlocale(LC_ALL, "");
   setlocale(LC_NUMERIC, "C"); /* otherwise eval "1.5" returns 1 in fr_FR for example */

char *
setlocale(category, locale = 0) 
    int     category
    char *      locale

int
lseek_sector(fd, sector, offset)
  int fd
  long sector
  long offset
  CODE:
  RETVAL = lseek64(fd, (off64_t) sector * SECTORSIZE + offset, SEEK_SET) >= 0;
  OUTPUT:
  RETVAL

int
isBurner(fd)
  int fd
  CODE:
  RETVAL = ioctl(fd, CDROM_GET_CAPABILITY) & CDC_CD_RW;
  OUTPUT:
  RETVAL

int
isDvdDrive(fd)
  int fd
  CODE:
  RETVAL = ioctl(fd, CDROM_GET_CAPABILITY) & CDC_DVD;
  OUTPUT:
  RETVAL

char *
floppy_info(name)
  char * name
  CODE:
  int fd = open(name, O_RDONLY | O_NONBLOCK);
  RETVAL = NULL;
  if (fd != -1) {
     char drivtyp[17];
     if (ioctl(fd, FDGETDRVTYP, (void *)drivtyp) == 0) {
       struct floppy_drive_struct ds;
       if (ioctl(fd, FDPOLLDRVSTAT, &ds) == 0 && ds.track >= 0)
         RETVAL = drivtyp;
     }
     close(fd);
  }
  OUTPUT:
  RETVAL

NV
total_sectors(fd)
  int fd
  CODE:
  {
    unsigned long long ll;
    unsigned long l;
    RETVAL = ioctl(fd, BLKGETSIZE64, &ll) == 0 ? ll / 512 : 
             ioctl(fd, BLKGETSIZE, &l) == 0 ? l : 0;
  }
  OUTPUT:
  RETVAL

void
openlog(ident)
  char *ident
  CODE:
  openlog(ident, 0, 0);

void
closelog()

void
syslog(priority, mesg)
  int priority
  char *mesg
  CODE:
  syslog(priority, "%s", mesg);

void
setsid()

void
_exit(status)
  int status

void
usleep(microseconds)
  unsigned long microseconds

void
pci_probe()
  PPCODE:
    //proc_pci_path = "/tmp/pci";
    struct pciusb_entries entries = pci_probe();
    char buf[2048];
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct pciusb_entry *e = &entries.entries[i];
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%04x\t%04x\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%s", 
               e->vendor, e->device, e->subvendor, e->subdevice, e->pci_domain, e->pci_bus, e->pci_device, e->pci_function,
               pci_class2text(e->class_id), e->class, e->module ? e->module : "unknown", e->text);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    pciusb_free(&entries);

void
usb_probe()
  PPCODE:
    struct pciusb_entries entries = usb_probe();
    char buf[2048];
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct pciusb_entry *e = &entries.entries[i];
      struct usb_class_text class_text = usb_class2text(e->class_id);
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%s|%s|%s\t%s\t%s\t%d\t%d", 
               e->vendor, e->device, class_text.usb_class_text, class_text.usb_sub_text, class_text.usb_prot_text, e->module ? e->module : "unknown", e->text, e->pci_bus, e->pci_device);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    pciusb_free(&entries);

void
dmi_probe()
  PPCODE:
    //dmidecode_file = "/usr/share/ldetect-lst/dmidecode.Laptop.Dell-Latitude-C810";
    //dmidecode_file = "../../soft/ldetect-lst/test/dmidecode.Laptop.Sony-Vaio-GRX316MP";

    struct dmi_entries entries = dmi_probe();
    char buf[2048];
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      snprintf(buf, sizeof(buf), "%s\t%s", 
               entries.entries[i].module, entries.entries[i].constraints);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    dmi_entries_free(entries);


unsigned int
getpagesize()


char*
get_usb_ups_name(int fd)
  CODE:
        /* from nut/drivers/hidups.c::upsdrv_initups() : */
        char name[256];
        ioctl(fd, HIDIOCGNAME(sizeof(name)), name);
        RETVAL=name;
        ioctl(fd, HIDIOCINITREPORT, 0);
  OUTPUT:
  RETVAL


int
isNetDeviceWirelessAware(device)
  char * device
  CODE:
    struct iwreq ifr;

    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, IFNAMSIZ);
    RETVAL = ioctl(s, SIOCGIWNAME, &ifr) != -1;
    close(s);
  OUTPUT:
  RETVAL


void
get_netdevices()
  PPCODE:
     struct ifconf ifc;
     struct ifreq *ifr;
     int i;
     int numreqs = 10;

     int s = socket(AF_INET, SOCK_DGRAM, 0);

     ifc.ifc_buf = NULL;
     for (;;) {
          ifc.ifc_len = sizeof(struct ifreq) * numreqs;
          ifc.ifc_buf = realloc(ifc.ifc_buf, ifc.ifc_len);

          if (ioctl(s, SIOCGIFCONF, &ifc) < 0) {
               perror("SIOCGIFCONF");
               close(s);
               return;
          }
          if (ifc.ifc_len == sizeof(struct ifreq) * numreqs) {
               /* assume it overflowed and try again */
               numreqs += 10;                                                                         
               continue;                                                                              
          }
          break;
     }
     if (ifc.ifc_len) {
          ifr = ifc.ifc_req;
          EXTEND(sp, ifc.ifc_len);
          for (i=0; i < ifc.ifc_len; i+= sizeof(struct ifreq)) {
               PUSHs(sv_2mortal(newSVpv(ifr->ifr_name, 0)));
               ifr++;
          }
     }

     close(s);


char*
getNetDriver(char* device)
  ALIAS:
    getHwIDs = 1
  CODE:
    struct ifreq ifr;
    struct ethtool_drvinfo drvinfo;
    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, IFNAMSIZ);

    drvinfo.cmd = ETHTOOL_GDRVINFO;
    ifr.ifr_data = (caddr_t) &drvinfo;

    if (ioctl(s, SIOCETHTOOL, &ifr) != -1) {
        switch (ix) {
            case 0:
                RETVAL = strdup(drvinfo.driver);
                break;
            case 1:
                RETVAL = strdup(drvinfo.bus_info);
                break;
        }
    } else { perror("SIOCETHTOOL"); RETVAL = strdup(""); }
    close(s);
  OUTPUT:
  RETVAL


int
addDefaultRoute(gateway)
  char *gateway
  CODE:
    struct rtentry route;
    struct sockaddr_in addr;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s == -1) { RETVAL = 0; return; }

    memset(&route, 0, sizeof(route));

    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    inet_aton(gateway, &addr.sin_addr);
    memcpy(&route.rt_gateway, &addr, sizeof(addr));

    addr.sin_addr.s_addr = INADDR_ANY;
    memcpy(&route.rt_dst, &addr, sizeof(addr));
    memcpy(&route.rt_genmask, &addr, sizeof(addr));

    route.rt_flags = RTF_UP | RTF_GATEWAY;
    route.rt_metric = 0;

    RETVAL = !ioctl(s, SIOCADDRT, &route);
  OUTPUT:
  RETVAL


char*
get_hw_address(const char* ifname)
  CODE:
    int s;
    struct ifreq ifr;
    unsigned char *a;
    char *res;
    s = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (s < 0) {
        perror("socket");
        RETVAL = NULL;
        return;
    }
    strncpy((char*) &ifr.ifr_name, ifname, IFNAMSIZ);
    if (ioctl(s, SIOCGIFHWADDR, &ifr) < 0) {
        perror("ioctl(SIOCGIFHWADDR)");
        RETVAL = NULL;
        return;
    }
    a = (unsigned char*)ifr.ifr_hwaddr.sa_data;
    asprintf(&res, "%02x:%02x:%02x:%02x:%02x:%02x", a[0],a[1],a[2],a[3],a[4],a[5]);
    RETVAL= res;
  OUTPUT:
  RETVAL


void
strftime(fmt, sec, min, hour, mday, mon, year, wday = -1, yday = -1, isdst = -1)
    char *      fmt
    int     sec
    int     min
    int     hour
    int     mday
    int     mon
    int     year
    int     wday
    int     yday
    int     isdst
    CODE:
    {   
        char *buf = my_strftime(fmt, sec, min, hour, mday, mon, year, wday, yday, isdst);
        if (buf) {
        ST(0) = sv_2mortal(newSVpv(buf, 0));
        Safefree(buf);
        }
    }



char *
kernel_version()
  CODE:
  struct utsname u;
  if (uname(&u) == 0) RETVAL = u.release; else RETVAL = NULL;
  OUTPUT:
  RETVAL

void
set_tagged_utf8(s)
   SV *s
   CODE:
   SvUTF8_on(s);

void
get_iso_volume_ids(int fd)
  INIT:
  struct iso_primary_descriptor voldesc;
  PPCODE:
  lseek(fd, 16 * ISOFS_BLOCK_SIZE, SEEK_SET);
  if (read(fd, &voldesc, sizeof(struct iso_primary_descriptor)) == sizeof(struct iso_primary_descriptor)) {
    if (voldesc.type[0] == ISO_VD_PRIMARY && !strncmp(voldesc.id, ISO_STANDARD_ID, sizeof(voldesc.id))) {
      XPUSHs(sv_2mortal(newSVpv(voldesc.volume_id, length_of_space_padded(voldesc.volume_id, sizeof(voldesc.volume_id)))));
      XPUSHs(sv_2mortal(newSVpv(voldesc.application_id, length_of_space_padded(voldesc.application_id, sizeof(voldesc.application_id)))));
    }
  }

';

@macros = (
  [ qw(int S_IFCHR S_IFBLK S_IFIFO KDSKBENT K_NOSUCHMAP NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO LOOP_GET_STATUS
       MS_MGC_VAL O_WRONLY O_RDWR O_CREAT O_NONBLOCK F_SETFL F_GETFL WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE
       CDROMEJECT CDROMCLOSETRAY CDROM_LOCKDOOR
       LOG_WARNING LOG_INFO LOG_LOCAL1
       LC_COLLATE
       ) ],
);

$\= "\n";
print;

foreach (@macros) {
    my ($type, @l) = @$_;
    foreach (@l) {
	print<< "END"
$type
$_()
  CODE:
  RETVAL = $_;

  OUTPUT:
  RETVAL

END

    }
}
print '

PROTOTYPES: DISABLE
';

