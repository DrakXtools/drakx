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


all: libutil.a libutil-STANDALONE.a

clean:
	rm -f *.o *.a


INCS = -I./../include

DEFS = -Wno-error -D_GNU_SOURCE -DELF_MACHINE_H='"elf_$(ARCH).h"' -DARCH_$(ARCH) -DHAVE_WORDEXP=1 -DHAVE_GLOB=1 -DCONFIG_ROOT_CHECK_OFF=0


OBJS = xmalloc.o xrealloc.o xstrcat.o xstrdup.o xsystem.o xftw.o \
        modstat.o meta_expand.o config.o snap_shot.o arch64.o gzfiles.o sys_nim.o sys_oim.o

libutil.a: $(OBJS) logger.o
	ar cru $@ $^
	ranlib $@

libutil-STANDALONE.a: $(OBJS) logger-standalone.o
	ar cru $@ $^
	ranlib $@

logger-standalone.o: logger.c
	$(DIET) gcc $(CFLAGS) $(DEFS) $(INCS) $(INCLUDES) -o $@ -D_STANDALONE_ -c logger.c

%.o: %.c
	$(DIET) gcc $(CFLAGS) $(DEFS) $(INCS) $(INCLUDES) -c $<
