use Config;

print '
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* workaround for glibc and kernel header files not in sync */
#define dev_t dev_t

#include <ctype.h>
#include <stdlib.h>
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

/* for is_ext3 */
#include <ext2fs/ext2_fs.h>
#include <ext2fs/ext2fs.h>

#include <libldetect.h>
#include <X11/Xlib.h>
#include <X11/extensions/xf86misc.h>

#include <langinfo.h>
#include <string.h>
#include <iconv.h>

#include <libintl.h>
#include <term.h>
#undef max_colors

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

#include <gdk/gdkx.h>

void initIMPS2() {
  unsigned char imps2_s1[] = { 243, 200, 243, 100, 243, 80, };
  unsigned char imps2_s2[] = { 246, 230, 244, 243, 100, 232, 3, };

  int fd = open("/dev/cdrom", O_WRONLY);
  if (fd < 0) return;

  write (fd, imps2_s1, sizeof (imps2_s1));
  usleep (30000);
  write (fd, imps2_s2, sizeof (imps2_s2));
  usleep (30000);
  tcflush (fd, TCIFLUSH);
  tcdrain(fd);
}

void log_message(const char * s, ...) {}

';

print '

MODULE = c::stuff		PACKAGE = c::stuff

';

$ENV{C_DRAKX} && $Config{archname} =~ /i.86/ and print '
char *
pcmcia_probe()
';

$ENV{C_DRAKX} and print '

int
Xtest(display)
  char *display
  CODE:
  int pid;
  if ((pid = fork()) == 0) {
    Display *d = XOpenDisplay(display);
    if (d) {
      XSetCloseDownMode(d, RetainPermanent);
      XCloseDisplay(d);
    }
    _exit(d != NULL);
  }
  waitpid(pid, &RETVAL, 0);
  OUTPUT:
  RETVAL

void
setMouseLive(display, type, emulate3buttons)
  char *display
  int type
  int emulate3buttons
  CODE:
  {
    XF86MiscMouseSettings mseinfo;
    Display *d = XOpenDisplay(display);
    if (d) {
      if (XF86MiscGetMouseSettings(d, &mseinfo) == True) {
        mseinfo.type = type;
        mseinfo.flags |= MF_REOPEN;
        mseinfo.emulate3buttons = emulate3buttons;
        XF86MiscSetMouseSettings(d, &mseinfo);
        XFlush(d);
        if (type == MTYPE_IMPS2) initIMPS2();
      }
    }
  }
';

print '

int
add_partition(hd, start_sector, size_sector, part_number)
  int hd
  unsigned long start_sector
  unsigned long size_sector
  int part_number
  CODE:
  {
    long long start = start_sector * 512;
    long long size = size_sector * 512;
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
dgettext(domainname, msgid)
   char * domainname
   char * msgid

int
KTYP(x)
  int x
  CODE:
  RETVAL = KTYP(x);
  OUTPUT:
  RETVAL

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
     ioctl(fd, FDGETDRVTYP, (void *)drivtyp);
     RETVAL = drivtyp;
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
  
int
detectSMP()

void
pci_probe(probe_type)
  int probe_type
  PPCODE:
    struct pciusb_entries entries = pci_probe(probe_type);
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
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%s\t%s\t%s\t%d\t%d", 
               e->vendor, e->device, usb_class2text(e->class_), e->module ? e->module : "unknown", e->text, e->pci_bus, e->pci_device);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    pciusb_free(&entries);

unsigned int
getpagesize()

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

char *
iconv(s, from_charset, to_charset)
  char *s
  char *from_charset
  char *to_charset
  CODE:
  iconv_t cd = iconv_open(to_charset, from_charset);
  RETVAL = s;
  if (cd != (iconv_t) (-1)) {
      size_t s_len = strlen(RETVAL);
      char *buf = alloca(3 * s_len + 10); /* 10 for safety, it should not be needed */
      {
	  char *ptr = buf;
	  size_t ptr_len = 3 * s_len + 10;
	  if ((iconv(cd, &s, &s_len, &ptr, &ptr_len)) != (size_t) (-1)) {
	      *ptr = 0;
	      RETVAL = buf;
	  }
      }
      iconv_close(cd);
  }
  OUTPUT:
  RETVAL

char *
standard_charset()
  CODE:
  RETVAL = nl_langinfo(CODESET);
  OUTPUT:
  RETVAL

';

$ENV{C_RPM} and print '
char *
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
  [ qw(int S_IFCHR S_IFBLK S_IFIFO KDSKBENT KT_SPEC NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO BLKGETSIZE LOOP_GET_STATUS
       MS_MGC_VAL MS_RDONLY O_NONBLOCK F_SETFL F_GETFL O_CREAT SECTORSIZE WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE CDROM_LOCKDOOR CDROMEJECT
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
