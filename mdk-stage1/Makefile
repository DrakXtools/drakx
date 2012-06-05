 #******************************************************************************
 #
 #    mdk-stage1 - the program that will load second-stage install
 #
 # $Id$
 #
 # Pixel (pixel@mandriva.com) (mostly done by Guillaume Cottenceau)
 #
 # Copyright 2000-2004 Mandriva
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

VERSION=1.54
PRODUCT = $(FAMILY)-binaries

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
ROOTDEST = $(LOCATION)/binaries

DEFS = -DDISTRIB_NAME=\"$(DISTRIB_NAME)\" -DDISTRIB_VERSION=\"$(DISTRIB_VERSION)\" -DDISTRIB_TYPE=\"$(DISTRIB_TYPE)\" -DDISTRIB_DESCR=\"$(DISTRIB_DESCR)\" $(ADDITIONAL_DEFS) -D_FILE_OFFSET_BITS=64 -DARCH=\"$(ARCHDIR)\" -DCONFIG_USE_ZLIB

COMPILE = $(CC) $(DEFS) $(CFLAGS)

INITSRC = init.c

STAGE1_DEFS=-DDISABLE_KA

INITOBJS = $(subst .c,.o,$(INITSRC))


FRONTEND_SRC =
FRONTEND_LIBS =
 #- frontends
ifeq (newt, $(FRONTEND))
FRONTEND_SRC += newt-frontend.c
FRONTEND_LIBS += -lnewt -lslang
else
FRONTEND_SRC += stdio-frontend.c
endif


FRONTEND_OBJS = $(subst .c,.o,$(FRONTEND_SRC))

STAGE1_LIBS = -lz -lldetect -lkmod -lpci -llzma -lsysfs

STAGE1_NETWORK_LIBS =
ifeq (dietlibc, $(LIBC))
STAGE1_NETWORK_LIBS += -lrpc
else
STAGE1_NETWORK_LIBS += -lresolv
endif

 #- stage1 itself
STAGE1_SRC = stage1.c log.c utils.c params.c tools.c modules.c probing.c mount.c automatic.c frontend-common.c lomount.c thirdparty.c zlibsupport.c
CDROMSRC = cdrom.c
DISKSRC = disk.c directory.c partition.c
NETWORKSRC = network.c nfsmount.c dhcp.c url.c dns.c adsl.c directory.c wireless.c
#KASRC = ka.c

# use sort to remove duplicates
STAGE1_ALLSRC = $(sort $(STAGE1_SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC) $(KASRC))
ALLSRC = $(INITSRC) $(STAGE1_ALLSRC)



CDROM_DEFS = -DSPAWN_SHELL -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS_NETWORK = $(subst .c,-NETWORK.o,$(STAGE1_SRC) $(NETWORKSRC))

NETWORK_DEFS = -DSPAWN_SHELL -DDISABLE_CDROM -DDISABLE_DISK -DDISABLE_KA


STAGE1OBJS_NETWORK_STANDALONE = $(subst .c,-NETWORK-STANDALONE.o,$(STAGE1_SRC) $(NETWORKSRC))

NETWORK_STANDALONE_DEFS = -DDISABLE_CDROM -DDISABLE_DISK -DENABLE_NETWORK_STANDALONE -DDISABLE_KA


STAGE1OBJS_FULL = $(subst .c,-FULL.o,$(STAGE1_ALLSRC))

BINS = init stage1 dhcp-client rescue-gui probe-modules

DIRS =
OTHERS = pci-ids.h usb-ids.h
ifeq (i386, $(ARCH))
DIRS += pcmcia
OTHERS += pcmcia-ids.h
PCMCIA_LIB = pcmcia/libpcmcia.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif
ifeq (x86_64, $(ARCH))
DIRS += pcmcia
OTHERS += pcmcia-ids.h
PCMCIA_LIB = pcmcia/libpcmcia.a
PCMCIA_DEFS = -DENABLE_PCMCIA
endif

BUILDDIRS = $(DIRS:%=build-%)
CLEANDIRS = $(DIRS:%=clean-%)

USB_DEFS_GEN = -DENABLE_USB
USB_DEFS = -DENABLE_USB -DDISABLE_PCIADAPTERS

all: $(BUILDDIRS) $(OTHERS) $(DIRS) $(BINS)
$(DIRS): $(BUILDDIRS)
$(BUILDDIRS):
	$(MAKE) -C $(@:build-%=%)


pci-ids.h: /usr/share/ldetect-lst/pcitable.gz update-pci-ids.pl
	perl update-pci-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia-ids.h: update-pcmcia-ids.pl
	perl update-pcmcia-ids.pl > $@ || { rm -f $@; exit 1; }

usb-ids.h: /usr/share/ldetect-lst/usbtable.gz update-usb-ids.pl
	perl update-usb-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia/libpcmcia.a: pcmcia

init: $(INITOBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(LIBC_LIBS)

stage1: $(STAGE1OBJS_FULL) bootsplash.o $(FRONTEND_OBJS) $(PCMCIA_LIB)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS)

dhcp-client: $(STAGE1OBJS_NETWORK_STANDALONE) $(FRONTEND_OBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS)


$(INITOBJS): %.o: %.c
	$(COMPILE) $(INCLUDES) -c $<

$(STAGE1OBJS_NETWORK): %-NETWORK.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) $(NETWORK_DEFS) $(PCMCIA_DEFS) $(USB_DEFS_GEN) -DENABLE_ADDITIONAL_MODULES -c $< -o $@

$(STAGE1OBJS_NETWORK_STANDALONE): %-NETWORK-STANDALONE.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) -c $< -o $@

$(STAGE1OBJS_FULL): %-FULL.o: %.c
	$(DIET) $(COMPILE) $(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) -DENABLE_BOOTSPLASH -c $< -o $@

.c.o:
	$(DIET) $(COMPILE) $(INCLUDES) -DENABLE_BOOTSPLASH -c $<


clean: $(CLEANDIRS)
	rm -f *.o .depend *.rdz *.img pci-ids.h pcmcia-ids.h usb-ids.h $(BINS)
$(CLEANDIRS): 
	$(MAKE) -C $(@:clean-%=%) clean

.PHONY: subdirs $(DIRS)
.PHONY: subdirs $(BUILDDIRS)
.PHONY: subdirs $(CLEANDIRS)
.PHONY: all clean test

rescue-gui: rescue-gui.o frontend-common.o params.o utils.o log.o automatic.o $(FRONTEND_OBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(FRONTEND_LIBS) $(LIBC_LIBS)

probe-modules: $(OTHERS) probe-modules.o probing-FULL.o modules-FULL.o params-FULL.o utils-FULL.o log-FULL.o automatic-FULL.o frontend-common-FULL.o stdio-frontend.o zlibsupport-FULL.o $(PCMCIA_LIB)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(LIBC_LIBS)

dist: tar
tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@if [ -e "../.svn" ]; then \
	    $(MAKE) dist-svn; \
	    elif [ -e "../.git" ]; then \
	    $(MAKE) dist-git; \
	    else \
	    echo "Unknown SCM (not SVN nor GIT)";\
	    exit 1; \
	    fi;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

dist-svn:
	mkdir -p $(PRODUCT)-$(VERSION)
	svn export -q -rBASE . $(PRODUCT)-$(VERSION)/mdk-stage1
	svn export -q -rBASE ../kernel $(PRODUCT)-$(VERSION)/kernel
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfa $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

dist-git:
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD mdk-stage1 kernel Makefile.config | xz >mdk-stage1/$(PRODUCT)-$(VERSION).tar.xz;

install: all
	install -m755 init -D $(DESTDIR)$(ROOTDEST)/init
	install -m755 stage1 -D $(DESTDIR)$(ROOTDEST)/stage1
	install -m755 rescue-gui -D $(DESTDIR)$(ROOTDEST)/rescue-gui
	install -m755 dhcp-client -D $(DESTDIR)$(ROOTDEST)/dhcp-client
	install -m755 probe-modules -D $(DESTDIR)$(ROOTDEST)/probe-modules
	if [ -e pcmcia/pcmcia_probe.o ]; then \
		install -m644 pcmcia/pcmcia_probe.o -D $(DESTDIR)$(ROOTDEST)/pcmcia_probe.o; \
	fi


.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-NETWORK.o: %-NETWORK.o: %.o

*-FULL.o: %-FULL.o: %.o

