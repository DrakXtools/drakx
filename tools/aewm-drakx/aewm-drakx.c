/* aewm - a minimalistic X11 window manager. ------- vim:sw=4:et
 * Copyright (c) 1998-2001 Decklin Foster <decklin@red-bean.com>
 * Free software! Please see README for details and license.  */

#include "aewm.h"


Display *dpy;
Window root;

static void scan_wins(void)
{
    unsigned int nwins, i;
    Window dummyw1, dummyw2, *wins;
    XWindowAttributes attr;

    XQueryTree(dpy, root, &dummyw1, &dummyw2, &wins, &nwins);
    for (i = 0; i < nwins; i++) {
        XGetWindowAttributes(dpy, wins[i], &attr);
        if (!attr.override_redirect && attr.map_state == IsViewable)
            make_new_client(wins[i]);
    }
    XFree(wins);
}

static void setup_display(void)
{
    XSetWindowAttributes sattr;

    dpy = XOpenDisplay(NULL);

    if (!dpy) {
        err("can't open display! check your DISPLAY variable.");
        exit(1);
    }

    XSetErrorHandler(handle_xerror);
    root = RootWindow(dpy, DefaultScreen(dpy));

    sattr.event_mask = SubstructureRedirectMask|SubstructureNotifyMask;
    XChangeWindowAttributes(dpy, root, CWEventMask, &sattr);
}


int main()
{
    setup_display();
    scan_wins();
    do_event_loop();
}
