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

VERSION = cooker


ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))


CFLAGS = -Os -Wall -Werror -fomit-frame-pointer
INCLUDES = -I.
DEFS = -DVERSION=\"$(VERSION)\"

COMPILE = $(CC) $(DEFS) $(INCLUDES) $(CFLAGS)


 #- stage1 "loader"
INITSRC = minilibc.c init.c

INITOBJS = $(subst .c,.o,$(INITSRC))


 #- frontends
NEWT_FRONTEND_SRC = newt-frontend.c
NEWT_FRONTEND_LIBS = /usr/lib/libnewt.a /usr/lib/libslang.a

STDIO_FRONTEND_SRC = stdio-frontend.c
STDIO_FRONTEND_LIBS =

WSLIB_FRONTEND_SRC = wslib-frontend.c
WSLIB_FRONTEND_LIBS = /usr/lib/libwslib.a

 #- default frontend is newt
F = NEWT

FRONTEND_OBJS = $(subst .c,.o,$($(F)_FRONTEND_SRC))
FRONTEND_LIBS = $($(F)_FRONTEND_LIBS)


STAGE1_OWN_LIBS = insmod-busybox/libinsmod.a mar/libmar.a

STAGE1_OTHER_LIBS = /usr/lib/libz.a

STAGE1_NETWORK_LIBS = /usr/lib/libresolv.a


 #- stage1 itself
STAGE1SRC = stage1.c log.c tools.c modules.c probing.c mount.c automatic.c
CDROMSRC = cdrom.c
DISKSRC = disk.c
NETWORKSRC = network.c dns.c nfsmount.c

ALLSRC = $(INITSRC) $(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC)


STAGE1OBJS = $(subst .c,.o,$(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC))

STAGE1OBJS_UTILS = $(FRONTEND_OBJS) $(STAGE1_OWN_LIBS) $(FRONTEND_LIBS) $(STAGE1_OTHER_LIBS)


STAGE1OBJS-CDROM = $(subst .c,-CDROM.o,$(STAGE1SRC) $(CDROMSRC))

CDROM_DEFS = -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS-DISK = $(subst .c,-DISK.o,$(STAGE1SRC) $(DISKSRC))

DISK_DEFS = -DDISABLE_CDROM -DDISABLE_NETWORK


STAGE1OBJS-NETWORK = $(subst .c,-NETWORK.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_DEFS = -DDISABLE_CDROM -DDISABLE_DISK





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


BINS = init stage1-full stage1-cdrom stage1-network stage1-disk


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

DIRS = mar insmod-busybox pci-resource


all: dirs $(BINS)

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done


init: $(INITOBJS)
	$(CC) $(LDFLAGS_INIT) -o $@ $(INITOBJS)
	strip -s $@

stage1-cdrom: $(STAGE1_OWN_LIBS) $(STAGE1OBJS-CDROM) $(STAGE1OBJS_UTILS)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $(STAGE1OBJS-CDROM) $(STAGE1OBJS_UTILS)
	strip -s $@

stage1-network: $(STAGE1_OWN_LIBS) $(STAGE1OBJS-NETWORK) $(STAGE1OBJS_UTILS)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $(STAGE1OBJS-NETWORK) $(STAGE1OBJS_UTILS) $(STAGE1_NETWORK_LIBS)
	strip -s $@

stage1-disk: $(STAGE1_OWN_LIBS) $(STAGE1OBJS-DISK) $(STAGE1OBJS_UTILS)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $(STAGE1OBJS-DISK) $(STAGE1OBJS_UTILS)
	strip -s $@

stage1-pcmcia: $(STAGE1_OWN_LIBS) $(STAGE1OBJS-PCMIA) $(STAGE1OBJS_UTILS)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $(STAGE1OBJS-PCMIA) $(STAGE1OBJS_UTILS)
	strip -s $@

stage1-full: $(STAGE1_OWN_LIBS) $(STAGE1OBJS) $(STAGE1OBJS_UTILS)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $(STAGE1OBJS) $(STAGE1OBJS_UTILS) $(STAGE1_NETWORK_LIBS)
	strip -s $@


#stage1-network-diet: $(STAGE1OBJS) stage1-network.o $(NETOBJS)
#	 gcc -nostdlib -o $@ ../../../tmp/dietlibc/start.o $^ ../../../tmp/dietlibc/dietlibc.a
#	 strip -s $@


$(STAGE1OBJS-CDROM): %-CDROM.o: %.c
	$(COMPILE) $(CDROM_DEFS) -c $< -o $@

$(STAGE1OBJS-DISK): %-DISK.o: %.c
	$(COMPILE) $(DISK_DEFS) -c $< -o $@

$(STAGE1OBJS-NETWORK): %-NETWORK.o: %.c
	$(COMPILE) $(NETWORK_DEFS) -c $< -o $@

.c.o:
	$(COMPILE) -c $<


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
