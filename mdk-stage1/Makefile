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

VERSION=1.10.1
PRODUCT=drakx-installer-binaries

 #
 # Portions from Erik Troan (ewt@redhat.com) Copyright 1996 Red Hat Software 
 #
 #*****************************************************************************
 #
 # Currently:
 #
 # 	ix86
 # init with dietlibc
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
 # init with dietlibc
 # stage1 with dietlibc
 #
 #*****************************************************************************


top_dir = .

include $(top_dir)/Makefile.common
include $(top_dir)/../Makefile.config
ARCHDIR=$(ARCH)
ifeq (i386, $(ARCH))
ARCHDIR=i586
endif

DEFS = -DDISTRIB_NAME=\"$(DISTRIB_NAME)\" -DDISTRIB_VERSION=\"$(DISTRIB_VERSION)\" -DDISTRIB_TYPE=\"$(DISTRIB_TYPE)\" -DDISTRIB_DESCR=\"$(DISTRIB_DESCR)\" $(ADDITIONAL_DEFS) -D_FILE_OFFSET_BITS=64 -DARCH=\"$(ARCHDIR)\" -DCONFIG_USE_ZLIB

COMPILE = $(CC) $(DEFS) $(CFLAGS)

INIT_DEFS =
INITSRC = init.c
ifneq (DIETLIBC, $(L))
INIT_DEFS += $(GLIBC_INCLUDES)
endif

INITOBJS = $(subst .c,.o,$(INITSRC))


 #- frontends
NEWT_FRONTEND_SRC = newt-frontend.c
NEWT_FRONTEND_LIBS = newt/libnewt.a slang/libslang.a

STDIO_FRONTEND_SRC = stdio-frontend.c
STDIO_FRONTEND_LIBS =
STDIO_FRONTEND_LIBS =


FRONTEND_OBJS = $(subst .c,.o,$($(F)_FRONTEND_SRC))

FRONTEND_LINK = $(FRONTEND_OBJS) $($(F)_FRONTEND_LIBS)

STAGE1_OWN_LIBS =
ifeq (DIETLIBC, $(L))
STAGE1_OWN_LIBS = /usr/$(LIB)/libz-diet.a
else
STAGE1_OWN_LIBS = /usr/$(LIB)/libz.a
endif


ifeq (DIETLIBC, $(L))
STAGE1_NETWORK_LIBS = /usr/lib/dietlibc/lib-$(ARCH)/librpc.a
else
STAGE1_NETWORK_LIBS = /usr/$(LIB)/libresolv.a
endif

 #- stage1 itself
STAGE1SRC = stage1.c log.c utils.c params.c tools.c modules.c probing.c mount.c automatic.c frontend-common.c lomount.c thirdparty.c zlibsupport.c
CDROMSRC = cdrom.c
DISKSRC = disk.c directory.c partition.c
NETWORKSRC = network.c nfsmount.c dhcp.c url.c dns.c adsl.c directory.c wireless.c
KASRC = ka.c

# use sort to remove duplicates
STAGE1_ALLSRC = $(sort $(STAGE1SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC) $(KASRC))
ALLSRC = $(INITSRC) $(STAGE1_ALLSRC)



CDROM_DEFS = -DSPAWN_SHELL -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS-NETWORK = $(subst .c,-NETWORK.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_DEFS = -DSPAWN_SHELL -DDISABLE_CDROM -DDISABLE_DISK -DDISABLE_KA


STAGE1OBJS-NETWORK-STANDALONE = $(subst .c,-NETWORK-STANDALONE.o,$(STAGE1SRC) $(NETWORKSRC))

NETWORK_STANDALONE_DEFS = -DDISABLE_CDROM -DDISABLE_DISK -DENABLE_NETWORK_STANDALONE -DDISABLE_KA


STAGE1OBJS-FULL = $(subst .c,-FULL.o,$(STAGE1_ALLSRC))

BINS = init stage1 dhcp-client rescue-gui

DIRS += pci-resource usb-resource slang newt ppp/pppd rp-pppoe/src
ifeq (i386, $(ARCH))
DIRS += pcmcia pcmcia-resource sysfs
endif
ifeq (x86_64, $(ARCH))
DIRS += pcmcia pcmcia-resource sysfs
endif


ifeq (i386,$(ARCH))
PCMCIA_LIB = pcmcia/libpcmcia.a sysfs/libsysfs.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif
ifeq (x86_64,$(ARCH))
PCMCIA_LIB = pcmcia/libpcmcia.a sysfs/libsysfs.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif


USB_DEFS_GEN = -DENABLE_USB
USB_DEFS = -DENABLE_USB -DDISABLE_PCIADAPTERS

all: dirs $(BINS)

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n || exit 1 ;\
	done

init: $(INITOBJS) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

stage1: $(STAGE1OBJS-FULL) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) bootsplash.o $(PCMCIA_LIB) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@

dhcp-client: $(STAGE1OBJS-NETWORK-STANDALONE) $(STAGE1_OWN_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@


$(INITOBJS): %.o: %.c
	$(COMPILE) $(INIT_DEFS) -c $<

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
	rm -f *.o .depend *.rdz *.img $(BINS)


rescue-gui: rescue-gui.o frontend-common.o params.o utils.o log.o automatic.o $(FRONTEND_LINK) $(STAGE1_LIBC)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^
	$(STRIPCMD) $@


tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	mkdir -p $(PRODUCT)-$(VERSION)
	svn export -q . $(PRODUCT)-$(VERSION)/mdk-stage1
	svn export -q ../kernel $(PRODUCT)-$(VERSION)/kernel
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfj $(PRODUCT)-$(VERSION).tar.bz2 $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-NETWORK.o: %-NETWORK.o: %.o

*-FULL.o: %-FULL.o: %.o

