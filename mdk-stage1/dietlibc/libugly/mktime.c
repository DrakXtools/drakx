#include <time.h>

/* seconds per day */
#define SPD 24*60*60

extern unsigned int __spm[];

time_t mktime(struct tm *t) {
  time_t x=0;
  unsigned int i;
  if (t->tm_year<70) return (time_t)(-1);
  for (i=70; i<t->tm_year; ++i) {
    x+=__isleap(i+1900)?366:365;
  }
  t->tm_yday=__spm[t->tm_mon] + t->tm_mday-1 + ((t->tm_mon>2) && __isleap(t->tm_year)?1:0);
  x+=t->tm_yday;
  /* x is now the number of days since Jan 1 1970 */
  t->tm_wday=(4+x)%7;
  x = x*SPD + t->tm_hour*60*60 + t->tm_min*60 + t->tm_sec;
  return x;
}
