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
#include <langinfo.h>
#include <string.h>
#include <iconv.h>

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
syslog(mesg)
  char *mesg
  CODE:
  syslog(LOG_WARNING, mesg);

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
      struct pciusb_entry e = entries.entries[i];
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%04x\t%04x\t%d\t%d\t%d\t%s\t%s\t%s", 
               e.vendor, e.device, e.subvendor, e.subdevice, e.pci_bus, e.pci_device, e.pci_function,
               pci_class2text(e.class), e.module ? e.module : "unknown", e.text);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    pciusb_free(entries);

void
usb_probe()
  PPCODE:
    struct pciusb_entries entries = usb_probe();
    char buf[2048];
    int i;

    EXTEND(SP, entries.nb);
    for (i = 0; i < entries.nb; i++) {
      struct pciusb_entry e = entries.entries[i];
      snprintf(buf, sizeof(buf), "%04x\t%04x\t%s\t%s\t%s", 
               e.vendor, e.device, usb_class2text(e.class), e.module ? e.module : "unknown", e.text);
      PUSHs(sv_2mortal(newSVpv(buf, 0)));
    }
    pciusb_free(entries);

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
set_loop(dev_fd, file)
  int dev_fd
  char *file
  CODE:
  RETVAL = 0;
{
  struct loop_info loopinfo;
  int file_fd = open(file, O_RDWR);

  if (file_fd < 0) return;

  memset(&loopinfo, 0, sizeof(loopinfo));
  strncpy(loopinfo.lo_name, file, LO_NAME_SIZE);
  loopinfo.lo_name[LO_NAME_SIZE - 1] = 0;

  if (ioctl(dev_fd, LOOP_SET_FD, file_fd) < 0) return;
  if (ioctl(dev_fd, LOOP_SET_STATUS, &loopinfo) < 0) {
    ioctl(dev_fd, LOOP_CLR_FD, 0);
    return;
  }
  close(file_fd);
  RETVAL = 1;
}
  OUTPUT:
  RETVAL

int
del_loop(device)
  char *device
  CODE:
  RETVAL = 0;
{
  int fd;
  if ((fd = open(device, O_RDONLY)) < 0) return;
  if (ioctl(fd, LOOP_CLR_FD, 0) < 0) return;
  close(fd);
  RETVAL = 1;
}
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
';

$ENV{C_RPM} and print '
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

int
rpmReadConfigFiles()
  CODE:
  char *rpmrc = getenv("RPMRC_FILE");
  if (rpmrc != NULL && !*rpmrc) rpmrc = NULL;
  RETVAL = rpmReadConfigFiles(rpmrc, NULL) == 0;
  OUTPUT:
  RETVAL

int
rpmdbInit(root, perms)
  char *root
  int perms
  CODE:
  RETVAL = rpmdbInit(root, perms) == 0;
  OUTPUT:
  RETVAL

void *
rpmdbOpen(root)
  char *root
  CODE:
  static rpmdb db;
  RETVAL = rpmdbOpen(root, &db, O_RDWR | O_CREAT, 0644) == 0 ||
           rpmdbOpen(root, &db, O_RDONLY, 0644) == 0 ? db : NULL;
  OUTPUT:
  RETVAL

void *
rpmdbOpenForTraversal(root)
  char *root
  CODE:
  static rpmdb db;
  rpmErrorCallBackType old_cb;
  old_cb = rpmErrorSetCallback(rpmError_callback_empty);
  rpmSetVerbosity(RPMMESS_FATALERROR);
  RETVAL = rpmdbOpen(root, &db, O_RDONLY, 0644) == 0 ? db : NULL;
  rpmErrorSetCallback(old_cb);
  rpmSetVerbosity(RPMMESS_NORMAL);
  OUTPUT:
  RETVAL

void
rpmdbClose(db)
  void *db

int
rpmdbTraverse(db, ...)
  void *db
  PREINIT:
  SV *callback = &PL_sv_undef;
  int count;
  Header h;
  rpmdbMatchIterator mi;
  CODE:
  if (items > 1) {
    callback = ST(1);
  }
  count = 0;
  mi = rpmdbInitIterator(db, RPMDBI_PACKAGES, NULL, 0);
  while (h = rpmdbNextIterator(mi)) {
    if (callback != &PL_sv_undef && SvROK(callback)) {
      dSP;
      ENTER;
      SAVETMPS;
      PUSHMARK(sp);
      XPUSHs(sv_2mortal(newSViv((IV)(void *)h)));
      PUTBACK;
      perl_call_sv(callback, G_DISCARD | G_SCALAR);
      FREETMPS;
      LEAVE;
    }
    ++count;
  }
  rpmdbFreeIterator(mi);
  RETVAL = count;
  OUTPUT:
  RETVAL

int
rpmdbNameTraverse(db, name, ...)
  void *db
  char *name
  PREINIT:
  SV *callback = &PL_sv_undef;
  int count;
  Header h;
  rpmdbMatchIterator mi;
  rpmErrorCallBackType oldcb;
  CODE:
  if (items > 2) {
    callback = ST(2);
  }
  count = 0;
  mi = rpmdbInitIterator(db, RPMTAG_NAME, name, 0);
  oldcb = rpmErrorSetCallback(rpmError_callback_empty);
  while (h = rpmdbNextIterator(mi)) {
    if (callback != &PL_sv_undef && SvROK(callback)) {
      dSP;
      ENTER;
      SAVETMPS;
      PUSHMARK(sp);
      XPUSHs(sv_2mortal(newSViv((IV)(void *)h)));
      PUTBACK;
      perl_call_sv(callback, G_DISCARD | G_SCALAR);
      FREETMPS;
      LEAVE;
    }
    ++count;
  }
  rpmErrorSetCallback(oldcb);
  rpmdbFreeIterator(mi);
  RETVAL = count;
  OUTPUT:
  RETVAL


void *
rpmtransCreateSet(db, rootdir)
  void *db
  char *rootdir

void
rpmtransAvailablePackage(rpmdep, header, key)
  void *rpmdep
  void *header
  char *key
  CODE:
  rpmtransAvailablePackage(rpmdep, header, strdup(key));

int
rpmtransAddPackage(rpmdep, header, key, update)
  void *rpmdep
  void *header
  char *key
  int update
  CODE:
  rpmTransactionSet r = rpmdep;
  RETVAL = rpmtransAddPackage(r, header, NULL, strdup(key), update, NULL) == 0;
  /* rpminstall.c of rpm-4 call headerFree directly after, we can make the same ?*/
  OUTPUT:
  RETVAL

int
rpmtransRemovePackages(db, rpmdep, p)
  void *db
  void *rpmdep
  char *p
  CODE:
  rpmdb d = db;
  rpmTransactionSet r = rpmdep;
  Header h;
  rpmdbMatchIterator mi;
  int count = 0;
  mi = rpmdbInitIterator(db, RPMDBI_LABEL, p, 0);
  while (h = rpmdbNextIterator(mi)) {
    unsigned int recOffset = rpmdbGetIteratorOffset(mi);
    if (recOffset) {
      rpmtransRemovePackage(rpmdep, recOffset);
      ++count;
    }
  }
  rpmdbFreeIterator(mi);
  RETVAL=count;
  OUTPUT:
  RETVAL

int
rpmdepOrder(order)
  void *order
  CODE:
  RETVAL = rpmdepOrder(order) == 0;
  OUTPUT:
  RETVAL

int
rpmdbRebuild(root)
  char *root
  CODE:
  rpmErrorCallBackType old_cb;
  old_cb = rpmErrorSetCallback(rpmError_callback_empty);
  rpmSetVerbosity(RPMMESS_FATALERROR);
  RETVAL = rpmdbRebuild(root) == 0;
  rpmErrorSetCallback(old_cb);
  rpmSetVerbosity(RPMMESS_NORMAL);
  OUTPUT:
  RETVAL

void
rpmtransFree(trans)
  void *trans

char *
rpmErrorString()

int
rpmVersionCompare(headerFirst, headerSecond)
  void *headerFirst
  void *headerSecond

void
rpmSetVeryVerbose()
  CODE:
  rpmSetVerbosity(RPMMESS_DEBUG);

void
rpmtransSetScriptFd(trans, fd)
  void *trans
  int fd
  CODE:
  static FD_t scriptFd = NULL;
  if (scriptFd != NULL) fdClose(scriptFd);
  scriptFd = fdDup(fd);
  rpmtransSetScriptFd(trans, scriptFd);

void
rpmRunTransactions(trans, callbackOpen, callbackClose, callbackMessage, force)
  void *trans
  SV *callbackOpen
  SV *callbackClose
  SV *callbackMessage
  int force
  PPCODE:
  rpmProblemSet probs;
  void *rpmRunTransactions_callback(const void *h, const rpmCallbackType what, const unsigned long amount, const unsigned long total, const void * pkgKey, void * data) {
      static int last_amount;
      static FD_t fd = NULL;
      char *msg = NULL;
      char *param_s = NULL;
      const unsigned long *param_ul1 = NULL;
      const unsigned long *param_ul2 = NULL;
      char *n = (char *) pkgKey;
      static struct timeval tprev;
      static struct timeval tcurr;
      long delta;

      switch (what) {
      case RPMCALLBACK_INST_OPEN_FILE: {
        int i;
  	dSP;
  	PUSHMARK(sp);
  	XPUSHs(sv_2mortal(newSVpv(n, 0)));
  	PUTBACK;
  	i = perl_call_sv(callbackOpen, G_SCALAR);
        SPAGAIN;
        if (i != 1) croak("Big trouble\n");
        i = POPi; fd = fdDup(i);
	fd = fdLink(fd, "persist DrakX");
  	PUTBACK;
        return fd;
      }

      case RPMCALLBACK_INST_CLOSE_FILE: {
	dSP;
  	PUSHMARK(sp);
  	XPUSHs(sv_2mortal(newSVpv(n, 0)));
  	PUTBACK;
  	perl_call_sv(callbackClose, G_DISCARD);
        free(n); /* was strdup in rpmtransAddPackage */
	fd = fdFree(fd, "persist DrakX");
	if (fd) {
	  fdClose(fd);
	  fd = NULL;
	}
  	break;
      }

      case RPMCALLBACK_TRANS_START: {
        switch (amount) {
        case 1: msg = "Examining packages to install..."; break;
        case 5: msg = "Examining files to install..."; break;
        case 6: msg = "Finding overlapping files..."; break;
        }
        if (msg) param_ul1 = &total;
      } break;

      case RPMCALLBACK_UNINST_START: {
        msg = "Removing old files...";
        param_ul1 = &total;
      } break;

      case RPMCALLBACK_TRANS_PROGRESS: {
        msg = "Progressing transaction";
        param_ul1 = &amount;
      } break;

      case RPMCALLBACK_UNINST_PROGRESS: {
        msg = "Progressing removing old files";
        param_ul1 = &amount;
      } break;

      case RPMCALLBACK_TRANS_STOP: {
        msg = "Done transaction";
      } break;

      case RPMCALLBACK_UNINST_STOP: {
        msg = "Done removing old files";
      } break;

      case RPMCALLBACK_INST_START: {
        msg = "Starting installing package";
	gettimeofday(&tprev, NULL);
        param_s = n;

        last_amount = 0;
      } break;

      case RPMCALLBACK_INST_PROGRESS:
        gettimeofday(&tcurr, NULL);
        delta = 1000000 * (tcurr.tv_sec - tprev.tv_sec) + (tcurr.tv_usec - tprev.tv_usec);
        if (delta > 200000 || amount >= total - 1) { /* (total && (amount - last_amount) * 22 / 4 / total)) { */
          msg = "Progressing installing package";
          param_s = n;
          param_ul1 = &amount;
          param_ul2 = &total;

	  tprev = tcurr;
          last_amount = amount;
  	} break;
      default: break;
      }

      if (msg) {
        dSP ;
        PUSHMARK(sp) ;
  	XPUSHs(sv_2mortal(newSVpv(msg, 0)));
        if (param_s) {
  	  XPUSHs(sv_2mortal(newSVpv(param_s, 0)));
        }
        if (param_ul1) {
  	  XPUSHs(sv_2mortal(newSViv(*param_ul1)));
        }
        if (param_ul2) {
          XPUSHs(sv_2mortal(newSViv(*param_ul2)));
        }
  	PUTBACK ;
  	perl_call_sv(callbackMessage, G_DISCARD);
      }
      return NULL;
  }
  if (rpmRunTransactions(trans, rpmRunTransactions_callback, NULL, NULL, &probs, 0, force ? ~0 : ~RPMPROB_FILTER_DISKSPACE)) {
    int i;
    /* printf("rpmRunTransactions finished, errors occured %d\n", probs->numProblems); fflush(stdout); */
    EXTEND(SP, probs->numProblems);
    for (i = 0; i < probs->numProblems; i++) {
      PUSHs(sv_2mortal(newSVpv(rpmProblemString(&probs->probs[i]), 0)));
    }
  }

void
rpmErrorSetCallback(fd)
  int fd
  CODE:
  rpmError_callback_data = fd;
  rpmErrorSetCallback(rpmError_callback);

void *
rpmReadPackageHeader(fdno)
  int fdno
  CODE:
  Header h;
  int isSource, major;
  FD_t fd = fdDup(fdno);
  RETVAL = rpmReadPackageHeader(fd, &h, &isSource, &major, NULL) ? NULL : h;
  fdClose(fd);
  OUTPUT:
  RETVAL

void *
headerRead(fdno, magicp)
  int fdno
  int magicp
  CODE:
  FD_t fd = fdDup(fdno);
  RETVAL = (void *) headerRead(fd, magicp);
  fdClose(fd);
  OUTPUT:
  RETVAL

void
headerFree(header)
  void *header

char *
headerGetEntry_string(h, query)
  void *h
  int query
  CODE:
  int type, count;
  headerGetEntry((Header) h, query, &type, (void **) &RETVAL, &count);
  OUTPUT:
  RETVAL

int
headerGetEntry_int(h, query)
  void *h
  int query
  CODE:
  int type, count, *i;
  headerGetEntry((Header) h, query, &type, (void **) &i, &count);
  RETVAL = i ? *i : 0; /* assume non existant value as 0 (needed for EPOCH (SERIAL)) */
  OUTPUT:
  RETVAL

void
headerGetEntry_int_list(h, query)
  void *h
  int query
  PPCODE:
  int i, type, count = 0;
  int_32 *intlist = (int_32 *) NULL;
  if (headerGetEntry((Header) h, query, &type, (void**) &intlist, &count)) {
    if (count > 0) {
      EXTEND(SP, count);
      for (i = 0; i < count; i++) {
        PUSHs(sv_2mortal(newSViv(intlist[i])));
      }
    }
  }

void
headerGetEntry_string_list(h, query)
  void *h
  int query
  PPCODE:
  int i, type, count = 0;
  char **strlist = (char **) NULL;
  if (headerGetEntry((Header) h, query, &type, (void**) &strlist, &count)) {
    if (count > 0) {
      EXTEND(SP, count);
      for (i = 0; i < count; i++) {
        PUSHs(sv_2mortal(newSVpv(strlist[i], 0)));
      }
    }
    free(strlist);
  }

void
headerGetEntry_filenames(h)
  void *h
  PPCODE:
  int i, type, count = 0;
  char ** baseNames, ** dirNames;
  int_32 * dirIndexes;
  char **strlist = (char **) NULL;

  if (headerGetEntry((Header) h, RPMTAG_OLDFILENAMES, &type, (void**) &strlist, &count)) {
    if (count > 0) {
      EXTEND(SP, count);
      for (i = 0; i < count; i++) {
        PUSHs(sv_2mortal(newSVpv(strlist[i], 0)));
      }
    }
    free(strlist);
  } else {

    headerGetEntry(h, RPMTAG_BASENAMES, &type, (void **) &baseNames, &count);
    headerGetEntry(h, RPMTAG_DIRINDEXES, &type, (void **) &dirIndexes, NULL);
    headerGetEntry(h, RPMTAG_DIRNAMES, &type, (void **) &dirNames, NULL);

    if (baseNames && dirNames && dirIndexes) {
      EXTEND(SP, count);
      for(i = 0; i < count; i++) {
        char *p = malloc(strlen(dirNames[dirIndexes[i]]) + strlen(baseNames[i]) + 1);
        if (p == NULL) croak("malloc failed");
        strcpy(p, dirNames[dirIndexes[i]]);
        strcat(p, baseNames[i]);
  	PUSHs(sv_2mortal(newSVpv(p, 0)));
        free(p);
      }
      free(baseNames);
      free(dirNames);
    }
  }

int rpmvercmp(char *a, char *b);
';

@macros = (
  [ qw(int S_IFCHR S_IFBLK S_IFIFO KDSKBENT KT_SPEC NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO BLKGETSIZE LOOP_GET_STATUS
       MS_MGC_VAL MS_RDONLY O_NONBLOCK F_SETFL F_GETFL O_CREAT SECTORSIZE WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE CDROM_LOCKDOOR CDROMEJECT
       ) ],
);
push @macros, [ qw(int RPMTAG_NAME RPMTAG_GROUP RPMTAG_SIZE RPMTAG_VERSION RPMTAG_SUMMARY RPMTAG_DESCRIPTION RPMTAG_RELEASE RPMTAG_EPOCH RPMTAG_ARCH RPMTAG_OBSOLETES RPMTAG_REQUIRENAME RPMTAG_FILEFLAGS     RPMFILE_CONFIG) ]
  if $ENV{C_RPM};

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
