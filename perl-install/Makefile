PACKAGE=drakxtools
PKGVERSION:=$(shell rpm -q --qf '%{VERSION}\n' --specfile $(PACKAGE).spec|head -n 1)
RELEASE:=$(shell rpm -q --qf '%{RELEASE}\n' --specfile $(PACKAGE).spec|head -n 1)
TAG := $(shell echo "V$(PKGVERSION)_$(RELEASE)" | tr -- '-.' '__')

include ../Makefile.config
include Makefile.config

POFILES   = $(shell ls share/po/*.po)
MOFILES   = $(POFILES:%.po=%.mo)
DISTFILES = *.pm $(PMS_DIRS) Makefile Makefile.config drakxtools.spec serial_probe share/po share/diskdrake.rc $(STANDALONEPMS) standalone/icons standalone/man/C/* pixmaps pixmaps/langs standalone/interactive_http rpcinfo-flushed.c share/rpmsrate standalone/convert standalone/finish-install.xsetup standalone/service_harddrake.sh
OTHERS     = $(OTHERDIRS) $(OTHERFILES)
OTHERDIRS  = tools/serial_probe
OTHERFILES = tools/rpcinfo-flushed.c

STAGE1 = ../mdk-stage1

USE_PCMCIA := n
ifeq ($(ARCH),i386)
USE_PCMCIA := y
endif
ifeq ($(ARCH),x86_64)
USE_PCMCIA := y
endif

.PHONY: all $(DIRS) install clean stage2 full_stage2

all: list_modules.pm TAGS $(DIRS)

up:
	(cd ..; cvs up;cd -;make localsrpm;up /home/tv/rpm/SRPMS/drakxtools-$(PKGVERSION)-$(RELEASE:).src.rpm)


xs: $(DIRS)

list_modules.pm:
	ln -sf ../kernel/list_modules.pm

TAGS: $(ALLPMS)
	@etags -o - $^ /usr/lib/perl5/*/*/MDK/Common/*.pm | ./perl2etags > $@

clean:
	for i in $(DIRS) share/po; do $(MAKE) -C $$i clean; done;:
	rm -rf auto ../drakxtools.tar.bz2 *.bak
	find . -name "*~" -o -name ".#*" -o -name "TAGS" -o -name "*.old" | xargs rm -f

check_pms_encoding:
	@for i in $(ALLPMS); do charset=ascii; grep -q 'use utf8' $$i && charset=utf8; iconv -f $$charset -t $$charset $$i >/dev/null || { echo "bad $$charset character in $$i"; exit 1; }; done

check: check_pms_encoding
	perl -I. -Mlang -e 'lang::check'

check2:
	perl -I. -Mkeyboard -e 'keyboard::check'

localcopy: clean
	rm -rf standalone/pixmaps
	$(MAKE) -C ../tools clean || :
	cd .. ; rm -rf $(PACKAGE)-$(PKGVERSION) ; cp -af perl-install $(PACKAGE)-$(PKGVERSION) ; cp -af $(OTHERS) $(PACKAGE)-$(PKGVERSION)
	cd .. ; rm -f $(PACKAGE)-$(PKGVERSION)/c/probe.c; cp -a mdk-stage1/{log.h,pcmcia_/{probe.c,*.h}} $(PACKAGE)-$(PKGVERSION)/c/
	cd
	@make nuke_perl


$(DIRS):
	install -d auto
	$(MAKE) -C $@

test_pms:
	perl_checker install2.pm install_steps_gtk.pm install_steps_stdio.pm partition_table/*.pm standalone/{harddrake2,diskdrake,draksec}

test_pms_all:
	perl_checker $(shell echo $(ALLPMS) | perl -pe 's!(printer|share/advertising)\S+!!g')

%.mo: %.po
	msgfmt -o $@ $<

install_pms: $(DIRS)
	[ -d $(DEST) ] || $(MISC_DEST)/mdkinst_stage2_tool $(STAGE2_DEST)

	for i in `perl -ne 's/sub (\w+?)_?(\(\))? {.*/$$1/ and print' commands.pm` sync; do ln -sf commands $(DEST)/usr/bin/$$i; done

	install -d $(DESTREP4PMS)
	find $(DESTREP4PMS) -name "*.pm.gz" | xargs rm -f
	for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -ne 'print' $$i > $(DESTREP4PMS)/$$i; \
		perl -pe 's/#[-+].*//; $$_ = "\n" if (/^=(head|begin)/ .. /^=cut/) || /use (diagnostics|strict|vars|warnings)/' $$i > $(DESTREP4PMS)/$$i; \
	done

	rm -f $(DESTREP4PMS)/{bootlook,tinyfirewall}.pm

	cp share/*.rc $(DESTREP4PMS)
	chmod a+x $(DESTREP4PMS)/install2
	chmod a+x $(DESTREP4PMS)/commands

mo_files : $(MOFILES)

get_needed_files: $(DIRS) mo_files
	REP4PMS=$(REP4PMS) ../tools/install-xml-file-list share/list.xml $(DEST)
	$(SUDO) chmod u-s -R $(DEST)

	mv -f $(DEST)/usr/{$(LIB),X11R6/$(LIB)}/*.so* $(DEST)/$(LIB)
	../tools/simplify-drakx-modules $(DEST)/usr/*/*/*/utf8_heavy.pl

	cp -f $(STAGE1)/init-stage2 $(DEST)/etc/init

	cat share/symlinks `../tools/specific_arch share/symlinks` > $(DEST)/usr/share/symlinks

	perl -I. -Mlang -e 'symlink "UTF-8", "$(DEST)/usr/share/locale/$$_" foreach lang::list_langs()'

	perl -ane 'symlink "$$F[1]", "$(DEST)$$F[0]"' share/aliases
ifeq (ia64,$(ARCH))
	ln -sf bash $(DEST)/bin/sh
else
	ln -sf ash $(DEST)/bin/sh
endif

	mkfontdir $(DEST)/usr/X11R6/lib/X11/fonts
	fc-cache -f $(DEST)/usr/X11R6/lib/X11/fonts

	for i in `ls ../kernel/all.kernels`; do cp -f ../kernel/all.kernels/$$i/modules.cz $(DEST)/lib/modules.cz-$$i; done
	ls ../kernel/all.kernels | grep '^2' > $(STAGE2_DEST)/mdkinst.kernels

	$(MAKE) -C share/po install SUDO= NAME=libDrakX LOCALEDIR=$(DEST)/usr/share/locale_special
# POFILES to disable for installation:
# be,fur: too few messages translated; 
# ta: font problem
	rm -rf $(DEST)/usr/share/locale_special/{be,fur,ta}

ifeq (y,$(USE_PCMCIA))
	install -s /sbin/cardmgr $(DEST)/sbin
	cp -a /etc/pcmcia $(DEST)/etc
	../tools/patch_pcmcia_config.pl $(DEST)/etc/pcmcia/config ../kernel/all.kernels/`cat ../kernel/RPMS/.main`/modules.dep
endif

	install -d $(MEDIA_INFO_DEST)
	grep ChangeLog CVS/Entries > $(STAGE2_DEST)/VERSION

	cd share ; cp compssUsers.pl* rpmsrate $(MEDIA_INFO_DEST)
	clean-rpmsrate $(MEDIA_INFO_DEST)/rpmsrate $(MAIN_RPMS_DIR)

full_stage2:
	$(MAKE) stage2
	$(MAKE) clp

clp:
	$(MISC_DEST)/mdkinst_stage2_tool $(STAGE2_DEST)

stage2:
	if [ `id -u` = 0 ]; then rm -rf $(DEST); else $(SUDO) rm -rf $(DEST); fi
	mkdir -p $(DEST)
	$(MAKE) get_needed_files 
	$(MAKE) install_pms

# rules to build a test rpm

localrpm: localdist buildrpm

localsrpm: spec_test localdist buildsrpm

srpm: spec_test cvstag localsrpm

localdist: cleandist localcopy tar

cleandist:
	rm -rf ../$(PACKAGE)-$(PKGVERSION) ../$(PACKAGE)-$(PKGVERSION).tar.bz2

spec_test:
	@if [[ -z "$(PKGVERSION)"  ]]; then echo "unable to get spec version"; exit 3;fi
	@if [[ -z "$(RELEASE)"  ]]; then echo "unable to get spec release"; exit 2;fi

tar:
	cd ../$(PACKAGE)-$(PKGVERSION) && perl -pi -e 's/^all: help/all:/' share/po/Makefile
	cd ../$(PACKAGE)-$(PKGVERSION) && rm -rf install* pkgs.pm help.pm ftp.pm http.pm crypto.pm t.pm debug.log `find -name CVS`
	cd ../$(PACKAGE)-$(PKGVERSION) && mv -f Makefile.drakxtools Makefile
	cd ../$(PACKAGE)-$(PKGVERSION) && rm -f list_modules.pm && cp -f ../kernel/list_modules.pm .
	cd ..; tar cfj $(PACKAGE)-$(PKGVERSION).tar.bz2 $(patsubst %,$(PACKAGE)-$(PKGVERSION)/%,$(DISTFILES))
	cd ..; rm -rf $(PACKAGE)-$(PKGVERSION)

buildrpm:
	rpm -ta ../$(PACKAGE)-$(PKGVERSION).tar.bz2

buildsrpm:
	rpm -ts --nodeps ../$(PACKAGE)-$(PKGVERSION).tar.bz2

# rules to build a distributable rpm

rpm: cvstag dist buildrpm

slowsrpm: spec_test cvstag dist buildsrpm

dist: cleandist export tar

export:
	cd ..; cvs export -d $(PACKAGE)-$(PKGVERSION) -r $(TAG) $(PACKAGE)
	cd ../$(PACKAGE)-$(PKGVERSION) && rm -rf $(OTHERDIRS) && set -x && for f in $(OTHERDIRS); do cvs -d `cat ../CVS/Root` export -r $(TAG) -d `basename $$f` gi/$$f; done
	cd ..; set -x && for f in $(OTHERFILES); do cvs -d `cat ../CVS/Root` export -r $(TAG) -d $(PACKAGE)-$(PKGVERSION) gi/$$f; done
	@make nuke_perl

cvstag:
	cvs tag $(CVSTAGOPT) $(TAG)
	cd ..; cvs tag $(CVSTAGOPT) $(TAG) $(OTHERS)

nuke_perl:
	find ../$(PACKAGE)-$(PKGVERSION) -name '*.pm' | xargs ../tools/simplify-drakx-modules
	find ../$(PACKAGE)-$(PKGVERSION)/standalone -type f | xargs ../tools/simplify-drakx-modules

dont_run_directly_stage2:
	[ -d $(DEST) ] || $(MISC_DEST)/mdkinst_stage2_tool $(STAGE2_DEST)
	echo -e '#!/bin/sh\n\nexec /usr/bin/busybox sh' > $(DEST)/usr/bin/runinstall2.sh
	chmod a+x $(DEST)/usr/bin/runinstall2.sh
	ln -sf runinstall2.sh $(DEST)/usr/bin/runinstall2

trace_stage2:
	[ -d $(DEST) ] || $(MISC_DEST)/mdkinst_stage2_tool $(STAGE2_DEST)
	f=`perldoc -l Devel::Trace`; install -m 644 -D $$f $(DEST)$$f
	perl -pi -e 's|(#!/usr/bin/perl).*|$$1 -d:Trace|' $(DEST)/usr/bin/runinstall2

# [pixel] for my grep looking for any .pm files
pixel_standalone_links:
	rm -rf .standalone_apps.swa
	mkdir .standalone_apps.swa
	for i in $(STANDALONEPMS_); do ln -sf ../standalone/$$i .standalone_apps.swa/$$i.pm; done

# [pixel] after make install_pms:
# sudo perl ../tools/drakx-in-chroot /export /tmp/rr --useless_thing_accepted --kickstart install/auto_inst.cfg.local.pl
