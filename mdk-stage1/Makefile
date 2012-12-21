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

VERSION=2.1
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

default: all

MDK_STAGE_ONE=1
ldetect_srcdir = ./ldetect
include $(ldetect_srcdir)/Makefile
LDETECT_SRC := $(patsubst %,ldetect/%,$(lib_src))


include $(top_dir)/Makefile.common
include $(top_dir)/../Makefile.config

INCLUDES += -Ildetect

ARCHDIR=$(ARCH)
ifeq (i386, $(ARCH))
ARCHDIR=i586
endif
ROOTDEST = $(LOCATION)/binaries

DEFS = -DDISTRIB_NAME=\""$(DISTRIB_NAME)"\" -DDISTRIB_VERSION=\""$(DISTRIB_VERSION)"\" -DDISTRIB_TYPE=\"$(DISTRIB_TYPE)\" -DDISTRIB_DESCR=\"$(DISTRIB_DESCR)\" $(ADDITIONAL_DEFS) -D_FILE_OFFSET_BITS=64 -DARCH=\"$(ARCHDIR)\"

COMPILE = $(CXX) $(DEFS) $(CXXFLAGS)

STAGE1_DEFS=-DDISABLE_KA -DDRAKX_ONE_BINARY -D_GNU_SOURCE

LOCAL_SRC = $(LDETECT_SRC)
FRONTEND_SRC =
FRONTEND_LIBS =
 #- frontends
#ifeq (newt, $(FRONTEND))
#FRONTEND_SRC += newt-frontend.c
#SLANG_SRC = slang/slang.c slang/slarith.c slang/slarray.c slang/slarrfun.c slang/slarrmis.c slang/slassoc.c slang/slboseos.c slang/slbstr.c slang/slclass.c slang/slcmd.c slang/slcmplex.c slang/slcommon.c slang/slcompat.c slang/slcurses.c slang/sldisply.c slang/slerrno.c slang/slerr.c slang/slexcept.c slang/slfpu.c slang/slgetkey.c slang/slintall.c slang/slischar.c slang/slistruc.c slang/slkeymap.c slang/slkeypad.c slang/sllist.c slang/sllower.c slang/slmalloc.c slang/slmath.c slang/slmemchr.c slang/slmemcmp.c slang/slmemcpy.c slang/slmemset.c slang/slmisc.c slang/slnspace.c slang/slospath.c slang/slpack.c slang/slparse.c slang/slpath.c slang/slposdir.c slang/slposio.c slang/slprepr.c slang/slproc.c slang/slregexp.c slang/slrline.c slang/slscanf.c slang/slscroll.c slang/slsearch.c slang/slsignal.c slang/slsig.c slang/slsmg.c slang/slstdio.c slang/slstd.c slang/slstring.c slang/slstrops.c slang/slstruct.c slang/sltermin.c slang/sltime.c slang/sltoken.c slang/sltypes.c slang/slupper.c slang/slutf8.c slang/slutty.c slang/slwclut.c slang/slwcwidth.c slang/slxstrng.c
#INCLUDES += -Islang

ifndef DYNAMIC
NEWT_SRC = newt/buttonbar.c newt/button.c  newt/checkbox.c  newt/checkboxtree.c  newt/entry.c  newt/form.c  newt/grid.c newt/label.c   newt/scale.c newt/scrollbar.c	newt/textbox.c	newt/windows.c newt/newt.c  newt/listbox.c
FRONTEND_SRC += $(NEWT_SRC) $(SLANG_SRC)

KMOD_SRC = libkmod/libkmod.c libkmod/libkmod-module.c libkmod/libkmod-elf.c libkmod/libkmod-config.c libkmod/libkmod-hash.c libkmod/libkmod-util.c libkmod/libkmod-list.c libkmod/libkmod-file.c libkmod/libkmod-index.c
KMOD_DEFS = -DHAVE_CONFIG_H -DROOTPREFIX='""' -DSYSCONFDIR='"/etc"'
LOCAL_SRC += $(KMOD_SRC)
INCLUDES += -Ilibkmod
DEFS += $(KMOD_DEFS)

LIBPCI_SRC = libpci/access.c libpci/caps.c libpci/dump.c libpci/generic.c libpci/init.c libpci/i386-ports.c libpci/names.c libpci/names-cache.c libpci/names-hash.c libpci/names-net.c libpci/names-parse.c libpci/params.c libpci/proc.c libpci/sysfs.c
LOCAL_SRC += $(LIBPCI_SRC)
INCLUDES += -Ilibpci

LIBSYSFS_SRC = libsysfs/dlist.c libsysfs/sysfs_attr.c libsysfs/sysfs_device.c libsysfs/sysfs_utils.c
LOCAL_SRC += $(LIBSYSFS_SRC) 
INCLUDES += -Ilibsysfs

else
FRONTEND_LIBS += -lnewt
endif
#else
#FRONTEND_SRC += stdio-frontend.cpp
#endif

SERIAL_PROBE_SRC = serial.cpp serial_probe.cpp
LOCAL_SRC += $(SERIAL_PROBE_SRC)

BINS_SRC = drvinst.cpp probe-modules.cpp rescue-gui.cpp ldetect/lspcidrake.cpp consoletype.cpp
LOCAL_SRC += $(BINS_SRC)

FRONTEND_OBJS = $(subst .c,.o,$(FRONTEND_SRC))

ifndef DYNAMIC
STAGE1_LIBS = -lm
else
STAGE1_LIBS = -Wl,-Bdynamic -lm -lkmod -lpci -lsysfs -lz
endif

STAGE1_NETWORK_LIBS =
ifeq (dietlibc, $(LIBC))
	STAGE1_NETWORK_LIBS += -lrpc
else
	STAGE1_NETWORK_LIBS += -lresolv
endif
ifeq (glibc, $(LIBC))
STAGE1_NETWORK_LIBS += -ltirpc
endif

# - stage1 itself
STAGE1_SRC = stage1.cpp log.cpp utils.cpp params.cpp tools.cpp modules.cpp probing.cpp mount.cpp automatic.cpp frontend.cpp frontend-common.cpp lomount.cpp thirdparty.cpp
CDROMSRC = cdrom.cpp
DISKSRC = disk.cpp directory.cpp partition.cpp
NETWORKSRC = network.cpp nfsmount.cpp dhcp.cpp url.cpp dns.cpp adsl.cpp directory.cpp wireless.cpp
#KASRC = ka.c

# use sort to remove duplicates
STAGE1_ALLSRC = $(sort $(STAGE1_SRC) $(CDROMSRC) $(DISKSRC) $(NETWORKSRC) $(KASRC))
ALLSRC = $(STAGE1_ALLSRC) $(FRONTEND_LIBS) $(LOCAL_SRC)



CDROM_DEFS = -DDISABLE_DISK -DDISABLE_NETWORK


STAGE1OBJS_NETWORK = $(subst .cpp,-NETWORK.o,$(STAGE1_SRC) $(NETWORKSRC))

NETWORK_DEFS = -DDISABLE_CDROM -DDISABLE_DISK -DDISABLE_KA


STAGE1OBJS_NETWORK_STANDALONE = $(subst .cpp,-NETWORK-STANDALONE.o,$(STAGE1_SRC) $(NETWORKSRC))

NETWORK_STANDALONE_DEFS = -DDISABLE_CDROM -DDISABLE_DISK -DENABLE_NETWORK_STANDALONE -DDISABLE_KA


STAGE1OBJS_FULL = $(subst .cpp,-FULL.o,$(STAGE1_ALLSRC))

LOCALOBJS = $(subst .cpp,.o,$(LOCAL_SRC))

ADD_BINS = dhcp-client rescue-gui probe-modules drvinst lspcidrake serial_probe consoletype

BINS := stage1 $(ADD_BINS)

DIRS =
HEADERS = pci-ids.h usb-ids.h
ifneq (,$(findstring $(ARCH), i386 x86_64))
	HEADERS += pcmcia-ids.h
ifneq (0, $(WHOLE_PROGRAM))
PCMCIA_LIB = pcmcia/probe.cpp pcmcia/startup.cpp pcmcia/yacc_config.cpp pcmcia/lex_config.cpp
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

all: $(BUILDDIRS) $(DIRS) $(BINS) pcmcia/pcmcia_probe.o
$(DIRS): $(BUILDDIRS)
$(BUILDDIRS):
	$(MAKE) -C $(@:build-%=%)

pcmcia/pcmcia_probe.o: pcmcia/probe.cpp
	$(DIET) $(COMPILE) -fPIC $(INCLUDES) -c $< -o $@

pcmcia/yacc_config.cpp:
	$(YACC) $(YFLAGS) -d -o pcmcia/yacc_config.cpp pcmcia/yacc_config.y

pci-ids.h: /usr/share/ldetect-lst/pcitable.gz update-pci-ids.pl
	perl update-pci-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia-ids.h: update-pcmcia-ids.pl
	perl update-pcmcia-ids.pl > $@ || { rm -f $@; exit 1; }

usb-ids.h: /usr/share/ldetect-lst/usbtable.gz update-usb-ids.pl
	perl update-usb-ids.pl > $@ || { rm -f $@; exit 1; }

pcmcia/libpcmcia.a: pcmcia

ifneq (0, $(ONE_BINARY))
$(ADD_BINS): stage1
	ln -f $^ $@
endif

ifneq (0, $(WHOLE_PROGRAM))

ifneq (0, $(ONE_BINARY))

stage1: .depend $(PCMCIA_LIB) $(FRONTEND_SRC) $(LOCAL_SRC) $(FRONTEND_LIBS) $(STAGE1_ALLSRC) Makefile
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) \
		$(FRONTEND_SRC) $(LOCAL_SRC) $(STAGE1_ALLSRC) \
		$(PCMCIA_LIB) $(FRONTEND_LIBS) $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(LIBC_LIBS) \
		-o $@

else
stage1: .depend $(PCMCIA_LIB) $(FRONTEND_SRC) $(STAGE1_ALLSRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) \
		$(FRONTEND_SRC) $(STAGE1_ALLSRC) \
		$(PCMCIA_LIB) $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

dhcp-client: .depend $(STAGE1_SRC) $(NETWORKSRC) $(FRONTEND_SRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) \
		$(STAGE1_SRC) $(NETWORKSRC) $(FRONTEND_SRC) \
		$(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

rescue-gui: .depend rescue-gui.cpp frontend-common.cpp params.cpp utils.cpp log.cpp automatic.cpp $(FRONTEND_SRC)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) \
		rescue-gui.cpp frontend-common.cpp params.cpp utils.cpp log.cpp automatic.cpp $(FRONTEND_SRC) \
		$(FRONTEND_LIBS) $(LIBC_LIBS) \
		-o $@

probe-modules: .depend $(PCMCIA_LIB) probe-modules.cpp probing.cpp modules.cpp params.cpp utils.cpp log.cpp automatic.cpp frontend-common.cpp stdio-frontend.cpp $(PCMCIA_LIB)
	$(DIET) $(COMPILE) $(LDFLAGS) $(WHOLEFLAGS) \
		$(INCLUDES) \
		probe-modules.cpp probing.cpp modules.cpp params.cpp utils.cpp log.cpp automatic.cpp frontend-common.cpp stdio-frontend.cpp $(PCMCIA_LIB) \
		$(STAGE1_LIBS) $(LIBC_LIBS) \
		-o $@
endif
else

stage1: $(STAGE1OBJS_FULL) $(FRONTEND_OBJS) $(PCMCIA_LIB) $(LOCALOBJS)
	$(DIET) $(CXX) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS)

ifeq (0, $(ONE_BINARY))
dhcp-client: $(STAGE1OBJS_NETWORK_STANDALONE) $(FRONTEND_OBJS)
	$(DIET) $(CXX) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(STAGE1_NETWORK_LIBS) $(FRONTEND_LIBS) $(LIBC_LIBS)

rescue-gui: rescue-gui.o frontend-common.o params.o utils.o log.o automatic.o $(FRONTEND_OBJS)
	$(DIET) $(CXX) $(LDFLAGS) -o $@ $^ $(FRONTEND_LIBS) $(LIBC_LIBS)

probe-modules: probe-modules.o probing-FULL.o modules-FULL.o params-FULL.o utils-FULL.o log-FULL.o automatic-FULL.o frontend-common-FULL.o stdio-frontend.o $(PCMCIA_LIB)
	$(DIET) $(CXX) $(LDFLAGS) -o $@ $^ $(STAGE1_LIBS) $(LIBC_LIBS)

endif

$(STAGE1OBJS_NETWORK): %-NETWORK.o: %.cpp .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(STAGE1_DEFS) $(NETWORK_DEFS) $(PCMCIA_DEFS) $(USB_DEFS_GEN) -DENABLE_ADDITIONAL_MODULES -c $< -o $@

$(STAGE1OBJS_NETWORK_STANDALONE): %-NETWORK-STANDALONE.o: %.cpp .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(STAGE1_DEFS) $(NETWORK_STANDALONE_DEFS) $(USB_DEFS_GEN) -c $< -o $@

$(STAGE1OBJS_FULL): %-FULL.o: %.cpp .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(STAGE1_DEFS) $(USB_DEFS_GEN) $(PCMCIA_DEFS) $(STAGE1_DEFS) -c $< -o $@

$(FRONTEND_OBJS) $(LOCALOBJS): %.o: %.cpp .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(STAGE1_DEFS) -c $< -o $@


.cpp.o: .depend
	$(DIET) $(COMPILE) $(INCLUDES) $(STAGE1_DEFS) -c $<

endif

clean: $(CLEANDIRS)
	rm -f *.o .depend *.rdz *.img pci-ids.h pcmcia-ids.h usb-ids.h $(BINS)
$(CLEANDIRS): 
	$(MAKE) -C $(@:clean-%=%) clean

.PHONY: subdirs $(DIRS)
.PHONY: subdirs $(BUILDDIRS)
.PHONY: subdirs $(CLEANDIRS)
.PHONY: subdirs ldetect
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

#$@ $^
dist-svn:
	mkdir -p $(PRODUCT)-$(VERSION)/
	svn export -q -rBASE . $(PRODUCT)-$(VERSION)/mdk-stage1
	svn export -q -rBASE ldetect/  --force $(PRODUCT)-$(VERSION)/mdk-stage1/ldetect
	svn export -q -rBASE ../kernel $(PRODUCT)-$(VERSION)/kernel
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfa $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)/
	rm -rf $(PRODUCT)-$(VERSION)

dist-git:
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD mdk-stage1 kernel Makefile.config | xz >mdk-stage1/$(PRODUCT)-$(VERSION).tar.xz;

install:
	install -m755 stage1 -D $(DESTDIR)$(ROOTDEST)/stage1
ifeq (0, $(ONE_BINARY))
	install -m755 rescue-gui -D $(DESTDIR)$(ROOTDEST)/rescue-gui
	install -m755 dhcp-client -D $(DESTDIR)$(ROOTDEST)/dhcp-client
	install -m755 probe-modules -D $(DESTDIR)$(ROOTDEST)/probe-modules
	install -m755 drvinst -D $(DESTDIR)$(ROOTDEST)/drvinst
	install -m755 lspcidrake -D $(DESTDIR)$(ROOTDEST)/lspcidrake
else
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/rescue-gui
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/dhcp-client
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/probe-modules
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/drvinst
	ln -f $(DESTDIR)$(ROOTDEST)/stage1 $(DESTDIR)$(ROOTDEST)/lspcidrake
endif
	if [ -e pcmcia/pcmcia_probe.o ]; then \
		install -m644 pcmcia/pcmcia_probe.o -D $(DESTDIR)$(ROOTDEST)/pcmcia_probe.o; \
	fi


.DELETE_ON_ERROR:
pcmcia/lex_config.cpp: pcmcia/lex_config.c
	ln -s lex_config.c pcmcia/lex_config.cpp

.depend: $(HEADERS) ldetect/pciclass.cpp ldetect/usbclass.cpp pcmcia/lex_config.c
	$(CXX) $(DEFS) $(INCLUDES) $(CXXFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif


*-NETWORK.o: %-NETWORK.o: %.o

*-FULL.o: %-FULL.o: %.o

