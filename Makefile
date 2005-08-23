include Makefile.config

DIRS = tools kernel mdk-stage1 perl-install rescue

.PHONY: dirs install isolinux-graphic.bmp.parameters isolinux-graphic-simple.bmp.parameters images

install: dirs images rescue install_only

dirs:
	@for n in $(DIRS); do $(MAKE) -C $$n all || exit 1 ; done

images:
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img

tar: clean
	rpm -qa > needed_rpms.lst
	cd .. ; tar cfj gi.tar.bz2 gi
	rm needed_rpms.lst

install_only:
	install -d $(MISC_DEST) $(EXTRA_INSTALL_DEST) $(IMAGES_DEST) $(MEDIA_INFO_DEST)
    ifneq (ppc,$(ARCH))
	cp -f images/* $(IMAGES_DEST)
	rm -rf $(IMAGES_DEST)/alternatives 
	if [ `ls $(IMAGES_DEST)/*.img-* 2>/dev/null | wc -l` -gt 0 ]; then	\
	  cd $(IMAGES_DEST); mkdir alternatives; cd alternatives; mv ../*.img-* .; md5sum *.img-* > MD5SUM; \
	fi
	cd $(IMAGES_DEST); md5sum *.{img,iso}* > MD5SUM
    endif
    ifeq (alpha,$(ARCH))
	cp -f images/* $(ROOTDEST)/boot
	cp -f vmlinux.gz $(ROOTDEST)/boot/instboot.gz
	make -C tools/$(ARCH)/cd install ROOTDEST=$(ROOTDEST)
    endif

    ifeq (i386,$(ARCH))
	rm -rf $(ROOTDEST)/isolinux
	if [ -d isolinux/xbox ]; then mv -f isolinux/xbox/{linuxboot.cfg,default.xbe} $(ROOTDEST); fi
	cp -af isolinux $(ROOTDEST)
    endif

    ifeq (x86_64,$(ARCH))
	rm -rf $(ROOTDEST)/isolinux
	cp -af isolinux $(ROOTDEST)
    endif

	make -C perl-install full_stage2
	make -C perl-install/share/advertising install
	make -C rescue install

clean:
	rm -rf images
#	force taking new rpms from repository
	rm -rf kernel/RPMS
	for i in $(DIRS); do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

check:
	@badrights=`find $(STAGE2_LIVE) | perl -lne 'print if !((stat)[2] & 4)'`; [ -z "$$badrights" ] || { echo "bad rights for files vvvvvvvvvvvvvvvvvvvvvvvvvv" ; echo "$$badrights" ; echo "bad rights for files ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" ; exit 1; }
	@missing_kb=`find -name "Entries" | xargs perl -F/ -alne 'print $$ARGV =~ m|(.*)/CVS|, "/$$F[1]" if $$F[1] =~ /\.(png|gif|bmp|xcf|gz|bz2|tar|rdz|so|a|o|mar|img|exe)$$/ && $$F[4] ne "-kb"'` ; [ -z "$$missing_kb" ] || { echo "missing -kb in CVS for files vvvvvvvvvvvvvvvvvvvvvvvvvv" ; echo "$$missing_kb" ; echo "missing -kb in CVS for files ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" ; exit 1; }
	$(MAKE) -C perl-install check

upload: 
	$(MAKE) clean

#	# done before make install to increment ChangeLog version
	tools/addchangelog.pl tools/cvslog2changelog.pl | tools/mailchangelog.pl &

	$(MAKE) install
	$(MAKE) check
	$(MAKE) upload_only

upload_only:
	function upload() { rel=`echo $$1 | sed 's!$(ROOTDEST)/!!'`; rsync -qSavz --verbose --exclude '*~' -e ssh --delete $$1/$$2 mandrake@ken:/c/cooker/$$rel; } ;\
	upload $(MEDIA_INFO_DEST) 'compssUsers.pl*' ;\
	upload $(MEDIA_INFO_DEST) rpmsrate ;\
	upload $(STAGE2_DEST) '*.clp' ;\
	upload $(STAGE2_DEST) mdkinst.kernels ;\
	upload $(STAGE2_DEST) VERSION ;\
	upload $(EXTRA_INSTALL_DEST)/advertising '' ;\
	upload $(MISC_DEST) gendistrib ;\
	upload $(MISC_DEST) mdkinst_stage2_tool ;\
	upload $(MISC_DEST) packdrake ;\
	upload $(MISC_DEST) packdrake.pm ;\
	upload $(MISC_DEST) auto ;\
	upload $(IMAGES_DEST) MD5SUM ;\
	upload $(IMAGES_DEST) '*.img*' ;\
	upload $(IMAGES_DEST) '*.iso*' ;\
	upload $(IMAGES_DEST)/alternatives '' ;\
	upload $(ROOTDEST)/isolinux '' ;\
	if [ "$(ARCH)" = "i386" ]; then\
	  upload $(ROOTDEST) linuxboot.cfg;\
	  upload $(ROOTDEST) default.xbe;\
	fi;\
	echo


isolinux-graphic.bmp.parameters: isolinux-graphic.bmp isolinux
	perl -I perl-install perl-install/standalone/draksplash2 --isolinux --kernel isolinux/alt0/vmlinuz --initrd isolinux/alt0/all.rdz $<

isolinux-graphic-simple.bmp.parameters: isolinux-graphic-simple.bmp isolinux
	perl -I perl-install perl-install/standalone/draksplash2 --isolinux --size 1400 $<
