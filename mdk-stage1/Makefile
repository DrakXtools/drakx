 #******************************************************************************
 #
 #    mdk-stage1 - the program that will load second-stage install
 #
 # $Id$
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2000 MandrakeSoft
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 #
 # Portions from Erik Troan (ewt@redhat.com) Copyright 1996 Red Hat Software 
 #
 #*****************************************************************************

VERSION = 7.2cooker


ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))


 #- We can leave "-g" forever since stripping will remove everything
CFLAGS = -Os -g -Wall -Werror -fomit-frame-pointer
INCLUDES = -I.
DEFS = -D_GNU_SOURCE=1 -DVERSION=\"$(VERSION)\"

COMPILE = $(CC) $(DEFS) $(INCLUDES) $(CFLAGS)


 #- stage1 "loader"
INITSRC = minilibc.c init.c

INITOBJS = $(subst .c,.o,$(INITSRC))


 #- stage1 itself (minus stage1.c)
STAGE1SRC = log.c tools.c modules.c probing.c newt-frontend.c cdrom.c disk.c network.c mount.c

STAGE1OBJS = $(subst .c,.o,$(STAGE1SRC)) insmod-busybox/libinsmod.a mar/libmar.a /usr/lib/libnewt.a /usr/lib/libslang.a /usr/lib/libz.a


ALLSRC = $(INITSRC) $(STAGE1SRC) stage1.c


ifeq (i386, $(ARCH))
MINILIC=minilibc.o
LDFLAGS_INIT = -static -nostdlib /usr/lib/crt1.o
LDFLAGS_STAGE1 = -static
STATIC=-static
endif
ifeq (sparc, $(ARCH))
MINILIBC=minilibc.o /usr/lib/libc.a
LDFLAGS_INIT = -static -nostdlib /usr/lib/crt1.o
LDFLAGS_STAGE1 = -static
endif


BINS = init stage1-network


#ifeq (i386, $(ARCH))
#BINS += stage1-all stage1-cdrom stage1-network stage1-hd stage1-pcmcia
#endif
#
#ifeq (ia64, $(ARCH))
#BINS += stage1-all
#endif
#
#ifeq (alpha, $(ARCH))
#BINS += stage1-all
#endif
#
#ifeq (sparc, $(ARCH))
#BINS += stage1-all
#endif

DIRS = mar insmod-busybox


all: dirs $(BINS)

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done


init: $(INITOBJS)
	$(CC) $(LDFLAGS_INIT) -o $@ $(INITOBJS)
	strip -s $@

stage1-network: stage1-network.o $(STAGE1OBJS) $(NETOBJS)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $^
	strip -s $@

stage1-network-diet: $(STAGE1OBJS) stage1-network.o $(NETOBJS)
	gcc -nostdlib -o $@ ../../../tmp/dietlibc/start.o $^ ../../../tmp/dietlibc/dietlibc.a
	strip -s $@

.c.o:
	$(COMPILE) -c $<

stage1-network.o: stage1.c
	$(COMPILE) -c $< -o $@


clean: 
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done
	rm -f *.o .depend *.rdz *.img $(BINS)

deps:
	$(CPP) $(CFLAGS) -DHAVE_CONFIG_H -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif                                           
