#ifndef _SYS_FILE_H
#define _SYS_FILE_H

#include <sys/cdefs.h>

extern int fcntl(int fd, int cmd, ...) __THROW;
extern int flock(int fd, int operation) __THROW;

/* Operations for the `flock' call.  */
#define	LOCK_SH	1	/* Shared lock.  */
#define	LOCK_EX	2 	/* Exclusive lock.  */
#define	LOCK_UN	8	/* Unlock.  */

/* Can be OR'd in to one of the above.  */
#define	LOCK_NB	4	/* Don't block when locking.  */



#endif	/* _SYS_FILE_H */
