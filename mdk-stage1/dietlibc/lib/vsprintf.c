#include <stdarg.h>
#include <linux/types.h>
#include <unistd.h>
#include <stdlib.h>

int vsnprintf (char *str,size_t size,const char *format, va_list arg_ptr);

int vsprintf(char *str, const char *format, va_list ap)
{
	return vsnprintf(str, 1000000, format, ap);
}
