#include "start.h"

#ifdef __i386__
.text
.globl _start
_start:
#if 0
	popl	%ecx
	movl	%esp, %edx
	leal	4(%esp,%ecx,4),%eax
#else
	movl (%esp),%ecx	/* %ecx = argc */
	leal 4(%esp),%edx	/* %edx = argv */

	leal 4(%edx,%ecx,4),%eax	/* eax = 4*ecx+4 = envp */
#endif
	pushl %eax
	pushl %edx
	pushl %ecx
	movl %eax,environ

	call main
	pushl %eax
	call exit
.Lfefe:
	.size	 _start,.Lfefe-_start
#endif

