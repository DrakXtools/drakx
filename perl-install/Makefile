SO_FILES = c/blib/arch/auto/c/c.so
PMS = *.pm c/*.pm resize_fat/*.pm commands diskdrake
DEST = /tmp/t
DESTREP4PMS = $(DEST)/usr/bin/perl-install
PERL = ./perl
BINS = /bin/ash /sbin/mke2fs $(PERL)

.PHONY: all tags install clean verify_c

all: $(SO_FILES)

tags:
	etags -o - $(PMS) | perl2etags > TAGS

clean:
	test ! -e c/Makefile || $(MAKE) -C c clean
	rm -f c/c.xs
	find . -name "*~" -o -name "TAGS" -o -name "*.old" | xargs rm -f

tar: clean
	cd .. ; tar cfy perl-install.tar.bz2 --exclude perl-install/perl perl-install

c/c.xs: c/c.xs.pm
	rm -f $@
	perl $< > $@
	chmod a-w $@

$(SO_FILES): c/c.xs
	test -e c/Makefile || (cd c; perl Makefile.PL)
	$(MAKE) -C c

test_pms: verify_c
	perl2fcalls -excludec install2.pm
	(for i in $(PMS); do perl -cw -I. -Ic -Ic/blib/arch $$i || exit 1 ; done)

verify_c:
	./verify_c $(PMS)

install_pms: $(SO_FILES)
	for i in `perl -ne 's/sub (\w+?)_? {.*/$$1/ and print' commands.pm`; do ln -sf commands $(DEST)/usr/bin/$$i; done

	install -d $(DESTREP4PMS)
	for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -ne 'print #unless /^use (diagnostics|vars|strict)/' $$i > $(DESTREP4PMS)/$$i; \
	done
	@#	cp -f $$i $$dest; \
	cp diskdrake.rc $(DESTREP4PMS)
	ln -sf perl-install/install2.pm $(DEST)/usr/bin/install2
	ln -sf perl-install/commands $(DEST)/usr/bin/commands
	chmod a+x $(DESTREP4PMS)/install2.pm
	chmod a+x $(DESTREP4PMS)/commands

	cp -af */blib/arch/auto $(DESTREP4PMS)
	find $(DESTREP4PMS) -name "*.so" | xargs strip

full_tar:
	cp -af /usr/lib/perl5/site_perl/5.005/i386-linux/Gtk* $(DESTREP4PMS)
	cp -af /usr/lib/perl5/site_perl/5.005/i386-linux/auto/Gtk $(DESTREP4PMS)/auto
	find $(DESTREP4PMS) -name "*.so" | xargs strip
	cd $(DESTREP4PMS)/.. ; tar cfz /tmp/perl-install.tgz perl-install

get_needed_files: $(SO_FILES)
	export PERL_INSTALL_TEST=1 ; strace -f -e trace=file -o '| grep -v "(No such file or directory)" | sed -e "s/[^\"]*\"//" -e "s/\".*//" | grep "^/" | grep -v -e "^/tmp" -e "^/home" -e "^/proc" -e "^/var" -e "^/dev" -e "^/etc" -e "^/usr/lib/rpm" > /tmp/list ' $(PERL) -d install2.pm < /dev/null
	perl -pi -e 's|/usr/local/|/usr/|' /tmp/list

	install -d $(DEST)/bin
	install -d $(DEST)/usr/bin
	for i in $(BINS) `grep "\.so" /tmp/list`; do \
		install -s $$i $(DEST)/lib; \
		ldd $$i | sed -e 's/.*=> //' -e 's/ .*//' >> /tmp/list; \
	done
	for i in `sort /tmp/list | uniq`; do \
		install -d $(DEST)/`dirname $$i` && \
		if (echo $$i | grep "\.pm"); then \
		   perl -pe '$$_ eq "__END__" and exit(0);' $$i > $(DEST)/$$i; \
		else \
			cp -f $$i $(DEST)/$$i; \
		fi && \
		strip $(DEST)/$$i 2>/dev/null || true; \
	done
	mv $(DEST)/usr/lib/*.so* $(DEST)/lib

	ln -sf ../usr/bin/sh $(DEST)/bin/sh
	ln -sf ../usr/bin/tr $(DEST)/bin/tr
	ln -sf sh $(DEST)/bin/bash
	ln -sf ash $(DEST)/usr/bin/sh

	echo -e "#!/usr/bin/perl\n\nsymlink '/tmp/rhimage/usr/lib/perl5', '/usr/lib/perl5';\nexec '/bin/sh'" > $(DEST)/usr/bin/runinstall2
	chmod a+x $(DEST)/usr/bin/runinstall2

as_root:
	/bin/dd if=/dev/zero of=/tmp/initrd bs=1k count=4000
	echo y | /sbin/mke2fs /tmp/initrd
	losetup /dev/loop0 /tmp/initrd
	mount /dev/loop0 /mnt/initrd
	chmod a+w /mnt/initrd

full_stage2:
	rm -rf $(DEST)/[^M]*
	ln -sf .. $(DEST)/Mandrake/instimage
	@#mkdir -p $(DEST)/Mandrake/base
	@#ln -s .. $(DEST)/Mandrake/instimage
	$(MAKE) get_needed_files 
	$(MAKE) stage2

stage2:
	$(MAKE) install_pms

	@#rm -rf /mnt/initrd/*
	@#cp -a $(DEST)/* /mnt/initrd
	@#sync
	@#dd if=/dev/loop0 | gzip -9 > /tmp/t/Mandrake/base/stage2.img


# function f() { grep "$*" /usr/include/*.h /usr/include/*/*.h; }
