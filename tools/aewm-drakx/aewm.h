/* aewm - a minimalistic X11 window manager. ------- vim:sw=4:et
 * Copyright (c) 1998-2001 Decklin Foster <decklin@red-bean.com>
 * Free software! Please see README for details and license.  */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <X11/Xutil.h>

typedef struct _Client Client;

struct _Client {
    Client	*next;
    Window	window;
};

extern Display *dpy;
extern Atom wm_state;

/* events.c */
extern void do_event_loop(void);

/* client.c */
extern Client *find_client(Window);
extern void set_wm_state(Client *, int);
extern void remove_client(Client *);
extern void make_new_client(Window);

/* misc.c */
void err(const char *, ...);
int handle_xerror(Display *, XErrorEvent *);

