#include <stdlib.h>
#include <X11/Xlib.h>

int main(int argc, char **argv) {
  int permanent = argc > 1 && !strcmp(argv[1], "-permanent");
  Display *display = XOpenDisplay(NULL);

  if (display) {
    XEvent event;
    
    XSelectInput(display, DefaultRootWindow(display), SubstructureNotifyMask);
    do {
      XNextEvent(display, &event);
    } while (event.type != CreateNotify || permanent);
    XCloseDisplay(display);
  }

  exit(display == NULL);
}
