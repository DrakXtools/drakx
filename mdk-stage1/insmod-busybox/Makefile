 #******************************************************************************
 #
 #    insmod from busybox (i386 only)
 #
 # $Id$
 #
 # Copyright (C) 1999,2000 by Lineo, inc.
 #
 #*****************************************************************************


all: insmod libinsmod.a

clean:
	rm -f *.o insmod

FLAGS = -c -Wall -Os -fomit-frame-pointer -D_GNU_SOURCE -DBB_VER='"0.47"' -DBB_BT='"2000.12.06-14:02+0000"'

insmod: insmod-frontend.o insmod.o utility-standalone.o
	gcc -o $@ $^

libinsmod.a: insmod.o utility.o
	ar cru $@ $^
	ranlib $@

insmod-frontend.o: insmod-frontend.c busybox.h
	gcc $(FLAGS) insmod-frontend.c

utility.o: utility.c busybox.h
	gcc $(FLAGS) utility.c

utility-standalone.o: utility.c busybox.h
	gcc $(FLAGS) -o $@ -D_STANDALONE_ utility.c

insmod.o: insmod.c busybox.h
	gcc $(FLAGS) insmod.c

