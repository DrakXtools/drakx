print '
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ctype.h>
#include <unistd.h>
#include <syslog.h>
#include <fcntl.h>
#include <resolv.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/mount.h>
#include <linux/keyboard.h>
#include <linux/kd.h>
#include <linux/hdreg.h>
#include <linux/vt.h>
#include <linux/cdrom.h>
#include <linux/loop.h>
#include <net/if.h>
#include <net/route.h>

#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/extensions/xf86misc.h>

#define SECTORSIZE 512
';

$ENV{C_RPM} and print '
#undef Fflush
#undef Mkdir
#undef Stat
#include <rpm/rpmlib.h>

void rpmError_callback_empty(void) {}

int rpmError_callback_data;
void rpmError_callback(void) {
  if (rpmErrorCode() != RPMERR_UNLINK && rpmErrorCode() != RPMERR_RMDIR) {
    write(rpmError_callback_data, rpmErrorString(), strlen(rpmErrorString()));
    write(rpmError_callback_data, "\n", 1);
  }
}

FD_t fd2FD_t(int fd) {
  static FD_t f = NULL;
  if (fd == -1) return NULL;
  if (f == NULL) f = fdNew("");
  fdSetFdno(f, fd);
  return f;
}

';

print '

long long llseek(int fd, long long offset,  int whence);

MODULE = c::stuff		PACKAGE = c::stuff

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
setMouseMicrosoft(display)
  char *display
  CODE:
  {
    XF86MiscMouseSettings mseinfo;
    Display *d = XOpenDisplay(display);
    if (d) {
      if (XF86MiscGetMouseSettings(d, &mseinfo) == True) {
        mseinfo.type = MTYPE_MICROSOFT;
        mseinfo.flags = 128;
        XF86MiscSetMouseSettings(d, &mseinfo);
        XFlush(d);
      }
    }
  }

void
XSetInputFocus(window)
  int window
  CODE:
  XSetInputFocus(GDK_DISPLAY(), window, RevertToParent, CurrentTime);

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
  RETVAL = llseek(fd, (long long) sector * SECTORSIZE + offset, SEEK_SET) >= 0;
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

char*
crypt_md5(pw, salt)
  char *pw
  char *salt

unsigned int
getpagesize()

int
loadFont(fontFile)
  char *fontFile
  CODE:
    char font[8192];
    unsigned short map[E_TABSZ];
    struct unimapdesc d;
    struct unimapinit u;
    struct unipair desc[2048];
    int rc = 0;

	int fd = open(fontFile, O_RDONLY);
	read(fd, font, sizeof(font));
	read(fd, map, sizeof(map));
        read(fd, &d.entry_ct, sizeof(d.entry_ct));
        d.entries = desc;
        read(fd, desc, d.entry_ct * sizeof(desc[0]));
	close(fd);

	rc = ioctl(1, PIO_FONT, font);
	rc = ioctl(1, PIO_UNIMAPCLR, &u) || rc;
	rc = ioctl(1, PIO_UNIMAP, &d) || rc;
	rc = ioctl(1, PIO_UNISCRNMAP, map) || rc;
        RETVAL = rc == 0;
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
    if (!RETVAL) close(s);
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

';

$ENV{C_RPM} and print '
int
rpmReadConfigFiles()
  CODE:
  RETVAL = rpmReadConfigFiles(NULL, NULL) == 0;
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
  RETVAL = rpmdbOpenForTraversal(root, &db) == 0 ? db : NULL;
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
  int num, count;
  Header h;
  CODE:
  if (items > 1) {
    callback = ST(1);
  }
  count = 0;
  num = rpmdbFirstRecNum(db);
  while (num>0) {
    if (callback != &PL_sv_undef && SvROK(callback)) {
      h = rpmdbGetRecord(db, num);
      {
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
      headerFree(h);
    }
    num = rpmdbNextRecNum(db, num);
    ++count;
  }
  RETVAL = count;
  OUTPUT:
  RETVAL

int
rpmdbNameTraverse(db, name, ...)
  void *db
  char *name
  PREINIT:
  SV *callback = &PL_sv_undef;
  int i, rc;
  Header h;
  rpmErrorCallBackType oldcb;
  dbiIndexSet matches;
  CODE:
  if (items > 2) {
    callback = ST(2);
  }
  rc = rpmdbFindPackage(db, name, &matches);
  if (rc == 0) {
    RETVAL = matches.count;
    if (callback != &PL_sv_undef && SvROK(callback) && matches.count > 0) {
      oldcb = rpmErrorSetCallback(rpmError_callback_empty);
      for (i = 0; i < matches.count; ++i) {
        h = rpmdbGetRecord(db, matches.recs[i].recOffset);

        {
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

        headerFree(h);
      }
      rpmErrorSetCallback(oldcb);
    }
    dbiFreeIndexRecord(matches);
  } else
    RETVAL = 0;
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
  dbiIndexSet matches;
  int i;
  int count = 0;
  if (!rpmdbFindByLabel(d, p, &matches)) {
    for (i = 0; i < dbiIndexSetCount(matches); ++i) {
      unsigned int recOffset = dbiIndexRecordOffset(matches, i);
      if (recOffset) {
        rpmtransRemovePackage(rpmdep, recOffset);
        ++count;
      }
    }
    RETVAL=count;
  } else
    RETVAL=0;
  OUTPUT:
  RETVAL

int
rpmdepOrder(order)
  void *order
  CODE:
  RETVAL = rpmdepOrder(order) == 0;
  OUTPUT:
  RETVAL

void
rpmdepCheck(rpmdep)
  void *rpmdep
  PPCODE:
  struct rpmDependencyConflict * conflicts;
  int numConflicts, i;
  rpmdepCheck(rpmdep, &conflicts, &numConflicts);
  if (numConflicts) {
    EXTEND(SP, numConflicts);
    for (i = 0; i < numConflicts; i++)
      if (conflicts[i].sense == RPMDEP_SENSE_CONFLICTS) {
        fprintf(stderr, "%s conflicts with %s\n", conflicts[i].byName, conflicts[i].needsName);
      } else {
 	if (conflicts[i].suggestedPackage)
 	  PUSHs(sv_2mortal(newSVpv((char *) conflicts[i].suggestedPackage, 0)));
 	else {
 	  char *p = malloc(100 + strlen(conflicts[i].needsName) + strlen(conflicts[i].byName));
 	  sprintf(p, "%s needed but nothing provide it (%s)", conflicts[i].needsName, conflicts[i].byName);
 	  PUSHs(sv_2mortal(newSVpv(p, 0)));
 	  free(p);
      }
    }
  }

void
rpmdepCheckFrom(rpmdep)
  void *rpmdep
  PPCODE:
  struct rpmDependencyConflict * conflicts;
  int numConflicts, i;
  rpmdepCheck(rpmdep, &conflicts, &numConflicts);
  if (numConflicts) {
    EXTEND(SP, numConflicts);
    for (i = 0; i < numConflicts; i++)
        PUSHs(sv_2mortal(newSVpv(conflicts[i].byName, 0)));
  }

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
  /* this code core dumps on install...
  static FD_t scriptFd = NULL;
  if (scriptFd == NULL) scriptFd = fdNew("");
  fdSetFdno(scriptFd, fd);
  rpmtransSetScriptFd(trans, scriptFd);
  */
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
  void *rpmRunTransactions_callback(const Header h, const rpmCallbackType what, const unsigned long amount, const unsigned long total, const void * pkgKey, void * data) {
      static FD_t fd;
      static int last_amount;
      char *msg = NULL;
      char *param_s = NULL;
      const unsigned long *param_ul1 = NULL;
      const unsigned long *param_ul2 = NULL;
      char *n = (char *) pkgKey;

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
        fd = fd2FD_t(POPi);
  	PUTBACK;
        return fd;
      }

      case RPMCALLBACK_INST_CLOSE_FILE: {
	dSP;
  	PUSHMARK(sp);
  	XPUSHs(sv_2mortal(newSVpv(n, 0)));
  	PUTBACK;
  	perl_call_sv(callbackClose, G_DISCARD);
        free(n); /* was strdup in rpmtransAddPackage  */
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
        param_s = n;

        last_amount = 0;
      } break;

      case RPMCALLBACK_INST_PROGRESS:
        if (total && (amount - last_amount) * 4 / total) {
          msg = "Progressing installing package";
          param_s = n;
          param_ul1 = &amount;
          param_ul2 = &total;

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
    EXTEND(SP, probs->numProblems);
    for (i = 0; i < probs->numProblems; i++) {
      PUSHs(sv_2mortal(newSVpv(rpmProblemString(probs->probs[i]), 0)));
    }
  }

void
rpmErrorSetCallback(fd)
  int fd
  CODE:
  rpmError_callback_data = fd;
  rpmErrorSetCallback(rpmError_callback);

void *
rpmReadPackageHeader(fd)
  int fd
  CODE:
  Header h;
  int isSource, major;
  RETVAL = rpmReadPackageHeader(fd2FD_t(fd), &h, &isSource, &major, NULL) ? NULL : h;
  OUTPUT:
  RETVAL

void *
headerRead(fd, magicp)
  int fd
  int magicp
  CODE:
  RETVAL = (void *) headerRead(fd2FD_t(fd), magicp);
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
  RETVAL = *i;
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
';

@macros = (
  [ qw(int S_IFCHR S_IFBLK KDSKBENT KT_SPEC NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO BLKGETSIZE LOOP_GET_STATUS
       MS_MGC_VAL MS_RDONLY O_NONBLOCK O_CREAT SECTORSIZE WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE CDROM_LOCKDOOR CDROMEJECT
       ) ],
);
push @macros, [ qw(int RPMTAG_NAME RPMTAG_GROUP RPMTAG_SIZE RPMTAG_VERSION RPMTAG_SUMMARY RPMTAG_DESCRIPTION RPMTAG_RELEASE RPMTAG_ARCH RPMTAG_OBSOLETES RPMTAG_REQUIRENAME RPMTAG_FILEFLAGS     RPMFILE_CONFIG) ]
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
