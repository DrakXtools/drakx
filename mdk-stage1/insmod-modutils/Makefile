 #******************************************************************************
 #
 #    insmod from modutils (generic)
 #
 # $Id$
 #
 # Copyright 1996, 1997 Linux International.
 #
 #*****************************************************************************

top_dir = ..

include $(top_dir)/Makefile.common


INCS = -I./include

TAINT_URL = http://www.tux.org/lkml/\#export-tainted

DEFS = -Wno-error -D_GNU_SOURCE \
       -DELF_MACHINE_H='"elf_$(ARCH).h"' -DARCH_$(ARCH) \
       -DTAINT_URL='"$(TAINT_URL)"'


DIRS = util obj

all: dirs insmod libinsmod.a

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done

clean:
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done
	rm -rf t *.o insmod libinsmod.a


insmod: insmod-frontend.o insmod.o ./util/libutil-STANDALONE.a ./obj/libobj.a
	$(DIET) gcc -o $@ $^
	$(STRIPCMD) $@

t/.create_stuff: util/libutil.a obj/libobj.a
	rm -rf t
	mkdir t
	cd t &&	for e in $^; do ar -x ../$$e; done
	touch t/.create_stuff

libinsmod.a: insmod.o t/.create_stuff
	ar cru $@ insmod.o t/*
	ranlib $@

insmod-frontend.o: insmod-frontend.c insmod.c
	$(DIET) gcc $(CFLAGS) $(DEFS) $(INCS) $(INCLUDES) -c insmod-frontend.c

insmod.o: insmod.c
	$(DIET) gcc $(CFLAGS) $(DEFS) $(INCS) $(INCLUDES) -c insmod.c
