#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

int vfprintf(FILE *fstream, const char *format, va_list ap)
{
  char tmp[1000000];
  size_t n = vsnprintf(tmp, sizeof(tmp), format, ap);
  fwrite(tmp, n, 1, fstream);
  return n;
}
