/* aewm - a minimalistic X11 window manager. ------- vim:sw=4:et
 * Copyright (c) 1998-2001 Decklin Foster <decklin@red-bean.com>
 * Free software! Please see README for details and license.  */

#include "aewm.h"
#include <stdarg.h>


void err(const char *fmt, ...)
{
    va_list argp;

    fprintf(stderr, "aewm: ");
    va_start(argp, fmt);
    vfprintf(stderr, fmt, argp);
    va_end(argp);
    fprintf(stderr, "\n");
}

int handle_xerror(Display *dpy, XErrorEvent *e)
{
    Client *c = find_client(e->resourceid);
    
    char msg[255];
    XGetErrorText(dpy, e->error_code, msg, sizeof msg);
    err("X error (%#lx): %s", e->resourceid, msg);

    return 0;
}
