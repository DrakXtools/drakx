VERSION     = 2.2.10-BOOT                                                                             
SUDO        = sudo
SO_FILES    = c/blib/arch/auto/c/c.so                                                                 
PMS         = *.pm Newt/*.pm c/stuff.pm resize_fat/*.pm pci_probing/*.pm commands install2 diskdrake XFdrake g_auto_install
REP4PMS     = /usr/bin/perl-install
ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
STAGE2      = $(ROOTDEST)/Mandrake/base/mdkinst_stage2
BASE        = $(ROOTDEST)/Mandrake/base
DESTREP4PMS = $(DEST)$(REP4PMS)
PERL        = perl
LOCALFILES  = pnp_serial
LOCALFILES2 = extract_archive
DIRS        = c Newt po pci_probing resize_fat
EXCLUDE     = $(LOCALFILES) boot.img keymaps consolefonts install
CFLAGS	    = -Wall
override CFLAGS  += -pipe

.PHONY: all $(DIRS) install clean stage2 full_stage2 verify_c 

all: TAGS $(DIRS)

TAGS: $(PMS)
	etags -o - $^ | ./perl2etags > $@

clean:
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf auto ../diskdrake*
	find . -name "*~" -o -name ".#*" -o -name "TAGS" -o -name "*.old" | xargs rm -f

tar: clean
	cd .. ; tar cfy perl-install.tar.bz2 $(EXCLUDE:%=--exclude %) perl-install

tar-diskdrake: clean pci_probing
	cd .. ; rm -rf diskdrake ; cp -af perl-install diskdrake

	l=`./perl2fcalls -uses -excludec -excluderesize_fat::c_rewritten diskdrake | sort | uniq | grep -v "^resize_fat::" | sed -e 's/::/\//' -e 's/^/diskdrake\//' -e 's/$$/.pm/'` ; \
	cd .. ; tar cfz diskdrake.tgz --exclude CVS $(patsubst %,diskdrake/%,c c.pm resize_fat po diskdrake*) $$l

tar-XFdrake: clean
	cd .. ; rm -rf XFdrake ; cp -af perl-install XFdrake

	l=`./perl2fcalls -uses -excludec -excludepci_probing::ids XFdrake | sort | uniq | sed -e 's/::/\//' -e 's/^/XFdrake\//' -e 's/$$/.pm/'` ; \
	cd .. ; tar cfz XFdrake.tgz --exclude CVS $(patsubst %,XFdrake/%,c MonitorsDB po pci_probing XFdrake*) $$l

$(DIRS):
	install -d auto
	$(MAKE) -C $@

test_pms: verify_c
	./perl2fcalls -excludec -excluderesize_fat::c_rewritten install2
	for i in install2 install_steps_*.pm; do perl -cw -I. $$i; done

verify_c:
	./verify_c $(PMS)

install_pms: $(DIRS)
	for i in `perl -ne 's/sub (\w+?)_? {.*/$$1/ and print' commands.pm`; do ln -sf commands $(DEST)/usr/bin/$$i; done

	install -d $(DESTREP4PMS)
	for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -ne 'print' $$i > $(DESTREP4PMS)/$$i; \
		perl -pe 's/#-.*//; $$_ = "\n" if (/^=head/ .. /^=cut/) || /use (diagnostics)/' $$i > $(DESTREP4PMS)/$$i; \
	done
#		perl -pe 's/#-.*//; $$_ = "\n" if (/^=head/ .. /^=cut/) || /use (diagnostics|vars|strict)/' $$i > $(DESTREP4PMS)/$$i; \

	cp *.rc $(DESTREP4PMS)
	install -d $(DESTREP4PMS)/po
	cp -f po/*.po* $(DESTREP4PMS)/po ||:
	chmod a+x $(DESTREP4PMS)/install2
	chmod a+x $(DESTREP4PMS)/commands
	chmod a+x $(DESTREP4PMS)/XFdrake
	chmod a+x $(DESTREP4PMS)/g_auto_install

get_needed_files: $(DIRS)
#	export PERL_INSTALL_TEST=1 ; strace -f -e trace=file -o '| grep -v "(No such file or directory)" | sed -e "s/[^\"]*\"//" -e "s/\".*//" | grep "^/" | grep -v -e "^/tmp" -e "^/home" -e "^/proc" -e "^/var" -e "^/dev" -e "^/etc" -e "^/usr/lib/rpm" > /tmp/list ' $(PERL) -d install2 < /dev/null
	cp -f list /tmp/list
	find auto -follow -name "*.so" >> /tmp/list

	for i in $(LOCALFILES) `cat /tmp/list` ; do \
		ldd $$i 2>/dev/null | grep -v "not a dynamic" | sed -e 's/.*=> //' -e 's/ .*//' | uniq | sort >> /tmp/list; \
	done

	install -d $(DEST)/etc
	install -d $(DEST)/lib
	install -d $(DEST)/bin
	install -d $(DEST)/usr/bin
	install -d $(DEST)/usr/lib
	install -d $(DEST)/usr/share
	install -d $(DEST)/usr/share/gtk
	install -d $(DEST)/usr/share/xmodmap
	install -d $(ROOTDEST)/Mandrake/base
	install -s $(LOCALFILES) $(DEST)/usr/bin
	cp -f $(LOCALFILES2) $(DEST)/usr/bin

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

	mv -f $(DEST)/bin/* $(DEST)/sbin/* $(DEST)/usr/bin
	cd $(DEST)/usr/bin ; mv insmod insmod_
	rmdir $(DEST)/bin $(DEST)/sbin

	perl -ane 'symlink "$$F[1]", "$(DEST)/usr/bin/$$F[0]"' aliases

	tar xfy locales.tar.bz2 -C $(DEST)
#	DEST=$(DEST) perl -I. -MForMakefile -e 'locale()'
#	DEST=$(DEST) perl -I. -MForMakefile -e 'xmodmap()'

	cp -a keymaps $(DEST)/usr/share
	cp -a consolefonts $(DEST)/usr/share
	cp ifcfg-ppp.* chat-ppp.* kppprc.in modparm.lst MonitorsDB $(DEST)/usr/share
	cp logo-mandrake.xpm $(DEST)/usr/share
	cp -a themes $(DEST)/usr/share/gtk
	cp compss compssUsers compssList $(ROOTDEST)/Mandrake/base

	if [ -f "../modules/modules.cz2" ]; then \
		cp -f ../modules/modules.cz2 $(DEST)/lib/; \
		cp -f ../modules/modules.cz2.pl $(DEST)/lib/; \
	else \
		cp -f ../modules/modules.cpio.bz2 $(DEST)/lib/; \
		install -d $(DEST)/lib/modules; \
		cp -f ../modules/pristine/* $(DEST)/lib/modules ||: ; \
	fi

#	echo -e "#!/bin/sh\n\nexec '/usr/bin/sh'" > $(DEST)/usr/bin/runinstall2
#	chmod a+x $(DEST)/usr/bin/runinstall2

	tar xyC $(DEST) -f ../install/install1_pcmcia.tar.bz2 ./etc/pcmcia

full_stage2:
	sudo rm -rf $(DEST)
	mkdir -p $(DEST)
	$(MAKE) get_needed_files 
	$(MAKE) stage2

stage2:
	$(MAKE) install_pms
	../make_mdkinst_stage2 $(DEST)  $(ROOTDEST)/Mandrake/base/mdkinst_stage2
