#define tcsetattr libc_tcsetattr
#include <termios.h>
#include <sys/ioctl.h>
#undef tcsetattr

#include <asm/errno.h>

extern int errno;

int tcsetattr(int fildes, int optional_actions, struct termios *termios_p)
{
  switch (optional_actions) {
  case TCSANOW:
    return ioctl(fildes, TCSETS, termios_p);
  case TCSADRAIN:
    return ioctl(fildes, TCSETSW, termios_p);
  case TCSAFLUSH:
    return ioctl(fildes, TCSETSF, termios_p);
  default:
    errno = EINVAL;
    return -1;
  }
}
