#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <X11/Xlib.h>
#include <X11/extensions/xf86misc.h>

#include <term.h>
#undef max_colors

void initIMPS2() {
  unsigned char imps2_s1[] = { 243, 200, 243, 100, 243, 80, };
  unsigned char imps2_s2[] = { 246, 230, 244, 243, 100, 232, 3, };

  int fd = open("/dev/mouse", O_WRONLY);
  if (fd < 0) return;

  write (fd, imps2_s1, sizeof (imps2_s1));
  usleep (30000);
  write (fd, imps2_s2, sizeof (imps2_s2));
  usleep (30000);
  tcflush (fd, TCIFLUSH);
  tcdrain(fd);
}

MODULE = xf86misc::main		PACKAGE = xf86misc::main

PROTOTYPES: DISABLE


int
Xtest(display)
  char *display
  CODE:
  int pid;
  if ((pid = fork()) == 0) {
    Display *d = XOpenDisplay(display);
    if (d) {
      int child;
      /* keep a client until some window is created, otherwise X server blinks to hell */
      if ((child = fork()) == 0) {
        XEvent event;
        XSelectInput(d, DefaultRootWindow(d), SubstructureNotifyMask);
        do {
          XNextEvent(d, &event);
        } while (event.type != CreateNotify);
        XCloseDisplay(d);
        exit(0);
      }
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
