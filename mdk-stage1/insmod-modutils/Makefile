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

DEFS = -Wno-error -D_GNU_SOURCE -DELF_MACHINE_H='"elf_$(ARCH).h"' -DARCH_$(ARCH)


DIRS = util obj

all: dirs insmod libinsmod.a #libinsmod-DIET.a

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done

clean:
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done
	rm -rf t *.o insmod libinsmod.a libinsmod-DIET.a


insmod: insmod-frontend.o insmod.o ./util/libutil-STANDALONE.a ./obj/libobj.a
	gcc -o $@ $^
	$(STRIPCMD) $@

t/.create_stuff: util/libutil.a obj/libobj.a
	rm -rf t
	mkdir t
	cd t &&	for e in $^; do ar -x ../$$e; done
	touch t/.create_stuff

libinsmod.a: insmod.o t/.create_stuff
	ar cru $@ insmod.o t/*
	ranlib $@

libinsmod-DIET.a: insmod-DIET.o ./util/libutil-DIET.a ./obj/libobj-DIET.a
	ar cru $@ $^
	ranlib $@

insmod-frontend.o: insmod-frontend.c insmod.c
	gcc $(CFLAGS) $(DEFS) $(INCS) $(GLIBC_INCLUDES) -c insmod-frontend.c

insmod.o: insmod.c
	gcc $(CFLAGS) $(DEFS) $(INCS) $(GLIBC_INCLUDES) -c insmod.c

insmod-DIET.o: insmod.c
	gcc $(CFLAGS) $(DEFS) $(INCS) $(DIETLIBC_INCLUDES) -o $@ -c insmod.c

