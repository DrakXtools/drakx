#include <stdlib.h>
#include <X11/Xlib.h>


int main(int argc, char **argv) {
  Display *d = XOpenDisplay(getenv("DISPLAY") ? getenv("DISPLAY") : ":0");
  if (d == NULL) exit(1);
  XDisableAccessControl(d);
  XCloseDisplay(d);
  exit(0);
}
