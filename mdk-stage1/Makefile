 #******************************************************************************
 #
 #    mdk-stage1 - the program that will load second-stage install
 #
 # $Id$
 #
 # Pixel (pixel@mandrakesoft.com) (mostly done by Guillaume Cottenceau)
 #
 # Copyright 2000-2004 Mandrakesoft
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
 # stage1 with dietlibc
 #
 # 	ppc
 # init with dietlibc
 # stage1 with glibc
 #
 # 	ia64
 # init with glibc
 # stage1 with glibc
 #
 #	x86-64
 # init with minilibc
 # stage1 with dietlibc
 #
 #*****************************************************************************


top_dir = .

include $(top_dir)/Makefile.common
include $(top_dir)/../Makefile.config


DEFS = -DDISTRIB_NAME=\"$(DISTRIB_NAME)\" -DDISTRIB_VERSION=\"$(DISTRIB_VERSION)\" -DDISTRIB_DESCR=\"$(DISTRIB_DESCR)\" $(ADDITIONAL_DEFS) -D_FILE_OFFSET_BITS=64

COMPILE = $(CC) $(DEFS) $(CFLAGS)

ifeq (ppc, $(ARCH))
INIT_HEADERS=init-libc-headers.h
else
ifeq (DIETLIBC, $(L))
INIT_HEADERS=minilibc.h
else
INIT_HEADERS=init-libc-headers.h
endif
endif

INIT_DEFS = -DINIT_HEADERS=\"$(INIT_HEADERS)\"

ifeq (DIETLIBC, $(L))
INITSRC = minilibc.c init.c
INIT_DEFS += -fno-builtin
else
INITSRC = init.c
INIT_DEFS += $(GLIBC_INCLUDES)
endif

INIT_DEFS_ADD = -DBINARY=\"/sbin/stage1\"
ifdef MOVE
INIT_DEFS_ADD_STAGE2 = -DBINARY=\"/usr/bin/runstage2.pl\"
else
INIT_DEFS_ADD_STAGE2 = -DBINARY=\"/usr/bin/runinstall2\"
endif

INITOBJS = $(subst .c,.o,$(INITSRC))
INITOBJS-STAGE2 = $(subst .c,-STAGE2.o,$(INITSRC))


 #- frontends
NEWT_FRONTEND_SRC = newt-frontend.c
NEWT_FRONTEND_LIBS = newt/libnewt.a slang/libslang.a

STDIO_FRONTEND_SRC = stdio-frontend.c
STDIO_FRONTEND_LIBS =
STDIO_FRONTEND_LIBS =


FRONTEND_OBJS = $(subst .c,.o,$($(F)_FRONTEND_SRC))

FRONTEND_LINK = $(FRONTEND_OBJS) $($(F)_FRONTEND_LIBS)

ifeq (DIETLIBC, $(L))
INSMOD = insmod-busybox
else
INSMOD = insmod-modutils
endif

STAGE1_OWN_LIBS = $(INSMOD)/libinsmod.a mar/libmar.a bzlib/libbzlib.a


ifeq (DIETLIBC, $(L))
STAGE1_NETWORK_LIBS = /usr/lib/dietlibc/lib-$(ARCH)/librpc.a
else
STAGE1_NETWORK_LIBS = /usr/$(LIB)/libresolv.a
endif

 #- stage1 itself
STAGE1SRC = stage1.c log.c tools.c modules.c probing.c mount.c automatic.c frontend-common.c lomount.c thirdparty.c
CDROMSRC = cdrom.c
DISKSRC = disk.c directory.c partition.c
NETWORKSRC = network.c nfsmount.c dhcp.c url.c dns.c adsl.c directory.c wireless.c
KASRC = ka.c

# use sort to remove duplicates
STAGE1_ALLSRC = $(sort $(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC) $(KASRC))
ALLSRC = $(INITSRC) $(STAGE1_ALLSRC)



STAGE1OBJS-CDROM = $(subst .c,-CDROM.o,$(STAGE1SRC) $(CDROMSRC))

CDROM_DEFS = -DSPAWN_SHELL -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS-NETWORK = $(subst .c,-NETWORK.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_DEFS = -DSPAWN_SHELL -DDISABLE_CDROM -DDISABLE_DISK -DDISABLE_KA


STAGE1OBJS-NETWORK-STANDALONE = $(subst .c,-NETWORK-STANDALONE.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_STANDALONE_DEFS = -DDISABLE_CDROM -DDISABLE_DISK -DENABLE_NETWORK_STANDALONE -DDISABLE_KA


STAGE1OBJS-FULL = $(subst .c,-FULL.o,$(STAGE1_ALLSRC))

BINS = init init-stage2 stage1-full dhcp-client

ifndef MOVE
ifeq (i386, $(ARCH))
BINS += stage1-cdrom stage1-network
endif
ifeq (x86_64, $(ARCH))
BINS += stage1-cdrom stage1-network
endif
endif

DIRS += mar pci-resource usb-resource bzlib $(INSMOD) slang newt ppp/pppd rp-pppoe/src
ifeq (i386, $(ARCH))
DIRS += pcmcia_
endif
ifeq (x86_64, $(ARCH))
DIRS += pcmcia_
endif


ifeq (i386,$(ARCH))
PCMCIA_LIB = pcmcia_/libpcmcia.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif
ifeq (x86_64,$(ARCH))
PCMCIA_LIB = pcmcia_/libpcmcia.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif


USB_DEFS_GEN = -DENABLE_USB
USB_DEFS = -DENABLE_USB -DDISABLE_PCIADAPTERS

all: dirs $(BINS)

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n || exit 1 ;\
	done

init: $(INITOBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

init-stage2: $(INITOBJS-STAGE2)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

stage1-cdrom: $(STAGE1OBJS-CDROM) $(STAGE1_OWN_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

stage1-network: $(STAGE1OBJS-NETWORK) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) $(PCMCIA_LIB) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

stage1-full: $(STAGE1OBJS-FULL) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) bootsplash.o $(PCMCIA_LIB) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

dhcp-client: $(STAGE1OBJS-NETWORK-STANDALONE) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@


$(INITOBJS): %.o: %.c
	$(COMPILE) $(INIT_DEFS) $(INIT_DEFS_ADD) -c $<

$(INITOBJS-STAGE2): %-STAGE2.o: %.c
	$(COMPILE) $(INIT_DEFS) $(INIT_DEFS_ADD_STAGE2) -c $< -o $@

$(STAGE1OBJS-CDROM): %-CDROM.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) $(CDROM_DEFS) -c $< -o $@

$(STAGE1OBJS-NETWORK): %-NETWORK.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) $(NETWORK_DEFS) $(PCMCIA_DEFS) $(USB_DEFS_GEN) -DENABLE_ADDITIONAL_MODULES -c $< -o $@

$(STAGE1OBJS-NETWORK-STANDALONE): %-NETWORK-STANDALONE.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) -c $< -o $@

$(STAGE1OBJS-FULL): %-FULL.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) -DENABLE_BOOTSPLASH -c $< -o $@

.c.o:
	$(DIET) $(COMPILE) $(INCLUDES) -DENABLE_BOOTSPLASH -c $<


clean: localclean
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done

localclean:
	rm -f *.o .depend *.rdz *.img rescue-gui init-move $(BINS)


tar-mkinitrd_helper: clean
	rm -rf mkinitrd_helper-subdir
	mkdir mkinitrd_helper-subdir
	cd mkinitrd_helper-subdir ; cp -a ../insmod-busybox ../Makefile.common ../insmod.h ../log.h . ; \
	    cp ../Makefile.mkinitrd_helper Makefile
	tar cfj mkinitrd_helper.tar.bz2 mkinitrd_helper-subdir --exclude CVS
	rm -rf mkinitrd_helper-subdir

rescue-gui: rescue-gui.o frontend-common.o $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@


.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-CDROM.o: %-CDROM.o: %.o

*-NETWORK.o: %-NETWORK.o: %.o

*-FULL.o: %-FULL.o: %.o

