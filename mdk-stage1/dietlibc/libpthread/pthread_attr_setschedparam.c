#include <unistd.h>
#include <errno.h>

#include <pthread.h>
#include "thread_internal.h"

int pthread_attr_setschedparam(pthread_attr_t *attr, const struct sched_param *param)
{
  __THREAD_INIT();

  if ((attr->__schedpolicy == SCHED_OTHER) && (param->sched_priority == 0)) {
    attr->__schedparam.sched_priority=0;
    return 0;
  }
  if (((attr->__schedpolicy == SCHED_RR) || (attr->__schedpolicy == SCHED_RR))
      && ((param->sched_priority > 0) && (param->sched_priority < 100))) {
    attr->__schedparam.sched_priority=param->sched_priority;
    return 0;
  }
  (*(__errno_location()))=EINVAL;
  return -1;
}

