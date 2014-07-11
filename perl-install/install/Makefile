include ../../Makefile.config
include ../Makefile.config

PRODUCT=$(FAMILY)-stage2
COMPRESS ?= xz -T0 --x86 --lzma2 -ve9 --check=crc32

STAGE2_DEST = $(ROOTDEST)/install/stage2
DEST = $(STAGE2_DEST)/live

REP4PMS     = /usr/lib/libDrakX
DESTREP4PMS = $(DEST)$(REP4PMS)

all: pixmaps/left-background.png xs

xs:
	make -C .. $@

clean:
	rm -f pixmaps/left-background.png
	make -C .. $@

dist: dist-git

dist-svn:
	mkdir -p $(PRODUCT)-$(VERSION)
	svn export -q -rBASE .. $(PRODUCT)-$(VERSION)/perl-install
	svn export -q -rBASE ../../tools $(PRODUCT)-$(VERSION)/tools
	svn export -q -rBASE ../../kernel $(PRODUCT)-$(VERSION)/kernel
	cp ../../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfa $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

dist-git:
	cd ../..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD kernel perl-install tools images/tree/root Makefile.config > perl-install/install/$(PRODUCT)-$(VERSION).tar
	cd share/meta-task; \
	git archive --format=tar --prefix=$(PRODUCT)-$(VERSION)/perl-install/install/share/meta-task/ HEAD . > meta-task-$(PRODUCT)-$(VERSION).tar
	tar --concatenate --file=$(PRODUCT)-$(VERSION).tar share/meta-task/meta-task-$(PRODUCT)-$(VERSION).tar
	rm share/meta-task/meta-task-$(PRODUCT)-$(VERSION).tar
	xz -v9ef -T0 $(PRODUCT)-$(VERSION).tar
	git tag $(PRODUCT)-$(VERSION)

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@if [ -e "../.svn" ]; then \
		$(MAKE) dist-svn; \
	elif [ -e "../../.git" ]; then \
		$(MAKE) dist-git; \
	else \
		echo "Unknown SCM (not SVN nor GIT)";\
		exit 1; \
	fi;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

install:
	$(MAKE) full_stage2
	echo $(VERSION) > $(DESTDIR)$(STAGE2_DEST)/VERSION

install_pms:
	[ -d $(DESTDIR)$(DEST) ] || ../../tools/mdkinst_stage2_tool --uncompress $(DESTDIR)$(STAGE2_DEST)

	for i in `perl -ne 's/sub (\w+?)_?(\(\))? {.*/$$1/ and print' commands.pm`; do ln -sf commands $(DESTDIR)$(DEST)/usr/bin/$$i; done

	install -d $(DESTDIR)$(DESTREP4PMS)
	cd .. ; for i in $(PMS); do \
		dest=$(DESTDIR)$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -pe 's/#[-+].*//; $$_ = "\n" if (/^=(back|begin|head|item|over|pod)/ .. /^=cut/) || /use (diagnostics|strict|vars|warnings)/' $$i > $(DESTDIR)$(DESTREP4PMS)/$$i; \
	done

	cp ../share/*.css $(DESTDIR)$(DESTREP4PMS)
	chmod a+x $(DESTDIR)$(DESTREP4PMS)/install/install2
	chmod a+x $(DESTDIR)$(DESTREP4PMS)/install/commands

get_needed_files: xs
	REP4PMS=$(REP4PMS) ../../tools/install-xml-file-list share/list.xml $(DESTDIR)$(DEST)
	chmod u-s -R $(DESTDIR)$(DEST) # for mount/umount
	share/generate-xlocales $(DESTDIR)$(DEST)

	../../tools/simplify-drakx-modules $(DESTDIR)$(DEST)/usr/*/*/*/utf8_heavy.pl

	perl -I.. -Mlang -e 'symlink "UTF-8", "$(DESTDIR)$(DEST)/usr/share/locale/$$_" foreach lang::list_langs()'

	perl -ane 'symlink "$$F[1]", "$(DESTDIR)$(DEST)$$F[0]"' share/aliases

	mkfontdir $(DESTDIR)$(DEST)/usr/share/fonts
	fc-cache -f $(DESTDIR)$(DEST)/usr/share/fonts

	$(MAKE) -C ../share/po install SUDO= LOCALEDIR=$(DESTDIR)$(DEST)/usr/share/locale_special
	$(MAKE) -C help/po install SUDO= LOCALEDIR=$(DESTDIR)$(DEST)/usr/share/locale_special
	$(MAKE) -C share/po install SUDO= LOCALEDIR=$(DESTDIR)$(DEST)/usr/share/locale_special
# POFILES to disable for installation:
# be,fur: too few messages translated; 
# ta: font problem
	rm -rf $(DESTDIR)$(DEST)/usr/share/locale_special/{be,fur,ta}


pixmaps/left-background.png: pixmaps/left-background.xcf
	../../tools/xcf2png  -i $^ -o $@ -a indexed -c 75

full_stage2:
	$(MAKE) stage2
	@if [ "$${DEBUG_INSTALL+xxx}" ]; then make dont_run_directly_stage2; else : ; fi
	$(MAKE) compress

compress:
	(cd $(DESTDIR)$(STAGE2_DEST)/live; find | cpio -o -H newc -H newc --quiet --owner=root:root| $(COMPRESS)) > $(DESTDIR)$(STAGE2_DEST)/mdkinst.cpio.xz
	rm -rf $(DESTDIR)$(STAGE2_DEST)/live

stage2: pixmaps/left-background.png
	rm -rf $(DESTDIR)$(DEST)
	mkdir -p $(DESTDIR)$(DEST)
	$(MAKE) get_needed_files 
	$(MAKE) install_pms

dont_run_directly_stage2:
	[ -d $(DESTDIR)$(DEST) ] || ../../tools/mdkinst_stage2_tool --uncompress $(DESTDIR)$(STAGE2_DEST)
	install -m 755 share/runinstall2.sh $(DESTDIR)$(DEST)/usr/bin/
	ln -sf runinstall2.sh $(DESTDIR)$(DEST)/usr/bin/runinstall2

trace_stage2:
	[ -d $(DESTDIR)$(DEST) ] || ../../tools/mdkinst_stage2_tool --uncompress $(DESTDIR)$(STAGE2_DEST)
	f=`perldoc -l Devel::Trace`; install -m 644 -D $$f $(DESTDIR)$(DEST)$$f
	perl -pi -e 's|(#!/usr/bin/perl).*|$$1 -d:Trace|' $(DESTDIR)$(DEST)/usr/bin/runinstall2

# [pixel] after make install_pms:
# sudo sh -c 'CLEAN=1 perl ../../tools/drakx-in-chroot /export /tmp/rr --useless_thing_accepted --kickstart install/auto_inst.cfg.local.pl'
