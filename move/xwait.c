#include <stdlib.h>
#include <X11/Xlib.h>

int main() {
  Display *display = XOpenDisplay(NULL);

  if (display) {
    XEvent event;
    
    XSelectInput(display, DefaultRootWindow(display), SubstructureNotifyMask);
    do {
      XNextEvent(display, &event);
    } while (event.type != CreateNotify);
    XCloseDisplay(display);
  }

  exit(display == NULL);
}
