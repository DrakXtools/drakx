#include "syscalls.h"

.text
.global pipe
pipe:
	mov	__NR_pipe, %g1
	ta 0x10
	bcc,a	.Lnoerror
	nop
	save	%sp, -96, %sp
	call	__errno_location
	nop
	st	%i0, [ %o0 ]
	ret
	restore	%g0, -1, %o0
.Lnoerror:
	st	%o0, [ %o2 ]
	st	%o1, [ %o2 + 4 ]
	retl
	mov	%g0, %o0
