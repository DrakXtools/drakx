ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))

RELEASE_BOOT_IMG = cdrom.img hd.img network.img usb.img
ifeq (i386,$(ARCH))
RELEASE_BOOT_IMG += blank.img pcmcia.img other.img
endif
ifeq (sparc,$(ARCH))
BOOT_IMG = live.img tftp.img tftprd.img live64.img tftp64.img tftprd64.img
RELEASE_BOOT_IMG += hd64.img cdrom64.img network64.img
endif
ifeq (ppc,$(ARCH))
BOOT_IMG = 
RELEASE_BOOT_IMG = all.img
endif
ifeq (ia64,$(ARCH))
BOOT_IMG =
RELEASE_BOOT_IMG = all.img
endif
BOOT_IMG += $(RELEASE_BOOT_IMG)

FRELEASE_BOOT_IMG = $(BOOT_IMG:%=images/%)
FBOOT_IMG = $(BOOT_IMG:%=images/%)
FBOOT_RDZ = $(FBOOT_IMG:%.img=%.rdz) images/all.rdz

BINS = mdk-stage1/init mdk-stage1/stage1-full mdk-stage1/stage1-cdrom mdk-stage1/stage1-network mdk-stage1/stage1-usb
ifeq (ppc,$(ARCH))
BINS = mdk-stage1/init mdk-stage1/stage1-full 
endif
DIRS = tools mdk-stage1 perl-install

ROOTDEST = /export
UPLOAD_DEST_ = ~/cooker
UPLOAD_DEST = $(UPLOAD_DEST_)/cooker
UPLOAD_DEST_CONTRIB = $(UPLOAD_DEST_)/contrib
UPLOAD_SPARC_DEST = /mnt/BIG/distrib/sparc

.PHONY: dirs perl-install $(FLOPPY_IMG) install

install: all.modules build rescue
	for i in images misc Mandrake Mandrake/base; do install -d $(ROOTDEST)/$$i ; done
ifneq (ppc,$(ARCH))
	for i in $(FRELEASE_BOOT_IMG); do cp -f $${i}* $(ROOTDEST)/images; done
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

build: $(FBOOT_RDZ) $(FBOOT_IMG)

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || $(MAKE) -C $$n all ;\
	done

rescue: all.modules
	make -C $@

$(FBOOT_RDZ): dirs all.modules
	./make_boot_img $@ `basename $(@:%.rdz=%)`

$(FBOOT_IMG): %.img: %.rdz
	./make_boot_img $@ `basename $(@:%.img=%)`

tar: clean
	rpm -qa > needed_rpms.lst
	cd .. ; tar cfj gi.tar.bz2 gi
	rm needed_rpms.lst

perl-install:
	make -C perl-install all

mdk-stage1/mar/mar:
	make -C mdk-stage1/mar

all.modules: mdk-stage1/mar/mar perl-install/auto/c/stuff/stuff.so update_kernel perl-install/modules.pm
	`./tools/specific_arch ./update_kernel`

perl-install/auto/c/stuff/stuff.so: perl-install


$(FBOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

clean:
	rm -rf $(BINS) images all.modules all.modules64 install_pcmcia_modules
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

	function upload() { rsync -qSavz --verbose --exclude '*~' -e ssh --delete $(ROOTDEST)/$$1/$$2 mandrake@kenobi:/c/cooker/$$1; } ;\
	upload Mandrake/mdkinst '' ;\
	upload Mandrake/base compssUsers ;\
	upload Mandrake/base rpmsrate ;\
	upload Mandrake/base *_stage2.bz2 ;\
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

upload_sparc:
	touch /tmp/mdkinst_done
	cp -a $(ROOTDEST)/images/* $(UPLOAD_SPARC_DEST)/images ; true
	cp -a $(ROOTDEST)/boot/* $(UPLOAD_SPARC_DEST)/boot; true
	cp -a $(ROOTDEST)/misc/* $(UPLOAD_SPARC_DEST)/misc; true
	rm -rf $(UPLOAD_SPARC_DEST)/Mandrake/mdkinst
	cp -a $(ROOTDEST)/Mandrake/mdkinst $(UPLOAD_SPARC_DEST)/Mandrake/mdkinst; true
	( cd $(ROOTDEST)/Mandrake/base; cp mdkinst_stage2.bz2 rescue_stage2.bz2 compss compssList compssUsers compssUsers.desktop $(UPLOAD_SPARC_DEST)/Mandrake/base ); true
	rm -f /tmp/mdkinst_done

# mkisofs -r -J -b images/cdrom.img -c images/boot.cat /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
# as distrib: mv ~/oxygen/oxygen/images ~/tmp/r
# as mandrake: ~distrib/bin/mkisofs -r -b images/cdrom.img -c images/boot.cat -o /home/ftp/linux-mandrake/pub/mirror/oxyiso/oxygen-3.iso ~distrib/tmp/r ~distrib/oxygen/oxygen
# as mandrake: remove old iso in /home/ftp/linux-mandrake/pub/mirror/oxyiso
# as mandrake: cd /home/ftp/linux-mandrake/pub/mirror/oxyiso ; md5sum *.iso > md5sum
# as distrib: mv ~/tmp/r/images ~/oxygen/oxygen
