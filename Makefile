ROOTDEST = /export

DIRS = tools kernel mdk-stage1 perl-install


ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))

ifeq (i386,$(ARCH))
    BOOT_IMG = cdrom.img hd.img network.img usb.img blank.img pcmcia.img other.img
endif
ifeq (sparc,$(ARCH))
    BOOT_IMG  = cdrom.img   hd.img   network.img   live.img   tftp.img   tftprd.img
    BOOT_IMG += cdrom64.img hd64.img network64.img live64.img tftp64.img tftprd64.img 
endif
ifeq (ppc,$(ARCH))
    BOOT_IMG = all.img
endif
ifeq (ia64,$(ARCH))
    BOOT_IMG = all.img
endif

FBOOT_IMG = $(BOOT_IMG:%=images/%)
FBOOT_RDZ = $(FBOOT_IMG:%.img=%.rdz) images/all.rdz

.PHONY: dirs install

install: dirs images rescue install_only

dirs:
	@for n in $(DIRS); do $(MAKE) -C $$n all || exit 1 ; done

images: $(FBOOT_IMG)

$(FBOOT_RDZ): kernel/all.modules
	./make_boot_img $@ `basename $(@:%.rdz=%)`

$(FBOOT_IMG): %.img: %.rdz
	./make_boot_img $@ `basename $(@:%.img=%)`

tar: clean
	rpm -qa > needed_rpms.lst
	cd .. ; tar cfj gi.tar.bz2 gi
	rm needed_rpms.lst

install_only:
	for i in images misc Mandrake Mandrake/base Mandrake/share; do install -d $(ROOTDEST)/$$i ; done
    ifneq (ppc,$(ARCH))
	for i in $(FBOOT_IMG); do cp -f $${i}* $(ROOTDEST)/images; done
    endif
    ifeq (alpha,$(ARCH))
	for i in $(FBOOT_RDZ); do cp -f $${i}* $(ROOTDEST)/boot; done
	cp -f vmlinux.gz $(ROOTDEST)/boot/instboot.gz
	make -C tools/$(ARCH)/cd install ROOTDEST=$(ROOTDEST)
    endif
	cd $(ROOTDEST)/images; rm -rf alternatives 
	if [ `ls $(ROOTDEST)/images/*.img-* 2>/dev/null | wc -l` -gt 0 ]; then	\
	  cd $(ROOTDEST)/images; mkdir alternatives; cd alternatives; mv ../*.img-* .; md5sum *.img-* > MD5SUM; \
	fi
	cd $(ROOTDEST)/images; md5sum *.img* > MD5SUM

    ifeq (i386,$(ARCH))
	rm -rf $(ROOTDEST)/isolinux
	cp -af isolinux $(ROOTDEST)
    endif

	install live_update $(ROOTDEST)/live_update
	make -C perl-install full_stage2
	make -C perl-install/share/advertising install

clean:
	rm -rf images all.modules all.modules64
	for i in $(DIRS) rescue; do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

check:
	@badrights=`find $(ROOTDEST)/Mandrake/mdkinst | perl -lne 'print if !((stat)[2] & 4)'`; [ -z "$$badrights" ] || { echo "bad rights for files vvvvvvvvvvvvvvvvvvvvvvvvvv" ; echo "$$badrights" ; echo "bad rights for files ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^" ; exit 1; }
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
	function upload() { rsync -qSavz --verbose --exclude '*~' -e ssh --delete $(ROOTDEST)/$$1/$$2 mandrake@ken:/c/cooker/$$1; } ;\
	upload Mandrake/mdkinst '' ;\
	upload Mandrake/base compssUsers* ;\
	upload Mandrake/base rpmsrate ;\
	upload Mandrake/base *_stage2.bz2 ;\
	upload Mandrake/share/advertising '' ;\
	upload misc gendistrib ;\
	upload misc make_mdkinst_stage2 ;\
	upload misc packdrake ;\
	upload misc packdrake.pm ;\
	upload misc rpmtools.pm ;\
	upload misc auto ;\
	upload '' live_update ;\
	upload images MD5SUM ;\
	upload images *.img* ;\
	upload images/alternatives '' ;\
	upload isolinux '' ;\
	echo
