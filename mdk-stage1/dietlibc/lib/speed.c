#include <unistd.h>
#include <termios.h>
#include <sys/types.h>

#include <asm/errno.h>

extern int errno;

/* Hack around a kernel bug; value must correspond to the one used in tcsetattr.c */
#define IBAUD0	020000000000


/* Return the output baud rate stored in *TERMIOS_P.  */
speed_t cfgetospeed (struct termios *termios_p)
{
	return termios_p->c_cflag & (CBAUD | CBAUDEX);
}


/* Return the input baud rate stored in *TERMIOS_P.
   Although for Linux there is no difference between input and output
   speed, the numerical 0 is a special case for the input baud rate. It
   should set the input baud rate to the output baud rate. */
speed_t cfgetispeed (struct termios *termios_p)
{
	return ((termios_p->c_iflag & IBAUD0)
		? 0 : termios_p->c_cflag & (CBAUD | CBAUDEX));
}


/* Set the output baud rate stored in *TERMIOS_P to SPEED.  */
int cfsetospeed (struct termios *termios_p, speed_t speed)
{
	if ((speed & ~CBAUD) != 0 && (speed < B57600 || speed > B460800)) {
		errno = EINVAL;
		return -1;
	}
	
	termios_p->c_cflag &= ~(CBAUD | CBAUDEX);
	termios_p->c_cflag |= speed;
	
	return 0;
}


/* Set the input baud rate stored in *TERMIOS_P to SPEED.
   Although for Linux there is no difference between input and output
   speed, the numerical 0 is a special case for the input baud rate.  It
   should set the input baud rate to the output baud rate.  */
int cfsetispeed (struct termios *termios_p, speed_t speed)
{
	if ((speed & ~CBAUD) != 0 && (speed < B57600 || speed > B460800)) {
		errno = EINVAL;
		return -1;
	}
	
	if (speed == 0)
		termios_p->c_iflag |= IBAUD0;
	else
	{
		termios_p->c_iflag &= ~IBAUD0;
		termios_p->c_cflag &= ~(CBAUD | CBAUDEX);
		termios_p->c_cflag |= speed;
	}
	
	return 0;
}
