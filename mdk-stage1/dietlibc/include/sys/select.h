#ifndef _SYS_SELECT_H
#define _SYS_SELECT_H	1

int select(int n, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);

#endif
