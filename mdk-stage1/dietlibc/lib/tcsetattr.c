#define tcsetattr libc_tcsetattr
#include <termios.h>
#include <sys/ioctl.h>
#undef tcsetattr

#include <asm/errno.h>

extern int errno;

/* Hack around a kernel bug; value must correspond to the one used in speed.c */
#define IBAUD0	020000000000

int tcsetattr(int fildes, int optional_actions, struct termios *termios_p)
{
  termios_p->c_iflag &= ~IBAUD0;
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
