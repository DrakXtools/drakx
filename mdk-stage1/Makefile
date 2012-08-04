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

VERSION=1.56
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
#ifeq (newt, $(FRONTEND))
#FRONTEND_SRC += newt-frontend.c
ifndef DYNAMIC
FRONTEND_LIBS += -lnewt -lslang
else
FRONTEND_LIBS += -Wl,-Bstatic -lnewt -lslang -Wl,-Bdynamic
endif
#else
#FRONTEND_SRC += stdio-frontend.c
#endif


FRONTEND_OBJS = $(subst .c,.o,$(FRONTEND_SRC))

ifndef DYNAMIC
STAGE1_LIBS = -lldetect -lz -lkmod -lpci -lsysfs -llzma
else
STAGE1_LIBS = -Wl,-Bdynamic -lldetect -lz -Wl,-Bstatic -lkmod -lpci -lsysfs -llzma -Wl,-Bdynamic
endif

STAGE1_NETWORK_LIBS =
ifeq (dietlibc, $(LIBC))
STAGE1_NETWORK_LIBS += -lrpc
else
STAGE1_NETWORK_LIBS += -lresolv
endif

 #- stage1 itself
STAGE1_SRC = stage1.c log.c utils.c params.c tools.c modules.c probing.c mount.c automatic.c frontend.c frontend-common.c lomount.c thirdparty.c zlibsupport.c
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
HEADERS = pci-ids.h usb-ids.h
ifneq (,$(findstring $(ARCH), i386 x86_64))
HEADERS += pcmcia-ids.h
ifneq (0, $(WHOLE_PROGRAM))
PCMCIA_LIB = pcmcia/probe.c pcmcia/startup.c pcmcia/yacc_config.c pcmcia/lex_config.c
else
DIRS += pcmcia
PCMCIA_LIB = pcmcia/libpcmcia.a
endif
PCMCIA_DEFS = -DENABLE_PCMCIA
endif

BUILDDIRS = $(DIRS:%=build-%)
CLEANDIRS = $(DIRS:%=clean-%)

USB_DEFS_GEN = -DENABLE_USB
USB_DEFS = -DENABLE_USB -DDISABLE_PCIADAPTERS

all: $(BUILDDIRS) $(DIRS) $(BINS)
$(DIRS): $(BUILDDIRS)
$(BUILDDIRS):
	$(MAKE) -C $(@:build-%=%)

pcmcia/pcmcia_probe.o: pcmcia/probe.c
	$(DIET) $(COMPILE) -fPIC $(INCLUDES) -c $< -o $@

pcmcia/yacc_config.c:
	$(YACC) $(YFLAGS) -d -o pcmcia/yacc_config.c pcmcia/yacc_config.y

pci-ids.h: /usr/share/ldetect-lst/pcitable.gz update-pci-ids.pl
	perl update-pci-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia-ids.h: update-pcmcia-ids.pl
	perl update-pcmcia-ids.pl > $@ || { rm -f $@; exit 1; }

usb-ids.h: /usr/share/ldetect-lst/usbtable.gz update-usb-ids.pl
	perl update-usb-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia/libpcmcia.a: pcmcia

ifneq (0, $(ONE_BINARY))
dhcp-client rescue-gui probe-modules: stage1
	ln -f $^ $@
endif

ifneq (0, $(WHOLE_PROGRAM))

init: .depend $(INITSRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) \
		$(INITSRC) \
		$(LIBC_LIBS) \
		-o $@

ifneq (0, $(ONE_BINARY))
stage1: .depend $(PCMCIA_LIB) probe-modules.c rescue-gui.c $(FRONTEND_SRC) $(STAGE1_ALLSRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) \
		probe-modules.c rescue-gui.c $(FRONTEND_SRC) $(STAGE1_ALLSRC) \
		$(PCMCIA_LIB) $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

else
stage1: .depend $(PCMCIA_LIB) $(FRONTEND_SRC) $(STAGE1_ALLSRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) \
		$(FRONTEND_SRC) $(STAGE1_ALLSRC) \
		$(PCMCIA_LIB) $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

dhcp-client: .depend $(STAGE1_SRC) $(NETWORKSRC) $(FRONTEND_SRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) \
		$(STAGE1_SRC) $(NETWORKSRC) $(FRONTEND_SRC) \
		$(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

rescue-gui: .depend rescue-gui.c frontend-common.c params.c utils.c log.c automatic.c $(FRONTEND_SRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) \
		rescue-gui.c frontend-common.c params.c utils.c log.c automatic.c $(FRONTEND_SRC) \
		$(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

probe-modules: .depend $(PCMCIA_LIB) probe-modules.c probing.c modules.c params.c utils.c log.c automatic.c frontend-common.c stdio-frontend.c zlibsupport.c $(PCMCIA_LIB)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) \
		probe-modules.c probing.c modules.c params.c utils.c log.c automatic.c frontend-common.c stdio-frontend.c zlibsupport.c $(PCMCIA_LIB) \
		$(STAGE1_LIBS) $(LIBC_LIBS) \
		-o $@
endif
else

init: $(INITOBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(LIBC_LIBS)

stage1: $(STAGE1OBJS_FULL) $(FRONTEND_OBJS) $(PCMCIA_LIB)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS)

ifeq (0, $(ONE_BINARY))
dhcp-client: $(STAGE1OBJS_NETWORK_STANDALONE) $(FRONTEND_OBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS)

rescue-gui: rescue-gui.o frontend-common.o params.o utils.o log.o automatic.o $(FRONTEND_OBJS)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(FRONTEND_LIBS) $(LIBC_LIBS)
endif

probe-modules: probe-modules.o probing-FULL.o modules-FULL.o params-FULL.o utils-FULL.o log-FULL.o automatic-FULL.o frontend-common-FULL.o stdio-frontend.o zlibsupport-FULL.o $(PCMCIA_LIB)
	$(DIET) $(CC) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(LIBC_LIBS)

$(INITOBJS): %.o: %.c .depend
	$(DIET) $(COMPILE) $(INCLUDES) -c $<

$(STAGE1OBJS_NETWORK): %-NETWORK.o: %.c .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(NETWORK_DEFS) $(PCMCIA_DEFS) $(USB_DEFS_GEN) -DENABLE_ADDITIONAL_MODULES -c $< -o $@

$(STAGE1OBJS_NETWORK_STANDALONE): %-NETWORK-STANDALONE.o: %.c .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) -c $< -o $@

$(STAGE1OBJS_FULL): %-FULL.o: %.c .depend
	$(DIET) $(COMPILE) $(INCLUDES) -DSPAWN_SHELL $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) -c $< -o $@

.c.o: .depend
	$(DIET) $(COMPILE) $(INCLUDES) -c $<

endif

clean: $(CLEANDIRS)
	rm -f *.o .depend *.rdz *.img pci-ids.h pcmcia-ids.h usb-ids.h $(BINS)
$(CLEANDIRS): 
	$(MAKE) -C $(@:clean-%=%) clean

.PHONY: subdirs $(DIRS)
.PHONY: subdirs $(BUILDDIRS)
.PHONY: subdirs $(CLEANDIRS)
.PHONY: all clean test

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

install:
	install -m755 init -D $(DESTDIR)$(ROOTDEST)/init
	install -m755 stage1 -D $(DESTDIR)$(ROOTDEST)/stage1
ifeq (0, $(ONE_BINARY))
	install -m755 rescue-gui -D $(DESTDIR)$(ROOTDEST)/rescue-gui
	install -m755 dhcp-client -D $(DESTDIR)$(ROOTDEST)/dhcp-client
	install -m755 probe-modules -D $(DESTDIR)$(ROOTDEST)/probe-modules
else
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/rescue-gui
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/dhcp-client
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/probe-modules
endif

	if [ -e pcmcia/pcmcia_probe.o ]; then \
		install -m644 pcmcia/pcmcia_probe.o -D $(DESTDIR)$(ROOTDEST)/pcmcia_probe.o; \
	fi


.DELETE_ON_ERROR:
.depend: $(HEADERS)
	$(CPP) $(DEFS) $(INCLUDES) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-NETWORK.o: %-NETWORK.o: %.o

*-FULL.o: %-FULL.o: %.o

