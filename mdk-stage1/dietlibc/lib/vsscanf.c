#include "dietfeatures.h"
#include <stdarg.h>
#include <sys/types.h>
#include <ctype.h>
#include <stdlib.h>

const char *skip_ws(const char *str)
{
  while ((*str)&&(isspace(*str))) str++;
  return str;
}

extern double strtod(const char *s,char **f);

int vsscanf(const char *str, const char *format, va_list arg_ptr)
{
  int n=0,div;
  char ch;

  char flag_discard, flag_malloc, flag_half, flag_long, flag_longlong;
  char flag_width;

  unsigned long width;

#ifdef WANT_FLOATING_POINT_IN_SCANF
  /* arg_ptr tmps */
  double d,*pd;
  float *pf;
#endif

  long l=0,*pl;
  short *ph;
  int *pi;
  char *s;

  while ((*str)&&(*format))
  {
    const char *prevfmt=format;
    format=skip_ws(format);
    ch=*format++;
    if (!ch) continue;

    switch (ch)
    {
    case '%':
      div=0;
      flag_discard=0;
      flag_malloc=0;
      flag_half=0;
      flag_long=0;
      flag_longlong=0;

      flag_width=0;
      width=-1;

inn_vsscanf:
      ch=*format++;

      switch (ch)
      {
      case 0:
	return 0;

      case '%':
	if (*(str++)!=ch) return n;
	break;

      /* flags */
      case '*':
	flag_discard=1;
	goto inn_vsscanf;

      case 'a':
	flag_malloc=1;
	goto inn_vsscanf;

      case 'h':
	flag_half=1;
	goto inn_vsscanf;

      case 'l':
	if (flag_long) flag_longlong=1;
	flag_long=1;
	goto inn_vsscanf;

	/* longlong ? NOT YET ! */
      case 'q':
      case 'L':
	flag_longlong=1;
	goto inn_vsscanf;

      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
	width=strtol(format-1,&s,10);
	format=s;
	flag_width=1;
	goto inn_vsscanf;

      /* conversion */

      case 'n':
	while (width && *str)
	{
	  *(s++)=*(str++);
	  --width;
	  l++;
	}
	if (!flag_discard)
	{
	  pl=(long *)va_arg(arg_ptr,long*);
	  *pl=l;
	  ++n;
	}
	break;

      case 'p':
      case 'X':
      case 'x':
	div+=6;
      case 'd':
	div+=2;
      case 'o':
	div+=8;
      case 'u':
      case 'i':
	if (*(str=skip_ws(str)))
	{
	  l=strtol(str,&s,div);
	  if (str!=s)
	  {
	    if (!flag_discard)
	    {
	      if (flag_long)
	      {
		pl=(long *)va_arg(arg_ptr,long*);
		*pl=l;
	      }
	      else if (flag_half)
	      {
		ph=(short *)va_arg(arg_ptr,short*);
		*ph=l;
	      }
	      else
	      {
		pi=(int *)va_arg(arg_ptr,int*);
		*pi=l;
	      }
	      ++n;
	    }
	    str=s;
	  }
	  else
	    return n;
	}
	break;

#ifdef WANT_FLOATING_POINT_IN_SCANF
      case 'e':
      case 'E':
      case 'f':
      case 'g':
	if (*(str=skip_ws(str)))
	{
	  d=strtod(str,&s);
	  if (str!=s)
	  {
	    if (!flag_discard)
	    {
	      if (flag_long)
	      {
		pd=(double *)va_arg(arg_ptr,double*);
		*pd=d;
	      }
	      else
	      {
		pf=(float *)va_arg(arg_ptr,float*);
		*pf=d;
	      }
	      ++n;
	    }
	    str=s;
	  }
	  else
	    return n;
	}
	break;
#endif

      case 'c':
	if (!flag_discard)
	{
	  s=(char *)va_arg(arg_ptr,char*);
	  ++n;
	}
	if (!flag_width) width=1;
	while (width && *str)
	{
	  if (!flag_discard) *(s++)=*(str);
	  ++str;
	  --width;
	}
	break;

      case 's':
	if (!flag_discard)
	{
	  s=(char *)va_arg(arg_ptr,char*);
	  ++n;
	}
	if (*(str=skip_ws(str)))
	{
	  while (width && *str && (!isspace(*str)))
	  {
	    if (!flag_discard) *(s++)=*(str);
	    ++str;
	    --width;
	  }
	  *s = '\0';
	}
	break;
      }
      break;

    default:
      if (prevfmt<format) {
	while (prevfmt<format) {
	  if (*str!=*prevfmt) return n;
	  ++str; ++prevfmt;
	}
      } else
	if (*(str++)!=ch) return n;
      break;
    }
  }
  return n;
}
