#include "dietfeatures.h"
#include <stdarg.h>
#include <sys/types.h>
#include <stdlib.h>
#include <string.h>

extern int __ltostr(char *s, int size, unsigned long i, int base, char UpCase);
extern int __dtostr(double d,char *buf,int maxlen,int prec);

#include <unistd.h>
void print_int(int fd, int i)
{
	char buf[10];
	char * chptr = buf + 9;
	int j = 0;
	
	if (i < 0)
	{
		write(1, "-", 1);
		i = -1 * i;
	}
	
	while (i)
	{
		*chptr-- = '0' + (i % 10);
		j++;
		i = i / 10;
	}
	
	write(fd, chptr + 1, j);
}

int vsnprintf (char *str, size_t size, const char *format, va_list arg_ptr)
{
  size_t apos,i;
  char ch,buf[1024];
  char *pb;
  char flag_in_sign;
  char flag_hash,flag_zero,flag_left,flag_space,flag_sign,flag_dot,flag_long;
  long number,width,preci,buf_len,pad;
  char padwith;

  size--;

  apos=0;
  while (apos<size)
  {
    ch=*format++;
    switch (ch)
    {
    case '%':
      flag_hash=0;
      flag_zero=0;
      flag_left=0;
      flag_space=0;
      flag_sign=0;
      flag_dot=0;
      flag_in_sign=0;
      flag_long=0;

      width=0;
      padwith=' ';

inn_vsnprintf:
      if (apos>=size) continue; /* ARGL !!! */

      ch=*format++;
      switch (ch)
      {
/* Format end ?!? */
      case 0:
	return -1;
	break;

/* Format flag chars */
      case '#':
	flag_hash=1;
	goto inn_vsnprintf;

      case 'l':
	flag_long=1;
	goto inn_vsnprintf;

      case '0':
	padwith='0';
	goto inn_vsnprintf;

      case '-':
	flag_left=1;
	goto inn_vsnprintf;

      case ' ':
	flag_space=1;
	goto inn_vsnprintf;

      case '+':
	flag_sign=1;
	goto inn_vsnprintf;

      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
	if(flag_dot) return -1;
	width=strtol(--format,&pb,10);
	format=pb;
	goto inn_vsnprintf;

      case '.':
	flag_dot=1;
	preci=strtol(format,&pb,10);
	format=pb;
	goto inn_vsnprintf;

/* Format conversion chars */
      case 'c':
	ch=(char)va_arg(arg_ptr,int);
      case '%':
	if (str) str[apos]=ch; ++apos;
	break;

      case 's':
	pb=va_arg(arg_ptr,char *);
#ifdef WANT_NULL_PRINTF
	if (!pb) pb="(null)";
#endif
	buf_len=strlen(pb);

print_out:
	if (str) {
	  if (width && (!flag_left))
	  {
	    for (pad=width-buf_len; pad>0; --pad) str[apos++]=padwith;
	  }
	  for(i=0;(pb[i])&&(apos<size);i++) { str[apos++]=pb[i]; } /* strncpy */
	  if (width && (flag_left))
	  {
	    for (pad=width-buf_len; pad>0; --pad) str[apos++]=padwith;
	  }
	} else {
	  if (width)
	    apos+=width;
	  else {
	    int a=strlen(pb);
	    if (a>size) apos+=size; else apos+=a;
	  }
	}

	break;

	/* Numbers */
      case 'b':
	i=2;
	goto num_vsnprintf;
      case 'p':
	flag_hash=1;
	width=sizeof(void *)<<1;
	padwith='0';
	ch='x';
      case 'X':
      case 'x':
	i=16;
	if (flag_hash)
	{
	  if (str) {
	    str[apos++]='0';
	    str[apos++]=ch;
	  } else
	    apos+=2;
	}
	goto num_vsnprintf;
      case 'd':
      case 'i':
	flag_in_sign=1;
      case 'u':
	i=10;
	goto num_vsnprintf;
      case 'o':
	i=8;
	if (flag_hash) { if (str) str[apos]='0'; ++apos; }

num_vsnprintf:
	if (apos>=size) continue; /* ARGL !!! */

	if (flag_long)
	  number=va_arg(arg_ptr,long);
	else
	  number=va_arg(arg_ptr,int);

	if (flag_in_sign && (number<0))
	{
	  number*=-1;
	  flag_in_sign=2;
	}

	buf_len=__ltostr(buf+1,sizeof(buf)-1,(unsigned long) number,i,0);
	pb=buf+1;

	if (flag_in_sign==2)
	{
	  *(--pb)='-';
	  buf_len++;
	}
	else if ((flag_in_sign)&&(flag_sign || flag_space))
	{
	  *(--pb)=(flag_sign)?'+':' ';
	  buf_len++;
	}
	goto print_out;

#ifdef WANT_FLOATING_POINT_IN_PRINTF
      case 'g':
	{
	  double d=va_arg(arg_ptr,double);
	  buf_len=__dtostr(d,buf,sizeof(buf),6);
	  pb=buf;
	  goto print_out;
	}
#endif
      default:
	break;
      }
      break;
    case 0:
      if (str) str[apos]=0;
      return apos;
    default:
      if (str) str[apos]=ch; apos++;
      break;
    }
  }
  if (str) str[apos]=0;
  return apos;
}
