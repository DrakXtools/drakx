 #******************************************************************************
 #
 #    insmod from busybox (i386 only)
 #
 # $Id$
 #
 # Copyright (C) 1999,2000 by Lineo, inc.
 #
 #*****************************************************************************

top_dir = ..

include $(top_dir)/Makefile.common


all: insmod insmod-DIET libinsmod.a libinsmod-DIET.a

clean:
	rm -f *.o insmod insmod-DIET libinsmod.a libinsmod-DIET.a


FLAGS = -c -Wall -Os -fomit-frame-pointer -D_GNU_SOURCE -DBB_VER='"0.60.5"' -DBB_BT='"2003.04.16-15:25+0000"'


insmod: insmod-frontend.o insmod.o utility-standalone.o
	gcc -o $@ $^
	$(STRIPCMD) $@

insmod-DIET: insmod-frontend-DIET.o insmod-DIET.o utility-standalone-DIET.o
	gcc $(DIETLIBC_LDFLAGS_STAGE1) -o $@ $^ $(DIETLIBC_LIBC)
	$(STRIPCMD) $@


libinsmod.a: insmod.o utility.o
	ar cru $@ $^
	ranlib $@

libinsmod-DIET.a: insmod-DIET.o utility-DIET.o
	ar cru $@ $^
	ranlib $@

insmod-frontend.o: insmod-frontend.c busybox.h
	gcc $(FLAGS) $(GLIBC_INCLUDES) insmod-frontend.c

insmod-frontend-DIET.o: insmod-frontend.c busybox.h
	gcc $(FLAGS) $(DIETLIBC_INCLUDES) -o $@ insmod-frontend.c

utility.o: utility.c busybox.h
	gcc $(FLAGS) $(GLIBC_INCLUDES) utility.c

utility-DIET.o: utility.c busybox.h
	gcc $(FLAGS) $(DIETLIBC_INCLUDES) -o $@ utility.c

utility-standalone.o: utility.c busybox.h
	gcc $(FLAGS) $(GLIBC_INCLUDES) -o $@ -D_STANDALONE_ utility.c

utility-standalone-DIET.o: utility.c busybox.h
	gcc $(FLAGS) $(DIETLIBC_INCLUDES) -o $@ -D_STANDALONE_ utility.c

insmod.o: insmod.c busybox.h
	gcc $(FLAGS) $(GLIBC_INCLUDES) insmod.c

insmod-DIET.o: insmod.c busybox.h
	gcc $(FLAGS) $(DIETLIBC_INCLUDES) -o $@ insmod.c

