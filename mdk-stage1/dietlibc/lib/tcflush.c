#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>

#include <asm/errno.h>

extern int errno;

/* Flush pending data on FD.  */
int tcflush(int fd, int queue_selector)
{
	switch (queue_selector) {
	case TCIFLUSH:
		return ioctl(fd, TCFLSH, 0);
	case TCOFLUSH:
		return ioctl(fd, TCFLSH, 1);
	case TCIOFLUSH:
		return ioctl(fd, TCFLSH, 2);
	default:
		errno = EINVAL;
		return -1;
	}
}
