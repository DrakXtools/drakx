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


all: insmod libinsmod.a

clean:
	rm -f *.o insmod libinsmod.a


FLAGS = -c -Wall -Os -fomit-frame-pointer -D_GNU_SOURCE -DBB_VER='"0.60.5"' -DBB_BT='"2003.04.16-15:25+0000"'


insmod: insmod-frontend.o insmod.o utility-standalone.o
	$(DIET) gcc -o $@ $^
	$(STRIPCMD) $@

libinsmod.a: insmod.o utility.o
	ar cru $@ $^
	ranlib $@

insmod-frontend.o: insmod-frontend.c busybox.h
	$(DIET) gcc $(FLAGS) $(INCLUDES) insmod-frontend.c

utility.o: utility.c busybox.h
	$(DIET) gcc $(FLAGS) $(INCLUDES) utility.c

utility-standalone.o: utility.c busybox.h
	$(DIET) gcc $(FLAGS) $(INCLUDES) -o $@ -D_STANDALONE_ utility.c

insmod.o: insmod.c busybox.h
	$(DIET) gcc $(FLAGS) $(INCLUDES) insmod.c
