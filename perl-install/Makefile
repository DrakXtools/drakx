PACKAGE=drakxtools
PKGVERSION:=$(shell rpm -q --qf '%{VERSION}\n' --specfile $(PACKAGE).spec|head -1)
RELEASE:=$(shell rpm -q --qf '%{RELEASE}\n' --specfile $(PACKAGE).spec|head -1)
TAG := $(shell echo "V$(PKGVERSION)_$(RELEASE)" | tr -- '-.' '__')

include Makefile.config

POFILES   = $(shell ls share/po/*.po)
MOFILES   = $(POFILES:%.po=%.mo)
DISTFILES = Makefile Makefile.config Newt apps.net_monitor diskdrake c ddcprobe drakxtools.spec pam.net_monitor serial_probe share/po sbus_probing resize_fat share/diskdrake.rc share/wizard.rc $(STANDALONEPMS) standalone/icons pixmaps network standalone/interactive_http rpcinfo-flushed.c *.pm security
OTHERS     = $(OTHERDIRS) $(OTHERFILES)
OTHERDIRS  = tools/ddcprobe tools/serial_probe
OTHERFILES = tools/rpcinfo-flushed.c

.PHONY: all $(DIRS) install clean stage2 full_stage2 verify_c 

all: TAGS $(DIRS)

TAGS: $(ALLPMS)
	etags -o - $^ /usr/lib/perl5/site_perl/*/MDK/Common/*.pm | ./perl2etags > $@

clean:
	for i in $(DIRS) share/po; do $(MAKE) -C $$i clean; done
	rm -rf auto ../drakxtools.tar.bz2
	find . -name "*~" -o -name ".#*" -o -name "TAGS" -o -name "*.old" | xargs rm -f

check:
	$(MAKE) -C share/po check
	perl -I. -Mlang -e 'lang::check'
	perl -I. -Mkeyboard -e 'keyboard::check'

localcopy: clean
	rm -rf standalone/pixmaps
	$(MAKE) -C ../tools clean
	cd .. ; rm -rf $(PACKAGE)-$(PKGVERSION) ; cp -af perl-install $(PACKAGE)-$(PKGVERSION) ; cp -af $(OTHERS) $(PACKAGE)-$(PKGVERSION)

$(DIRS):
	install -d auto
	$(MAKE) -C $@

test_pms: verify_c
	for i in install2 install_steps_*.pm standalone/keyboarddrake standalone/XFdrake standalone/drakboot; do perl_checker -I. -no_cw -excludec -excludehelp -excluderesize_fat::c_rewritten -excludeMDK::Common::Globals -excludeCGI -excludestandalone -excludeurpm $$i; done
	for i in install2 install_steps_*.pm; do perl -cw -I. $$i; done

verify_c:
	./verify_c $(ALLPMS)

%.mo: %.po
	msgfmt -o $@ $<

install_pms: $(DIRS)
	for i in `perl -ne 's/sub (\w+?)_? {.*/$$1/ and print' commands.pm` sync; do ln -sf commands $(DEST)/usr/bin/$$i; done

	install -d $(DESTREP4PMS)
	for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -ne 'print' $$i > $(DESTREP4PMS)/$$i; \
		perl -pe 's/#[-+].*//; $$_ = "\n" if (/^=head/ .. /^=cut/) || /use (diagnostics|vars|strict)/' $$i > $(DESTREP4PMS)/$$i; \
	done
	if [ "x$(PERL_INSTALL_DEBUG)" == "x" ]; then \
		perl -pi -e 's|#!/usr/bin/perl -d.*\n|#!/usr/bin/perl\n|' $(DESTREP4PMS)/install2; \
	else \
		perl -pe 's|#!/usr/bin/perl.*\n|#!/usr/bin/perl -d \n|' install2 > $(DESTREP4PMS)/install2; \
	fi \

	rm -f $(DESTREP4PMS)/{bootlook,tinyfirewall}.pm

	cp share/*.rc $(DESTREP4PMS)
	chmod a+x $(DESTREP4PMS)/install2
	chmod a+x $(DESTREP4PMS)/commands
	chmod a+x $(DESTREP4PMS)/g_auto_install
	chmod a+x $(DESTREP4PMS)/live_install*

get_needed_files: $(DIRS) $(MOFILES)
	$(MAKE) -C share

#	export PERL_INSTALL_TEST=1 ; strace -f -e trace=file -o '| grep -v "(No such file or directory)" | sed -e "s/[^\"]*\"//" -e "s/\".*//" | grep "^/" | grep -v -e "^/tmp" -e "^/home" -e "^/proc" -e "^/var" -e "^/dev" -e "^/etc" -e "^/usr/lib/rpm" > /tmp/list ' $(PERL) -d install2 < /dev/null
	eval `perl -V:version`; \
	cat share/list `../tools/specific_arch share/list` | \
	perl -pe "s/ARCH/$(ARCH)/g" | perl -pe "s/PERL_VERSION/$$version/g" > /tmp/list

	@missing=`perl -lne 'print if !-e $$_' /tmp/list`; [ -z "$$missing" ] || { echo "missing files vvvvvvvvvvvvvvvvvvvvvvvvvv" ; echo "$$missing" ; echo "missing files ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" ; exit 1; }

	find auto -follow -name "*.so" >> /tmp/list

	for i in $(LOCALFILES) `cat /tmp/list` ; do \
		ldd $$i 2>/dev/null | grep "=>" | sed -e 's/.*=> //' -e 's/ .*//' | uniq | sort >> /tmp/list; \
	done

	perl -Mlang -I. -e 'print "$$_\n" foreach lang::console_font_files()' >> /tmp/list

	install -d $(DEST)/etc
	install -d $(DEST)/etc/sysconfig/network-scripts
	install -d $(DEST)/lib
	install -d $(DEST)/bin
	install -d $(DEST)/usr/bin
	install -d $(DEST)/usr/lib
	install -d $(DEST)/usr/share
	install -d $(DEST)/usr/share/gtk
	install -d $(DEST)/usr/share/xmodmap
	install -d $(DEST)/usr/X11R6/lib/X11
	install -d $(ROOTDEST)/Mandrake/base
	install -s $(LOCALFILES) $(DEST)/usr/bin
#	cp -f $(LOCALFILES2) $(DEST)/usr/bin
	ln -s ../X11R6/lib/X11 $(DEST)/usr/lib/X11
ifeq (sparc,$(ARCH))
	cp -a /usr/X11R6/lib/X11/xkb $(DEST)/usr/X11R6/lib/X11
	rm -f $(DEST)/usr/X11R6/lib/X11/xkb/compiled
	ln -s /tmp $(DEST)/usr/X11R6/lib/X11/xkb/compiled
	ln -s /usr/X11R6/lib/X11/xkb/xkbcomp $(DEST)/usr/bin/xkbcomp
endif
ifeq (i386,$(ARCH))
	install -s /sbin/cardmgr $(DEST)/usr/bin
endif

	for i in `cat /tmp/list`; do \
	    if (echo $$i | grep -q "lib/[^/]*\.so"); then \
	      install -s $$i $(DEST)/lib; \
	    else \
	      d=$$i; \
	      (echo $$d | grep -q "^[^/]") && d="$(REP4PMS)/$$d"; \
	      d=`echo $(DEST)/$$d | sed 's/\/usr\/local\//\/usr\//'`; \
	      install -d `dirname $$d` && \
	      if (echo $$i | grep -q "\.pm"); then \
	    	 perl -pe '$$_ =~ /^__END__/ and exit(0);' $$i > $$d; \
	      elif (echo $$i | grep -q "\.so"); then \
	    	      install -s $$i $$d; \
	      else \
	    	      cp -f $$i $$d; \
	      fi; \
	    fi; \
	done
	mv -f $(DEST)/lib/libimlib-png.so $(DEST)/usr/lib

#	# transform xpm's in png's
	for i in $(DEST)/usr/share/icons/*.xpm; do convert $$i `echo $$i | sed 's/xpm/png/'`; rm $$i; done

	mv -f $(DEST)/bin/* $(DEST)/sbin/* $(DEST)/usr/bin
	cd $(DEST)/usr/bin ; mv insmod insmod_
	rmdir $(DEST)/bin $(DEST)/sbin

	perl -ane 'symlink "$$F[1]", "$(DEST)/usr/bin/$$F[0]"' share/aliases

ifeq (i386,$(ARCH))
	cp ../tools/i386/busybox $(DEST)/usr/bin
endif
	ln -sf ash $(DEST)/usr/bin/sh

	for i in fonts keyboards locales keymaps; do tar xfj `../tools/specific_arch share/$$i.tar.bz2` -C $(DEST); done

	grep ChangeLog CVS/Entries > $(DEST)/usr/share/VERSION

	gzip -9f $(DEST)/usr/share/ldetect-lst/*

	cd share ; cp -a modparm.lst $(DEST)/usr/share
	cd share ; cp -a consolefonts $(DEST)/usr/share
	-cd share ; cp -f *.png *.xpm $(DEST)/usr/share
	-cd pixmaps ; cp -f *.png *.xpm $(DEST)/usr/share ; rm -f $(DEST)/usr/share/wiz_*
	cd share ; cp -a themes $(DEST)/usr/share/gtk
	cd share ; cp compssUsers compssUsers.* rpmsrate $(ROOTDEST)/Mandrake/base

	clean-rpmsrate $(ROOTDEST)/Mandrake/base/rpmsrate $(ROOTDEST)/Mandrake/RPMS

	for i in ../all.modules/modules.cz*; do cp -f $$i $(DEST)/lib/; done

	$(MAKE) -C share/po install NAME=libDrakX LOCALEDIR=$(DEST)/usr/share/locale_special

#	echo -e '#!/bin/sh\n\nexec "/usr/bin/sh"' > $(DEST)/usr/bin/runinstall2
#	chmod a+x $(DEST)/usr/bin/runinstall2

ifeq (i386,$(ARCH))
	cp -a /etc/pcmcia $(DEST)/etc
	../tools/patch_pcmcia_config.pl $(DEST)/etc/pcmcia/config ../all.modules/`cat ../all.kernels/.main`/modules.dep
endif

	find $(DEST) -name CVS | xargs rm -rf

full_stage2:
	if [ `id -u` = 0 ]; then rm -rf $(DEST); else $(SUDO) rm -rf $(DEST); fi
	mkdir -p $(DEST)
	$(MAKE) get_needed_files 
	$(MAKE) stage2

stage2:
	$(MAKE) install_pms
	$(ROOTDEST)/misc/make_mdkinst_stage2 $(DEST) $(ROOTDEST)/Mandrake/base/mdkinst_stage2

# rules to build a test rpm

localrpm: localdist buildrpm

localsrpm: localdist buildsrpm

localdist: cleandist localcopy tar

cleandist:
	rm -rf ../$(PACKAGE)-$(PKGVERSION) ../$(PACKAGE)-$(PKGVERSION).tar.bz2

tar:
	cd ../$(PACKAGE)-$(PKGVERSION) && perl -pi -e 's/^C_RPM.*/C_RPM=0/; s/^C_DRAKX.*/C_DRAKX=0/' c/Makefile
	cd ../$(PACKAGE)-$(PKGVERSION) && perl -pi -e 's/^all: help/all:/' share/po/Makefile
	cd ../$(PACKAGE)-$(PKGVERSION) && rm -rf install* pkgs.pm help.pm ftp.pm http.pm crypto.pm t.pm */CVS && mv Makefile.drakxtools Makefile
	cd ..; tar cfj $(PACKAGE)-$(PKGVERSION).tar.bz2 --exclude CVS $(patsubst %,$(PACKAGE)-$(PKGVERSION)/%,$(DISTFILES))
	cd ..; rm -rf $(PACKAGE)-$(PKGVERSION)

buildrpm:
	rpm -ta ../$(PACKAGE)-$(PKGVERSION).tar.bz2

buildsrpm:
	rpm -ts ../$(PACKAGE)-$(PKGVERSION).tar.bz2

# rules to build a distributable rpm

rpm: cvstag dist buildrpm

srpm: cvstag dist buildsrpm

dist: cleandist export tar

export:
	cd ..; cvs export -d $(PACKAGE)-$(PKGVERSION) -r $(TAG) $(PACKAGE)
	cd ../$(PACKAGE)-$(PKGVERSION) && rm -rf $(OTHERDIRS) && set -x && for f in $(OTHERDIRS); do cvs -d `cat ../CVS/Root` export -r $(TAG) -d `basename $$f` gi/$$f; done
	cd ..; set -x && for f in $(OTHERFILES); do cvs -d `cat ../CVS/Root` export -r $(TAG) -d $(PACKAGE)-$(PKGVERSION) gi/$$f; done

cvstag:
	cvs tag $(CVSTAGOPT) $(TAG)
	cd ..; cvs tag $(CVSTAGOPT) $(TAG) $(OTHERS)
