#ifndef _LINUX_POSIX_TYPES_H
#define _LINUX_POSIX_TYPES_H

/*
 * This allows for 1024 file descriptors: if NR_OPEN is ever grown
 * beyond that you'll have to change this too. But 1024 fd's seem to be
 * enough even for such "real" unices like OSF/1, so hopefully this is
 * one limit that doesn't have to be changed [again].
 *
 * Note that POSIX wants the FD_CLEAR(fd,fdsetp) defines to be in
 * <sys/time.h> (and thus <linux/time.h>) - but this is a more logical
 * place for them. Solved by having dummy defines in <sys/time.h>.
 */

/*
 * Those macros may have been defined in <gnu/types.h>. But we always
 * use the ones here. 
 */
#undef __NFDBITS
#define __NFDBITS	(8 * sizeof(unsigned long))

#undef __FD_SETSIZE
#define __FD_SETSIZE	1024

#undef __FDSET_LONGS
#define __FDSET_LONGS	(__FD_SETSIZE/__NFDBITS)

#undef __FDELT
#define	__FDELT(d)	((d) / __NFDBITS)

#undef __FDMASK
#define	__FDMASK(d)	(1UL << ((d) % __NFDBITS))

typedef struct {
	unsigned long fds_bits [__FDSET_LONGS];
} __kernel_fd_set;

#ifndef __KERNEL_STRICT_NAMES
typedef __kernel_fd_set fd_set;
#endif

#if defined(__KERNEL__) || !defined(__GLIBC__) || (__GLIBC__ < 2)

#undef __FD_SET
static __inline__ void __FD_SET(unsigned long fd, __kernel_fd_set *fdsetp)
{
	unsigned long _tmp = fd / __NFDBITS;
	unsigned long _rem = fd % __NFDBITS;
	fdsetp->fds_bits[_tmp] |= (1UL<<_rem);
}

#undef __FD_CLR
static __inline__ void __FD_CLR(unsigned long fd, __kernel_fd_set *fdsetp)
{
	unsigned long _tmp = fd / __NFDBITS;
	unsigned long _rem = fd % __NFDBITS;
	fdsetp->fds_bits[_tmp] &= ~(1UL<<_rem);
}

#undef __FD_ISSET
static __inline__ int __FD_ISSET(unsigned long fd, __const__ __kernel_fd_set *p)
{
	unsigned long _tmp = fd / __NFDBITS;
	unsigned long _rem = fd % __NFDBITS;
	return (p->fds_bits[_tmp] & (1UL<<_rem)) != 0;
}

/*
 * This will unroll the loop for the normal constant cases (8 or 32 longs,
 * for 256 and 1024-bit fd_sets respectively)
 */
#undef __FD_ZERO
static __inline__ void __FD_ZERO(__kernel_fd_set *p)
{
	unsigned long *tmp = p->fds_bits;
	int i;

	if (__builtin_constant_p(__FDSET_LONGS)) {
		switch (__FDSET_LONGS) {
			case 32:
			  tmp[ 0] = 0; tmp[ 1] = 0; tmp[ 2] = 0; tmp[ 3] = 0;
			  tmp[ 4] = 0; tmp[ 5] = 0; tmp[ 6] = 0; tmp[ 7] = 0;
			  tmp[ 8] = 0; tmp[ 9] = 0; tmp[10] = 0; tmp[11] = 0;
			  tmp[12] = 0; tmp[13] = 0; tmp[14] = 0; tmp[15] = 0;
			  tmp[16] = 0; tmp[17] = 0; tmp[18] = 0; tmp[19] = 0;
			  tmp[20] = 0; tmp[21] = 0; tmp[22] = 0; tmp[23] = 0;
			  tmp[24] = 0; tmp[25] = 0; tmp[26] = 0; tmp[27] = 0;
			  tmp[28] = 0; tmp[29] = 0; tmp[30] = 0; tmp[31] = 0;
			  return;
			case 16:
			  tmp[ 0] = 0; tmp[ 1] = 0; tmp[ 2] = 0; tmp[ 3] = 0;
			  tmp[ 4] = 0; tmp[ 5] = 0; tmp[ 6] = 0; tmp[ 7] = 0;
			  tmp[ 8] = 0; tmp[ 9] = 0; tmp[10] = 0; tmp[11] = 0;
			  tmp[12] = 0; tmp[13] = 0; tmp[14] = 0; tmp[15] = 0;
			  return;
			case 8:
			  tmp[ 0] = 0; tmp[ 1] = 0; tmp[ 2] = 0; tmp[ 3] = 0;
			  tmp[ 4] = 0; tmp[ 5] = 0; tmp[ 6] = 0; tmp[ 7] = 0;
			  return;
			case 4:
			  tmp[ 0] = 0; tmp[ 1] = 0; tmp[ 2] = 0; tmp[ 3] = 0;
			  return;
		}
	}
	i = __FDSET_LONGS;
	while (i) {
		i--;
		*tmp = 0;
		tmp++;
	}
}

#endif /* defined(__KERNEL__) */

#endif /* _LINUX_POSIX_TYPES_H */
