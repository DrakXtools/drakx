 #******************************************************************************
 #
 #    insmod from modutils (generic)
 #
 # $Id$
 #
 # Copyright 1996, 1997 Linux International.
 #
 #*****************************************************************************

top_dir = ../..

include $(top_dir)/Makefile.common


all: libobj.a

clean:
	rm -f *.o *.a


INCS = -I./../include

DEFS = -D_GNU_SOURCE -DELF_MACHINE_H='"elf_$(ARCH).h"' -DARCH_$(ARCH) -DCONFIG_ROOT_CHECK_OFF=0

OBJS = obj_kallsyms.o obj_common.o obj_load.o obj_reloc.o obj_$(ARCH).o

libobj.a: $(OBJS)
	ar cru $@ $^
	ranlib $@

.c.o:
	gcc $(CFLAGS) $(DEFS) $(INCS) $(GLIBC_INCLUDES) -c $<
