#include "syscalls.h"

.text
.global fork
fork:
	mov	2, %g1
	ta	0x10
	bcc,a	1f
	nop

	sethi   %hi(errno), %o3
	or      %o3, %lo(errno), %o3
	st	%i0, [%o3]

	retl
	mov	-1, %o0
1:	dec	%o1
	retl
	and	%o0, %o1, %o0
