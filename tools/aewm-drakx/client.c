/* aewm - a minimalistic X11 window manager. ------- vim:sw=4:et
 * Copyright (c) 1998-2001 Decklin Foster <decklin@red-bean.com>
 * Free software! Please see README for details and license.  */

#include "aewm.h"
#include <X11/Xmd.h>


Client *head_client = NULL;

Client *find_client(Window w)
{
    Client *c;

    for (c = head_client; c; c = c->next)
      if (c->window == w) return c;

    return NULL;
}


void set_focus_on(Window w)
{
    char *name;
    XFetchName(dpy, w, &name);
    if (name && strcmp(name, "skip")) {
	XSetInputFocus(dpy, w, RevertToPointerRoot, CurrentTime);
#ifdef DEBUG
	printf("aewm-drakx: adding %ld %s\n", w, name);
#endif
    }
}

/* Attempt to follow the ICCCM by explicity specifying 32 bits for
 * this property. Does this goof up on 64 bit systems? */
void set_wm_state(Client *c, int state)
{
    CARD32 data[2];

    data[0] = state;
    data[1] = None; /* Icon? We don't need no steenking icon. */

    XChangeProperty(dpy, c->window, wm_state, wm_state,
        32, PropModeReplace, (unsigned char *)data, 2);
}

/* If we can't find a WM_STATE we're going to have to assume
 * Withdrawn. This is not exactly optimal, since we can't really
 * distinguish between the case where no WM has run yet and when the
 * state was explicitly removed (Clients are allowed to either set the
 * atom to Withdrawn or just remove it... yuck.) */
long get_wm_state(Client *c)
{
    Atom real_type; int real_format;
    unsigned long items_read, items_left;
    long *data, state = WithdrawnState;

    if (XGetWindowProperty(dpy, c->window, wm_state, 0L, 2L, False,
            wm_state, &real_type, &real_format, &items_read, &items_left,
            (unsigned char **) &data) == Success && items_read) {
        state = *data;
        XFree(data);
    }
    return state;
}

void remove_client(Client *c)
{
    int ignore_xerror(Display *dpy, XErrorEvent *e) { return 0; }

    Client *p;

    XGrabServer(dpy);
    XSetErrorHandler(ignore_xerror);

    set_wm_state(c, WithdrawnState);

    if (head_client == c) head_client = c->next;
    else for (p = head_client; p && p->next; p = p->next)
        if (p->next == c) p->next = c->next;

    free(c);

    if (head_client) set_focus_on(head_client->window);

    XSync(dpy, False);
    XSetErrorHandler(handle_xerror);
    XUngrabServer(dpy);
}

void make_new_client(Window w)
{
    Client *c;
    XWindowAttributes attr;

    c = malloc(sizeof *c);
    c->next = head_client;
    c->window = w;
    head_client = c;

    XGrabServer(dpy);
    XGetWindowAttributes(dpy, w, &attr);


    if (attr.map_state != IsViewable) {
        XWMHints *hints;
        set_wm_state(c, NormalState);
        if ((hints = XGetWMHints(dpy, w))) {
            if (hints->flags & StateHint) set_wm_state(c, hints->initial_state);
            XFree(hints);
        }
    }
    if (attr.map_state == IsViewable) {
      XMapWindow(dpy, c->window);
      set_wm_state(c, NormalState);
    } else if (get_wm_state(c) == NormalState) {
      XMapWindow(dpy, c->window);
    }
    set_focus_on(w);

    XSync(dpy, False);
    XUngrabServer(dpy);
}
