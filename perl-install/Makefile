SO_FILES = c/blib/arch/auto/c/c.so
PMS = *.pm c/*.pm resize_fat/*.pm commands diskdrake
DEST = /tmp/t
DESTREP4PMS = $(DEST)/usr/bin/perl-install
PERL = perl
LOCALFILES = $(PERL) mouseconfig fr.map

.PHONY: all tags install clean verify_c

all: $(SO_FILES)

tags:
	etags -o - $(PMS) | perl2etags > TAGS

clean:
	test ! -e c/Makefile || $(MAKE) -C c clean
	rm -f c/c.xs
	find . -name "*~" -o -name "TAGS" -o -name "*.old" | xargs rm -f

tar: clean
	cd .. ; tar cfy perl-install.tar.bz2 $(LOCALFILES:%=--exclude %) perl-install

tar-diskdrake: clean
	cd .. ; cp -af perl-install diskdrake

	l=`perl2fcalls -uses -excludec diskdrake | sort | uniq | sed -e 's/::/\//' -e 's/^/diskdrake\//' -e 's/$$/.pm/'` ; \
	cd .. ; tar cfvy diskdrake.tar.bz2 diskdrake/diskdrake $$l

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

	cp diskdrake.rc $(DESTREP4PMS)
	ln -sf perl-install/install2.pm $(DEST)/usr/bin/install2
	ln -sf perl-install/commands $(DEST)/usr/bin/commands
	chmod a+x $(DESTREP4PMS)/install2.pm
	chmod a+x $(DESTREP4PMS)/commands

	cp -af */blib/arch/auto $(DESTREP4PMS)
	find $(DESTREP4PMS) -name "*.so" | xargs strip

get_needed_files: $(SO_FILES)
#	export PERL_INSTALL_TEST=1 ; strace -f -e trace=file -o '| grep -v "(No such file or directory)" | sed -e "s/[^\"]*\"//" -e "s/\".*//" | grep "^/" | grep -v -e "^/tmp" -e "^/home" -e "^/proc" -e "^/var" -e "^/dev" -e "^/etc" -e "^/usr/lib/rpm" > /tmp/list ' $(PERL) -d install2.pm < /dev/null
	cp -f list /tmp/list
	for i in $(LOCALFILES) `cat /tmp/list` ; do \
		ldd $$i 2>/dev/null | sed -e 's/.*=> //' -e 's/ .*//' | uniq | sort >> /tmp/list; \
	done

	install -d $(DEST)/lib
	install -d $(DEST)/bin
	install -d $(DEST)/usr/bin
	install -s $(LOCALFILES) $(DEST)/usr/bin

	for i in `cat /tmp/list`; do \
		if (echo $$i | grep "lib/[^/]*\.so"); then \
		  install -s $$i $(DEST)/lib; \
		else \
		  d=`echo $(DEST)/$$i | sed -e 's/\/usr\/local\//\/usr\//' -e 's/\/sbin\//\/bin\//'`; \
		  install -d `dirname $$d` && \
		  if (echo $$i | grep "\.pm"); then \
		     perl -pe '$$_ eq "__END__" and exit(0);' $$i > $$d; \
		  else \
		  	  cp -f $$i $$d; \
			  strip $$d 2>/dev/null || true; \
		  fi; \
		fi; \
	done

	ln -sf ../usr/bin/tr $(DEST)/bin/tr
	ln -sf sh $(DEST)/bin/bash
	ln -sf ash $(DEST)/bin/sh
	ln -sf ../../bin/sh $(DEST)/usr/bin/sh
	ln -sf ../../bin/mke2fs $(DEST)/usr/bin/mke2fs

	install -d $(DEST)/lib/fonts
	cp -a /usr/lib/X11/fonts/misc $(DEST)/lib/fonts

	echo -e "#!/usr/bin/perl\n\nsymlink '/tmp/rhimage/usr/lib/perl5', '/usr/lib/perl5';\nexec '/usr/bin/sh'" > $(DEST)/usr/bin/runinstall2
	chmod a+x $(DEST)/usr/bin/runinstall2

as_root:
	/bin/dd if=/dev/zero of=/tmp/initrd bs=1k count=4000
	echo y | /sbin/mke2fs /tmp/initrd
	losetup /dev/loop0 /tmp/initrd
	mount /dev/loop0 /mnt/initrd
	chmod a+w /mnt/initrd

full_stage2:
	rm -rf $(DEST)/[^M]*
	rm -f $(DEST)/Mandrake/instimage ; ln -s .. $(DEST)/Mandrake/instimage
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
