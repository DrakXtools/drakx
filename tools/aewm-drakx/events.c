/* aewm - a minimalistic X11 window manager. ------- vim:sw=4:et
 * Copyright (c) 1998-2001 Decklin Foster <decklin@red-bean.com>
 * Free software! Please see README for details and license.  */

#include "aewm.h"


static void handle_configure_request(XConfigureRequestEvent *e)
{
    XWindowChanges wc;

    wc.x = e->x;
    wc.y = e->y;
    wc.width = e->width;
    wc.height = e->height;
    wc.sibling = e->above;
    wc.stack_mode = e->detail;
    XConfigureWindow(dpy, e->window, e->value_mask, &wc);
}

static void handle_map_request(XMapRequestEvent *e)
{
    Client *c = find_client(e->window);

    if (c) {
        XMapWindow(dpy, c->window);
        set_wm_state(c, NormalState);
	set_focus_on(c->window);
    } else {
        make_new_client(e->window);
    }
}

static void handle_destroy_event(XDestroyWindowEvent *e)
{
    Client *c = find_client(e->window);

    if (c) remove_client(c);
}


#ifdef DEBUG
#define SHOW_EV(name, memb) \
    case name: s = #name; w = e.memb.window; break;
#define SHOW(name) \
    case name: return #name;

void show_event(XEvent e)
{
    char *s = 0, buf[20];
    char *dd = 0;
    Window w = 0;
    Client *c;

    switch (e.type) {
        SHOW_EV(ButtonPress, xbutton)
        SHOW_EV(ButtonRelease, xbutton)
        SHOW_EV(ClientMessage, xclient)
        SHOW_EV(ColormapNotify, xcolormap)
        SHOW_EV(ConfigureNotify, xconfigure)
        SHOW_EV(ConfigureRequest, xconfigurerequest)
        SHOW_EV(CreateNotify, xcreatewindow)
        SHOW_EV(DestroyNotify, xdestroywindow)
        SHOW_EV(EnterNotify, xcrossing)
        SHOW_EV(Expose, xexpose)
        SHOW_EV(MapNotify, xmap)
        SHOW_EV(MapRequest, xmaprequest)
        SHOW_EV(MappingNotify, xmapping)
        SHOW_EV(MotionNotify, xmotion)
        SHOW_EV(PropertyNotify, xproperty)
        SHOW_EV(ReparentNotify, xreparent)
        SHOW_EV(ResizeRequest, xresizerequest)
        SHOW_EV(UnmapNotify, xunmap)
        default:
            break;
    }

    c = find_client(w);

    if (c) XFetchName(dpy, c->window, &dd);

    snprintf(buf, sizeof buf, dd ? dd : "");
    err("%#-10lx: %-20s: %s", w, buf, s);
}
#endif


void do_event_loop(void)
{
    XEvent ev;

    for (;;) {
        XNextEvent(dpy, &ev);
#ifdef DEBUG
	show_event(ev);
#endif
        switch (ev.type) {
            case ConfigureRequest:
                handle_configure_request(&ev.xconfigurerequest); break;
            case MapRequest:
                handle_map_request(&ev.xmaprequest); break;
            case DestroyNotify:
                handle_destroy_event(&ev.xdestroywindow); break;
        }
    }
}
