#include <stdarg.h>
#include <linux/types.h>
#include <unistd.h>
#include <stdlib.h>

int vsnprintf (char *str,size_t size,const char *format, va_list arg_ptr);

int vprintf(const char *format, va_list ap)
{
  int n;
  char *printf_buf;
/*  char printf_buf[1024]; */
  va_list temp = ap;
  n=vsnprintf(0,1000000,format,temp);
/*  write(1,printf_buf,strlen(printf_buf)); */
  printf_buf=alloca(n+2);
  n=vsnprintf(printf_buf,n+1,format,ap);
  write(1,printf_buf,n);
  return n;
}
