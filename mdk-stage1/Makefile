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
 #
 # Currently:
 #
 # 	ix86
 # init with minilibc
 # stage1 with dietlibc except some targets
 #
 # 	ppc
 # init with dietlibc
 # stage1 with glibc
 #
 # 	ia64
 # init with glibc
 # stage1 with glibc
 #
 #*****************************************************************************


VERSION = 8.1

top_dir = .

include $(top_dir)/Makefile.common


DEFS = -DVERSION=\"$(VERSION)\" -DSPAWN_SHELL

COMPILE = $(CC) $(DEFS) $(CFLAGS)


 #- stage1 "loader"
ifeq (i386, $(ARCH))
INITSRC = minilibc.c init.c
INIT_DEFS = -DINIT_HEADERS=\"minilibc.h\"
else
INITSRC = init.c
ifeq (ia64, $(ARCH))
INIT_DEFS = -DINIT_HEADERS=\"init-libc-headers.h\" $(GLIBC_INCLUDES)
else
INIT_DEFS = -DINIT_HEADERS=\"init-libc-headers.h\" $(DIETLIBC_INCLUDES)
endif
endif

INITOBJS = $(subst .c,.o,$(INITSRC))


 #- frontends
NEWT_FRONTEND_SRC = newt-frontend.c
GLIBC_NEWT_FRONTEND_LIBS = newt/libnewt.a slang/libslang.a
DIETLIBC_NEWT_FRONTEND_LIBS = $(subst .a,-DIET.a,$(GLIBC_NEWT_FRONTEND_LIBS))

STDIO_FRONTEND_SRC = stdio-frontend.c
GLIBC_STDIO_FRONTEND_LIBS =
DIETLIBC_STDIO_FRONTEND_LIBS =


FRONTEND_OBJS = $(subst .c,.o,$($(F)_FRONTEND_SRC))

FRONTEND_LINK = $(FRONTEND_OBJS) $($(L)_$(F)_FRONTEND_LIBS)

ifeq (i386, $(ARCH))
INSMOD = insmod-busybox
else
INSMOD = insmod-modutils
endif

GLIBC_STAGE1_OWN_LIBS = $(INSMOD)/libinsmod.a mar/libmar.a bzlib/libbzlib.a
DIETLIBC_STAGE1_OWN_LIBS = $(subst .a,-DIET.a,$(GLIBC_STAGE1_OWN_LIBS))
STAGE1_OWN_LIBS = $($(L)_STAGE1_OWN_LIBS)


ifeq (DIETLIBC, $(L))
STAGE1_NETWORK_LIBS = $(top_dir)/dietlibc/bin-$(ARCH)/librpc.a
endif

ifeq (GLIBC, $(L))
STAGE1_NETWORK_LIBS = /usr/lib/libresolv.a
endif

 #- stage1 itself
STAGE1SRC = stage1.c log.c tools.c modules.c probing.c mount.c automatic.c frontend-common.c
CDROMSRC = cdrom.c
DISKSRC = disk.c lomount.c
NETWORKSRC = network.c nfsmount.c dhcp.c url.c dns.c adsl.c

ALLSRC = $(INITSRC) $(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC)



STAGE1OBJS-CDROM = $(subst .c,-CDROM.o,$(STAGE1SRC) $(CDROMSRC))

CDROM_DEFS = -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS-DISK = $(subst .c,-DISK.o,$(STAGE1SRC) $(DISKSRC))

DISK_DEFS = -DDISABLE_CDROM -DDISABLE_NETWORK


STAGE1OBJS-NETWORK = $(subst .c,-NETWORK.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_DEFS = -DDISABLE_CDROM -DDISABLE_DISK


STAGE1OBJS-USBNET = $(subst .c,-USBNET.o,$(STAGE1SRC) $(NETWORKSRC))


STAGE1OBJS-FULL = $(subst .c,-FULL.o,$(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC))


ifeq (i386, $(ARCH))
LDFLAGS_INIT = -static -nostdlib /usr/lib/crt1.o
else
ifeq (ia64, $(ARCH))
LDFLAGS_INIT = $(GLIBC_LDFLAGS_STAGE1)
INIT_LIBC = $(GLIBC_LIBC)
else
LDFLAGS_INIT = $(DIETLIBC_LDFLAGS_STAGE1)
INIT_LIBC = $(DIETLIBC_LIBC)
endif
endif


BINS = init stage1-full

ifeq (i386, $(ARCH))
BINS += stage1-cdrom stage1-disk stage1-network stage1-usbnet
endif

ifneq (ia64, $(ARCH))
DIRS = dietlibc
endif
DIRS += mar pci-resource usb-resource bzlib $(INSMOD) slang newt ppp/pppd rp-pppoe/src
ifeq (i386,$(ARCH))
DIRS += pcmcia
endif


ifeq (i386,$(ARCH))
GLIBC_PCMCIA_LIB = pcmcia/libpcmcia.a
DIETLIBC_PCMCIA_LIB = $(subst .a,-DIET.a,$(GLIBC_PCMCIA_LIB))
PCMCIA_LIB = $($(L)_PCMCIA_LIB)
PCMCIA_DEFS = -DENABLE_PCMCIA
endif


USBNET_DEFS_GEN = -DENABLE_USB -DENABLE_USBNET
USBNET_DEFS = $(USBNET_DEFS_GEN) -DDISABLE_PCINET

all: dirs $(BINS)

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done

init: $(INITOBJS) $(INIT_LIBC)
	$(CC) $(LDFLAGS_INIT) -o $@ $^
	$(STRIPCMD) $@

stage1-cdrom: $(STAGE1OBJS-CDROM) $(STAGE1_OWN_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $^
	$(STRIPCMD) $@

stage1-disk: $(STAGE1OBJS-DISK) $(STAGE1_OWN_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $^
	$(STRIPCMD) $@

stage1-network: $(STAGE1OBJS-NETWORK) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $^
	$(STRIPCMD) $@

stage1-usbnet: $(STAGE1OBJS-USBNET) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $^
	$(STRIPCMD) $@

stage1-full: $(STAGE1OBJS-FULL) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) $(PCMCIA_LIB) $(STAGE1_LIBC)
	$(CC) $(LDFLAGS_STAGE1) -o $@ $^
	$(STRIPCMD) $@


$(INITOBJS): %.o: %.c
	$(COMPILE) $(INIT_DEFS) -c $<

$(STAGE1OBJS-CDROM): %-CDROM.o: %.c
	$(COMPILE) $(INCLUDES) $(CDROM_DEFS) -c $< -o $@

$(STAGE1OBJS-DISK): %-DISK.o: %.c
	$(COMPILE) $(INCLUDES) $(DISK_DEFS) -c $< -o $@

$(STAGE1OBJS-NETWORK): %-NETWORK.o: %.c
	$(COMPILE) $(INCLUDES) $(NETWORK_DEFS) -c $< -o $@

$(STAGE1OBJS-USBNET): %-USBNET.o: %.c
	$(COMPILE) $(INCLUDES) $(NETWORK_DEFS) $(USBNET_DEFS) -c $< -o $@

$(STAGE1OBJS-FULL): %-FULL.o: %.c
	$(COMPILE) $(INCLUDES) $(USBNET_DEFS_GEN) $(PCMCIA_DEFS) -c $< -o $@

.c.o:
	$(COMPILE) $(INCLUDES) -c $<


clean: 
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done
	rm -f *.o .depend *.rdz *.img $(BINS)


tar-mkinitrd_helper: clean
	rm -rf mkinitrd_helper-subdir
	mkdir mkinitrd_helper-subdir
	cd mkinitrd_helper-subdir ; cp -a ../dietlibc ../insmod-busybox ../Makefile.common ../insmod.h ../log.h . ; \
	    cp ../Makefile.mkinitrd_helper Makefile
	tar cfj mkinitrd_helper.tar.bz2 mkinitrd_helper-subdir --exclude CVS
	rm -rf mkinitrd_helper-subdir


.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-CDROM.o: %-CDROM.o: %.o

*-DISK.o: %-DISK.o: %.o

*-NETWORK.o: %-NETWORK.o: %.o

*-USBNET.o: %-USBNET.o: %.o

*-FULL.o: %-FULL.o: %.o

