ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))

RELEASE_BOOT_IMG = hd.img cdrom.img network.img
ifeq (i386,$(ARCH))
BOOT_IMG = pcmcia_ks.img network_ks.img
RELEASE_BOOT_IMG += pcmcia.img
endif
ifeq (sparc,$(ARCH))
BOOT_IMG = live.img tftp.img tftprd.img live64.img tftp64.img tftprd64.img
RELEASE_BOOT_IMG += hd64.img cdrom64.img network64.img
endif
BOOT_IMG += $(RELEASE_BOOT_IMG)

BOOT_RDZ = $(BOOT_IMG:%.img=%.rdz)
BINS = install/install install/full-install install/local-install install/installinit/init
DIRS = tools install install/installinit perl-install
ifeq (i386,$(ARCH))
#DIRS += lnx4win
endif

ROOTDEST = /export
UPLOAD_DEST_ = ~/cooker
UPLOAD_DEST = $(UPLOAD_DEST_)/cooker
UPLOAD_DEST_CONTRIB = $(UPLOAD_DEST_)/contrib
UPLOAD_SPARC_DEST = /mnt/BIG/distrib/sparc

AUTOBOOT = $(ROOTDEST)/dosutils/autoboot/mdkinst


.PHONY: dirs $(FLOPPY_IMG) install network_ks.rdz pcmcia_ks.rdz

install: build autoboot rescue
	for i in images misc Mandrake Mandrake/base; do install -d $(ROOTDEST)/$$i ; done
	cp -f $(RELEASE_BOOT_IMG) $(ROOTDEST)/images
ifeq (alpha,$(ARCH))
	cp -f $(BOOT_RDZ) $(ROOTDEST)/boot
	cp -f vmlinux.gz $(ROOTDEST)/boot/instboot.gz
#	 sudo install -d /mnt/loop
#	 for i in $(ROOTDEST)/images/disks/*; do \
#	   sudo mount $$i /mnt/loop -o loop ;\
#	   sudo cp -f vmlinux.gz /mnt/loop ;\
#	   sudo umount $$i ;\
#	 done
	make -C tools/$(ARCH)/cd install ROOTDEST=$(ROOTDEST)
endif
	make -C perl-install full_stage2

build: $(BOOT_IMG)

autoboot:
ifeq (i386,$(ARCH))
	install -d $(ROOTDEST)/lnx4win
	cp -f vmlinuz $(ROOTDEST)/lnx4win
	cp -f cdrom.rdz $(ROOTDEST)/lnx4win/initrd.gz
	/usr/sbin/rdev -v $(ROOTDEST)/lnx4win/vmlinuz 788

	install -d $(AUTOBOOT)
	cp -f vmlinuz $(AUTOBOOT)
	cp -f hd.rdz $(AUTOBOOT)/initrd.hd
	cp -f cdrom.rdz $(AUTOBOOT)/initrd.cd
	cp -f pcmcia.rdz $(AUTOBOOT)/initrd.pc
	cp -f network.rdz $(AUTOBOOT)/initrd.nt
	/usr/sbin/rdev -v $(AUTOBOOT)/vmlinuz 788
endif

dirs:
	for i in $(DIRS); do make -C $$i; done

rescue: modules
	make -C $@

network_ks.rdz pcmcia_ks.rdz: %_ks.rdz: %.rdz

network.rdz pcmcia.rdz hd.rdz cdrom.rdz live.rdz tftp.rdz tftprd.rdz network64.rdz hd64.rdz cdrom64.rdz live64.rdz tftp64.rdz tftprd64.rdz blank.rdz: dirs modules
	./make_boot_img $@ $(@:%.rdz=%)

$(BOOT_IMG): %.img: %.rdz
	./make_boot_img $@ $(@:%.img=%)

tar: clean
	rpm -qa > needed_rpms.lst
	cd .. ; tar cfy gi.tar.bz2 gi
	rm needed_rpms.lst

modules: kernel/lib/modules
	`./tools/specific_arch ./update_kernel`

$(BOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

clean:
	rm -rf $(BOOT_IMG) $(BOOT_RDZ) $(BINS) modules modules64 install_pcmcia_modules vmlinu* System*.map
	rm -rf install/*/sbin/install install/*/sbin/init
	for i in $(DIRS) rescue; do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

upload: clean install
	function upload() { rsync -qSavz --verbose --exclude '*~' -e ssh --delete $(ROOTDEST)/$$1/$$2 mandrake@kenobi:/c/cooker/$$1; } ;\
	upload Mandrake/mdkinst '' ;\
	upload Mandrake/base {compss*,mdkinst_stage2.gz,rescue_stage2.gz} ;\
	upload dosutils/autoboot/mdkinst {initrd.*,vmlinuz} ;\
	upload lnx4win {initrd.gz,vmlinuz} ;\
	for i in $(RELEASE_BOOT_IMG); do upload images $$i; done ;\
	echo 

upload_sparc:
	touch /tmp/mdkinst_done
	cp -a $(ROOTDEST)/images/* $(UPLOAD_SPARC_DEST)/images ; true
	cp -a $(ROOTDEST)/boot/* $(UPLOAD_SPARC_DEST)/boot; true
	cp -a $(ROOTDEST)/misc/* $(UPLOAD_SPARC_DEST)/misc; true
	rm -rf $(UPLOAD_SPARC_DEST)/Mandrake/mdkinst
	cp -a $(ROOTDEST)/Mandrake/mdkinst $(UPLOAD_SPARC_DEST)/Mandrake/mdkinst; true
	( cd $(ROOTDEST)/Mandrake/base; cp mdkinst_stage2.gz rescue_stage2.gz compss compssList compssUsers $(UPLOAD_SPARC_DEST)/Mandrake/base ); true
	rm -f /tmp/mdkinst_done

# mkisofs -r -J -b images/cdrom.img -c images/boot.cat /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
# as distrib: mv ~/oxygen/oxygen/images ~/tmp/r
# as mandrake: ~distrib/bin/mkisofs -r -b images/cdrom.img -c images/boot.cat -o /home/ftp/linux-mandrake/pub/mirror/oxyiso/oxygen-3.iso ~distrib/tmp/r ~distrib/oxygen/oxygen
# as mandrake: remove old iso in /home/ftp/linux-mandrake/pub/mirror/oxyiso
# as mandrake: cd /home/ftp/linux-mandrake/pub/mirror/oxyiso ; md5sum *.iso > md5sum
# as distrib: mv ~/tmp/r/images ~/oxygen/oxygen
