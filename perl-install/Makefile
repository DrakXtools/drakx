include Makefile.config

.PHONY: all $(DIRS) install clean stage2 full_stage2 verify_c 

all: TAGS $(DIRS)

TAGS: $(PMS)
	etags -o - $^ | ./perl2etags > $@

clean:
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf auto ../drakxtools.tar.bz2
	find . -name "*~" -o -name ".#*" -o -name "TAGS" -o -name "*.old" | xargs rm -f

tar-drakxtools: clean
	$(MAKE) -C ../tools clean
	cd .. ; rm -rf drakxtools ; cp -af perl-install drakxtools ; cp -af tools/ddcprobe tools/serial_probe drakxtools
	cd ../drakxtools ; rm -rf install* pkgs.pm ftp.pm t.pm */CVS ; mv Makefile.drakxtools Makefile ; mv -f standalone/* .
	cd .. ; tar cfj drakxtools.tar.bz2 --exclude CVS $(patsubst %,drakxtools/%,Makefile Makefile.config Newt c ddcprobe serial_probe share/po sbus_probing resize_fat share/diskdrake.rc share/wizard.rc $(STANDALONEPMS) icons *.pm)
	cd .. ; rm -rf drakxtools

$(DIRS):
	install -d auto
	$(MAKE) -C $@

test_pms: verify_c
	for i in install2 standalone/keyboarddrake standalone/XFdrake standalone/drakboot; do ./perl2fcalls -excludec -excluderesize_fat::c_rewritten $$i; done
	for i in install2 install_steps_*.pm; do perl -cw -I. $$i; done

verify_c:
	./verify_c $(PMS)

install_pms: $(DIRS)
	for i in `perl -ne 's/sub (\w+?)_? {.*/$$1/ and print' commands.pm` sync; do ln -sf commands $(DEST)/usr/bin/$$i; done

	install -d $(DESTREP4PMS)
	for i in $(PMS); do \
		dest=$(DESTREP4PMS)/`dirname $$i`; \
		install -d $$dest; \
		perl -ne 'print' $$i > $(DESTREP4PMS)/$$i; \
		perl -pe 's/#[-+].*//; $$_ = "\n" if (/^=head/ .. /^=cut/) || /use (diagnostics|vars|strict)/' $$i > $(DESTREP4PMS)/$$i; \
	done
#		perl -pe 's/#-.*//; $$_ = "\n" if (/^=head/ .. /^=cut/) || /use (diagnostics)/' $$i > $(DESTREP4PMS)/$$i; \

	cp share/*.rc $(DESTREP4PMS)
	install -d $(DESTREP4PMS)/po
	cp -f share/po/*.po* $(DESTREP4PMS)/po ||:
	chmod a+x $(DESTREP4PMS)/install2
	chmod a+x $(DESTREP4PMS)/commands
	chmod a+x $(DESTREP4PMS)/standalone/*
	chmod a+x $(DESTREP4PMS)/g_auto_install
	chmod a+x $(DESTREP4PMS)/live_install*

get_needed_files: $(DIRS)
#	export PERL_INSTALL_TEST=1 ; strace -f -e trace=file -o '| grep -v "(No such file or directory)" | sed -e "s/[^\"]*\"//" -e "s/\".*//" | grep "^/" | grep -v -e "^/tmp" -e "^/home" -e "^/proc" -e "^/var" -e "^/dev" -e "^/etc" -e "^/usr/lib/rpm" > /tmp/list ' $(PERL) -d install2 < /dev/null
	perl -pe "s/ARCH/$(ARCH)/g" share/list > /tmp/list

#	perl -pi -e 's/00503/6.0/g' /tmp/list
#	see also /usr/lib/perl5/5.00503/ARCH-linux/Data/Dumper.pm

	cat `../tools/specific_arch share/list` >> /tmp/list
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
	install -s ../kernel/cardmgr/cardmgr $(DEST)/usr/bin
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

	mv -f $(DEST)/bin/* $(DEST)/sbin/* $(DEST)/usr/bin
	cd $(DEST)/usr/bin ; mv insmod insmod_
	rmdir $(DEST)/bin $(DEST)/sbin

	perl -ane 'symlink "$$F[1]", "$(DEST)/usr/bin/$$F[0]"' share/aliases

	for i in fonts keyboards locales gconv keymaps; do tar xfj `../tools/specific_arch share/$$i.tar.bz2` -C $(DEST); done

	grep ChangeLog CVS/Entries > $(DEST)/usr/share/VERSION

	cd share ; cp -a modparm.lst $(DEST)/usr/share
	cd share ; cp -a consolefonts $(DEST)/usr/share
	cd share ; cp template.in/*.in $(DEST)/usr/share
	cd share ; cp *.png $(DEST)/usr/share
	cd share ; cp -a themes $(DEST)/usr/share/gtk
	cd share ; cp compssUsers compssUsers.desktop rpmsrate $(ROOTDEST)/Mandrake/base

	if [ -f ../modules/modules.cz* ]; then \
		cp -f ../modules/modules.cz* $(DEST)/lib/; \
		if [ -f ../modules64/modules.cz* ]; then \
			cp -f ../modules64/modules.cz* $(DEST)/lib/modules64.cz2; \
		fi \
	else \
		cp -f ../modules/modules.cpio.bz2 $(DEST)/lib/; \
		install -d $(DEST)/lib/modules; \
		cp -f ../modules/pristine/* $(DEST)/lib/modules ||: ; \
	fi

#	echo -e '#!/bin/sh\n\nexec "/usr/bin/sh"' > $(DEST)/usr/bin/runinstall2
#	chmod a+x $(DEST)/usr/bin/runinstall2

ifeq (i386,$(ARCH))
	cp -a /etc/pcmcia $(DEST)/etc
	patch -p0 -d $(DEST)/etc < ../install/pcmcia_config.patch
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
