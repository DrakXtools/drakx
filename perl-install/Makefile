VERSION = 2.2.10-BOOT
SUDO = sudo
SO_FILES = c/blib/arch/auto/c/c.so
PMS = *.pm c/*.pm resize_fat/*.pm po/*.pm pci_probing/*.pm commands install2 diskdrake XFdrake
ROOTDEST = /export
DEST = $(ROOTDEST)/Mandrake/mdkinst
STAGE2 = $(ROOTDEST)/Mandrake/base/mdkinst_stage2
DESTREP4PMS = $(DEST)/usr/bin/perl-install
PERL = perl
LOCALFILES = $(PERL) mouseconfig
DIRS = po pci_probing
EXCLUDE = $(LOCALFILES) boot.img xmodmap keymaps consolefonts install

CFLAGS	= -Wall
override CFLAGS  += -pipe

.PHONY: all $(DIRS) tags install clean stage2 full_stage2 verify_c

all: $(SO_FILES) $(DIRS)

tags:
	etags -o - $(PMS) | perl2etags > TAGS

clean:
	test ! -e c/Makefile || $(MAKE) -C c clean
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf c/c.xs gendepslist ../diskdrake*
	find . -name "*~" -o -name "TAGS" -o -name "*.old" | xargs rm -f

tar: clean
	cd .. ; tar cfy perl-install.tar.bz2 $(EXCLUDE:%=--exclude %) perl-install

floppy:
	dd if=/dev/zero of=/tmp/initrd bs=1k count=2000 ; echo y | mke2fs /tmp/initrd ; mount /tmp/initrd /mnt/disk/ -o loop ; cp -a ../install1/* /mnt/disk/ ; umount /mnt/disk ; gzip -c /tmp/initrd > /tmp/initrd.img ; mcopy -o /tmp/initrd.img a:

tar-diskdrake: clean pci_probing
	cd .. ; rm -rf diskdrake ; cp -af perl-install diskdrake

	l=`./perl2fcalls -uses -excludec diskdrake | sort | uniq | sed -e 's/::/\//' -e 's/^/diskdrake\//' -e 's/$$/.pm/'` ; \
	cd .. ; tar cfz diskdrake.tgz --exclude CVS $(patsubst %,diskdrake/%,c po diskdrake*) $$l

tar-XFdrake: clean
	cd .. ; rm -rf XFdrake ; cp -af perl-install XFdrake

	l=`./perl2fcalls -uses -excludec -excludepci_probing::ids XFdrake | sort | uniq | sed -e 's/::/\//' -e 's/^/XFdrake\//' -e 's/$$/.pm/'` ; \
	cd .. ; tar cfz XFdrake.tgz --exclude CVS $(patsubst %,XFdrake/%,c MonitorsDB po pci_probing XFdrake*) $$l

c/c.xs: c/c.xs.pm
	rm -f $@
	export C_RPM=1 ; perl $< > $@
	chmod a-w $@

$(SO_FILES): c/c.xs
	test -e c/Makefile || (cd c; export C_RPM=1 ; perl Makefile.PL)
	$(MAKE) -C c

$(DIRS):
	$(MAKE) -C $@

test_pms: verify_c
	./perl2fcalls -excludec install2
	(for i in $(PMS); do perl -cw -I. -Ic -Ic/blib/arch $$i || exit 1 ; done)

verify_c:
	./verify_c $(PMS)

gendepslist: %: %.cc
	$(CXX) -I/usr/include/rpm $(CFLAGS) $< -lrpm -ldb1 -lz -o $@

depslist: gendepslist
	./gendepslist $(ROOTDEST)/Mandrake/base/depslist /tmp/rhimage/Mandrake/RPMS/*.rpm

install_pms: all
	for i in `perl -ne 's/sub (\w+?)_? {.*/$$1/ and print' commands.pm`; do ln -sf commands $(DEST)/usr/bin/$$i; done

	install -d $(DESTREP4PMS)
	for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -ne 'print #unless /^use (diagnostics|vars|strict)/' $$i > $(DESTREP4PMS)/$$i; \
	done

	rm $(DESTREP4PMS)/c/c.xs.pm
	mv -f $(DESTREP4PMS)/c/c.pm $(DESTREP4PMS)

	cp *.rc $(DESTREP4PMS)
	ln -sf perl-install/install2 $(DEST)/usr/bin
	ln -sf perl-install/commands $(DEST)/usr/bin
	chmod a+x $(DESTREP4PMS)/install2
	chmod a+x $(DESTREP4PMS)/commands

	cp -af */blib/arch/auto $(DESTREP4PMS)
	find $(DESTREP4PMS) -name "*.so" | xargs strip

get_needed_files: $(SO_FILES)
#	export PERL_INSTALL_TEST=1 ; strace -f -e trace=file -o '| grep -v "(No such file or directory)" | sed -e "s/[^\"]*\"//" -e "s/\".*//" | grep "^/" | grep -v -e "^/tmp" -e "^/home" -e "^/proc" -e "^/var" -e "^/dev" -e "^/etc" -e "^/usr/lib/rpm" > /tmp/list ' $(PERL) -d install2 < /dev/null
	cp -f list /tmp/list
	for i in c/blib/arch/auto/c/c.so $(LOCALFILES) `cat /tmp/list` ; do \
		ldd $$i 2>/dev/null | grep -v "not a dynamic" | sed -e 's/.*=> //' -e 's/ .*//' | uniq | sort >> /tmp/list; \
	done

	install -d $(DEST)/etc
	install -d $(DEST)/lib
	install -d $(DEST)/bin
	install -d $(DEST)/usr/bin
	install -d $(DEST)/usr/lib
	install -d $(DEST)/usr/share
	install -d $(ROOTDEST)/Mandrake/base
	install -s $(LOCALFILES) $(DEST)/usr/bin

	for i in `cat /tmp/list`; do \
		if (echo $$i | grep -q "lib/[^/]*\.so"); then \
		  install -s $$i $(DEST)/lib; \
		else \
		  d=`echo $(DEST)/$$i | sed 's/\/usr\/local\//\/usr\//'`; \
		  install -d `dirname $$d` && \
		  if (echo $$i | grep -q "\.pm"); then \
		     perl -pe '$$_ =~ /^__END__/ and exit(0);' $$i > $$d; \
		  else \
		  	  cp -f $$i $$d; \
			  strip $$d 2>/dev/null || true; \
		  fi; \
		fi; \
	done

	mv -f $(DEST)/bin/* $(DEST)/sbin/* $(DEST)/usr/bin
	cd $(DEST)/usr/bin ; mv insmod insmod_
	rmdir $(DEST)/bin $(DEST)/sbin

	ln -sf ash $(DEST)/usr/bin/sh

	install -d $(DEST)/usr/X11R6/lib/X11/fonts/75dpi
	install -d $(DEST)/usr/X11R6/lib/X11/fonts/misc
	cd /usr/X11R6/lib/X11/fonts/75dpi ; cp -a fonts.* helvR* $(DEST)/usr/X11R6/lib/X11/fonts/75dpi
	cd /usr/X11R6/lib/X11/fonts/misc ; cp -a fonts.* cursor.pcf.gz 6x13.pcf.gz $(DEST)/usr/X11R6/lib/X11/fonts/misc

	cp -a xmodmap $(DEST)/usr/share
	cp -a keymaps $(DEST)/usr/share
	cp -a consolefonts $(DEST)/usr/share
	cp MonitorsDB $(DEST)/usr/share
	cp logo-mandrake.xpm $(DEST)/usr/share
	cp compss $(ROOTDEST)/Mandrake/base

	cp -f ../modules/modules.cpio.bz2 $(DEST)/lib/

	ln -s install2 $(DEST)/usr/bin/runinstall2
#	echo -e "#!/bin/sh\n\nexec '/usr/bin/sh'" > $(DEST)/usr/bin/runinstall2
#	chmod a+x $(DEST)/usr/bin/runinstall2

as_root:
	/bin/dd if=/dev/zero of=/tmp/initrd bs=1k count=4000
	echo y | /sbin/mke2fs /tmp/initrd
	losetup /dev/loop0 /tmp/initrd
	mount /dev/loop0 /mnt/initrd
	chmod a+w /mnt/initrd

full_stage2:
	rm -rf $(DEST)
	mkdir -p $(DEST)
	$(MAKE) get_needed_files 
	$(MAKE) stage2

stage2:
	$(MAKE) install_pms

	dd if=/dev/zero of=$(STAGE2) bs=1M count=16
	echo y | /sbin/mke2fs $(STAGE2)
	$(SUDO) mount $(STAGE2) /mnt/stage2 -o loop
	$(SUDO) cp -a $(DEST)/* /mnt/stage2
	$(SUDO) umount $(STAGE2)
	gzip -f -9 $(STAGE2)
#	cd $(ROOTDEST) ; tar cfz /tmp/instimage-full.tgz Mandrake
#	cd $(ROOTDEST) ; tar cfz /tmp/instimage-light.tgz Mandrake/base/compss Mandrake/mdkinst/usr/[bl]*

	@#rm -rf /mnt/initrd/*
	@#cp -a $(DEST)/* /mnt/initrd
	@#sync
	@#dd if=/dev/loop0 | gzip -9 > /tmp/t/Mandrake/base/stage2.img

# function f() { grep "$*" /usr/include/*.h /usr/include/*/*.h; }

# 
# install -s install/install install1/bin/install ; install -s installinit/init install1/bin/init
# mount /tmp/initrd /mnt/disk/ -o loop ;  ; umount /mnt/disk ; gzip -c /tmp/initrd > /tmp/initrd.img ; mcopy -o /tmp/initrd.img a:

