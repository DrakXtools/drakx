use Config;

print '
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* workaround for glibc and kernel header files not in sync */
#define dev_t dev_t

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
#include <linux/keyboard.h>
#include <linux/kd.h>
#include <linux/hdreg.h>
#include <linux/vt.h>
#include <linux/fd.h>
#include <linux/cdrom.h>
#include <linux/loop.h>
#include <linux/blkpg.h>
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

/* for is_ext3 */
#include <ext2fs/ext2_fs.h>
#include <ext2fs/ext2fs.h>

// for UPS on USB:
#include <linux/hiddev.h>

#include <libldetect.h>

#include <langinfo.h>
#include <string.h>
#include <iconv.h>

#include <libintl.h>

#define SECTORSIZE 512

char *prom_getopt();
void prom_setopt();
char *prom_getproperty();
char *disk2PromPath();
char *promRootName();

';

$ENV{C_DRAKX} && $Config{archname} =~ /i.86/ and print '
char *pcmcia_probe(void);
';

$ENV{C_RPM} and print '
#undef Fflush
#undef Mkdir
#undef Stat
#include <rpm/rpmlib.h>
#include <rpm/rpmio.h>

void rpmError_callback_empty(void) {}

int rpmError_callback_data;
void rpmError_callback(void) {
  if (rpmErrorCode() != RPMERR_UNLINK && rpmErrorCode() != RPMERR_RMDIR) {
    write(rpmError_callback_data, rpmErrorString(), strlen(rpmErrorString()));
  }
}

';

$ENV{C_DRAKX} and print '

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

';

print '

SV * iconv_(char* s, char* from_charset, char* to_charset) {
  iconv_t cd = iconv_open(to_charset, from_charset);
  char* retval = s;
  if (cd != (iconv_t) (-1)) {
      size_t s_len = strlen(retval);
      /* the maximum expansion when converting happens when converting
	 tscii to utf-8; each tscii char can become up to 4 unicode chars
	 and each one of those unicode chars can be 3 bytes long */
      char *buf = alloca(4 * 3 * s_len);
      {
	  char *ptr = buf;
	  size_t ptr_len = 4 * 3 * s_len;
	  if ((iconv(cd, &s, &s_len, &ptr, &ptr_len)) != (size_t) (-1)) {
	      *ptr = 0;
	      retval = buf;
	  }
      }
      iconv_close(cd);
  }
  return newSVpv(retval, 0);
}

MODULE = c::stuff		PACKAGE = c::stuff

';

$ENV{C_DRAKX} && $Config{archname} =~ /i.86/ and print '
char *
pcmcia_probe()
';

print '
char *
dgettext(domainname, msgid)
   char * domainname
   char * msgid

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

int
is_ext3(device_name)
  char * device_name
  CODE:
  {
    ext2_filsys fs;
    int retval = ext2fs_open (device_name, 0, 0, 0, unix_io_manager, &fs);
    if (retval) {
      RETVAL = 0;
    } else {
      RETVAL = fs->super->s_feature_compat & EXT3_FEATURE_COMPAT_HAS_JOURNAL;
      ext2fs_close(fs);  
    }
  }
  OUTPUT:
  RETVAL

char *
get_ext2_label(device_name)
  char * device_name
  CODE:
  {
    ext2_filsys fs;
    int retval = ext2fs_open (device_name, 0, 0, 0, unix_io_manager, &fs);
    if (retval) {
      RETVAL = 0;
    } else {
      RETVAL = fs->super->s_volume_name;
      ext2fs_close(fs);  
    }
  }
  OUTPUT:
  RETVAL

void
setlocale()
   CODE:
   setlocale(LC_ALL, "");
   setlocale(LC_NUMERIC, "C"); /* otherwise eval "1.5" returns 1 in fr_FR for example */

char *
bindtextdomain(domainname, dirname)
   char * domainname
   char * dirname

char *
bind_textdomain_codeset(domainname, codeset)
   char * domainname
   char * codeset

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

unsigned int
total_sectors(fd)
  int fd
  CODE:
  {
    long s;
    RETVAL = ioctl(fd, BLKGETSIZE, &s) == 0 ? s : 0;
  }
  OUTPUT:
  RETVAL

void
unlimit_core()
  CODE:
  {
    struct rlimit rlim = { RLIM_INFINITY, RLIM_INFINITY };
    setrlimit(RLIMIT_CORE, &rlim);
  }

int
getlimit_core()
  CODE:
  {
    struct rlimit rlim;
    getrlimit(RLIMIT_CORE, &rlim);
    RETVAL = rlim.rlim_cur;
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
  syslog(priority, mesg);

void
setsid()

void
_exit(status)
  int status

void
usleep(microseconds)
  unsigned long microseconds

int
detectSMP()

void
pci_probe()
  PPCODE:
    struct pciusb_entries entries = pci_probe();
    char buf[2048];
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct pciusb_entry *e = &entries.entries[i];
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%04x\t%04x\t%d\t%d\t%d\t%s\t%s\t%s", 
               e->vendor, e->device, e->subvendor, e->subdevice, e->pci_bus, e->pci_device, e->pci_function,
               pci_class2text(e->class_), e->module ? e->module : "unknown", e->text);
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
      struct usb_class_text class_text = usb_class2text(e->class_);
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%s|%s|%s\t%s\t%s\t%d\t%d", 
               e->vendor, e->device, class_text.usb_class_text, class_text.usb_sub_text, class_text.usb_prot_text, e->module ? e->module : "unknown", e->text, e->pci_bus, e->pci_device);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    pciusb_free(&entries);

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
hasNetDevice(device)
  char * device
  CODE:
    struct ifreq req;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s == -1) { RETVAL = 0; return; }

    strcpy(req.ifr_name, device);

    RETVAL = ioctl(s, SIOCGIFFLAGS, &req) == 0;
    close(s);
  OUTPUT:
  RETVAL

char*
getNetDriver(char* device)
  ALIAS:
    getHwIDs = 1
  CODE:
    struct ifreq ifr;
    struct ethtool_drvinfo drvinfo;
    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, sizeof(ifr.ifr_name)-1);

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
    a = ifr.ifr_hwaddr.sa_data;
    asprintf(&res, "%02x:%02x:%02x:%02x:%02x:%02x", a[0],a[1],a[2],a[3],a[4],a[5]);
    RETVAL= res;
  OUTPUT:
  RETVAL



char *
kernel_version()
  CODE:
  struct utsname u;
  if (uname(&u) == 0) RETVAL = u.release; else RETVAL = NULL;
  OUTPUT:
  RETVAL

int
prom_open()

void
prom_close()

int
prom_getsibling(node)
  int node

int
prom_getchild(node)
  int node

void
prom_getopt(key)
  char *key
  PPCODE:
  int lenp = 0;
  char *value = NULL;
  value = prom_getopt(key, &lenp);
  EXTEND(sp, 1);
  if (value != NULL) {
    PUSHs(sv_2mortal(newSVpv(value, 0)));
  } else {
    PUSHs(&PL_sv_undef);
  }

void
prom_setopt(key, value)
  char *key
  char *value

void
prom_getproperty(key)
  char *key
  PPCODE:
  int lenp = 0;
  char *value = NULL;
  value = prom_getproperty(key, &lenp);
  EXTEND(sp, 1);
  if (value != NULL) {
    PUSHs(sv_2mortal(newSVpv(value, lenp)));
  } else {
    PUSHs(&PL_sv_undef);
  }

void
prom_getstring(key)
  char *key
  PPCODE:
  int lenp = 0;
  char *value = NULL;
  value = prom_getproperty(key, &lenp);
  EXTEND(sp, 1);
  if (value != NULL) {
    PUSHs(sv_2mortal(newSVpv(value, 0)));
  } else {
    PUSHs(&PL_sv_undef);
  }

int
prom_getbool(key)
  char *key

void
initSilo()

char *
disk2PromPath(disk)
  unsigned char *disk

int
hasAliases()

char *
promRootName()

void
setPromVars(linuxAlias, bootDevice)
  char *linuxAlias
  char *bootDevice

SV *
iconv(s, from_charset, to_charset)
  char *s
  char *from_charset
  char *to_charset
  CODE:
  RETVAL = iconv_(s, from_charset, to_charset);
  OUTPUT:
  RETVAL

int
is_tagged_utf8(s)
   SV *s
   CODE:
   RETVAL = SvUTF8(s);
   OUTPUT:
   RETVAL

void
set_tagged_utf8(s)
   SV *s
   CODE:
   SvUTF8_on(s);

void
upgrade_utf8(s)
   SV *s
   CODE:
   sv_utf8_upgrade(s);

void
unset_tagged_utf8(s)
   SV *s
   CODE:
   SvUTF8_off(s);

char *
standard_charset()
  CODE:
  RETVAL = nl_langinfo(CODESET);
  OUTPUT:
  RETVAL

';

$ENV{C_RPM} and print '
const char *
rpmErrorString()

void
rpmSetVeryVerbose()
  CODE:
  rpmSetVerbosity(RPMMESS_DEBUG);

void
rpmErrorSetCallback(fd)
  int fd
  CODE:
  rpmError_callback_data = fd;
  rpmErrorSetCallback(rpmError_callback);

int
rpmvercmp(char *a, char *b);
';

@macros = (
  [ qw(int S_IFCHR S_IFBLK S_IFIFO KDSKBENT KT_SPEC K_NOSUCHMAP NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO BLKGETSIZE LOOP_GET_STATUS HIDIOCAPPLICATION
       MS_MGC_VAL MS_RDONLY O_NONBLOCK F_SETFL F_GETFL O_CREAT SECTORSIZE WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE CDROM_LOCKDOOR CDROMEJECT CDROM_DRIVE_STATUS CDS_DISC_OK
       LOG_WARNING LOG_INFO LOG_LOCAL1
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

PROTOTYPES: ENABLE
';

