#include <stdarg.h>
#include <linux/types.h>
#include <unistd.h>
#include <stdlib.h>

int vsnprintf (char *str,size_t size,const char *format, va_list arg_ptr);

int vprintf(const char *format, va_list ap)
{
  char tmp[1000000];
  size_t n = vsnprintf(tmp, sizeof(tmp), format, ap);
  write(1, tmp, n);
  return n;
}
