#ifndef _SYS_TIMES_H
#define _SYS_TIMES_H

#include <linux/times.h>

clock_t times(struct tms *buf);

#endif
