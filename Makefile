ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))

RELEASE_BOOT_IMG = cdrom.img hd.img hdreiser.img network.img 
ifeq (i386,$(ARCH))
RELEASE_BOOT_IMG += all.img blank.img other.img pcmcia.img
endif
ifeq (sparc,$(ARCH))
BOOT_IMG = live.img tftp.img tftprd.img live64.img tftp64.img tftprd64.img
RELEASE_BOOT_IMG += hd64.img cdrom64.img network64.img
endif
BOOT_IMG += $(RELEASE_BOOT_IMG)

BOOT_RDZ = $(BOOT_IMG:%.img=%.rdz)
BINS = mdk-stage1/init mdk-stage1/stage1-full mdk-stage1/stage1-cdrom mdk-stage1/stage1-network
DIRS = tools #mdk-stage1

ROOTDEST = /export
UPLOAD_DEST_ = ~/cooker
UPLOAD_DEST = $(UPLOAD_DEST_)/cooker
UPLOAD_DEST_CONTRIB = $(UPLOAD_DEST_)/contrib
UPLOAD_SPARC_DEST = /mnt/BIG/distrib/sparc

.PHONY: dirs $(FLOPPY_IMG) install

install: #rescue
	for i in images misc Mandrake Mandrake/base; do install -d $(ROOTDEST)/$$i ; done
#	cp -f $(RELEASE_BOOT_IMG) $(ROOTDEST)/images
ifeq (alpha,$(ARCH))
	cp -f $(BOOT_RDZ) $(ROOTDEST)/boot
	cp -f vmlinux.gz $(ROOTDEST)/boot/instboot.gz
	make -C tools/$(ARCH)/cd install ROOTDEST=$(ROOTDEST)
endif
	install live_update $(ROOTDEST)/live_update
	make -C perl-install full_stage2

build: $(BOOT_IMG)

autoboot:
ifeq (i386,$(ARCH))
	install -d $(ROOTDEST)/boot
#	cp -f vmlinuz {hd,cdrom,pcmcia,network,all,other}.rdz $(ROOTDEST)/boot
	cp -f vmlinuz {hd,hdreiser,cdrom,network,all,other}.rdz $(ROOTDEST)/boot
	/usr/sbin/rdev -v $(ROOTDEST)/boot/vmlinuz 788
endif

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done

rescue: modules
	make -C $@

network_ks.rdz pcmcia_ks.rdz: %_ks.rdz: %.rdz

$(BOOT_RDZ): dirs modules
	./make_boot_img $@ $(@:%.rdz=%)

$(BOOT_IMG): %.img: %.rdz
	./make_boot_img $@ $(@:%.img=%)

tar: clean
	rpm -qa > needed_rpms.lst
	cd .. ; tar cfy gi.tar.bz2 gi
	rm needed_rpms.lst

modules:
	`./tools/specific_arch ./update_kernel`

$(BOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

clean:
	rm -rf $(BOOT_IMG) $(BOOT_RDZ) $(BINS) modules modules64 install_pcmcia_modules vmlinu* System*.map
	for i in $(DIRS) rescue; do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

upload: install #clean
	function upload() { rsync -qSavz --verbose --exclude '*~' -e ssh --delete $(ROOTDEST)/$$1/$$2 mandrake@kenobi:/c/cooker/$$1; } ;\
	upload Mandrake/mdkinst '' ;\
	upload Mandrake/base compss* ;\
	upload Mandrake/base rpmsrate ;\
	upload Mandrake/base *_stage2.gz ;\
	upload boot '' ;\
	upload misc genbasefiles ;\
	upload misc genhdlist_cz2 ;\
	upload misc make_mdkinst_stage2 ;\
	upload misc packdrake ;\
	upload misc rpm2header ;\
	upload '' live_update ;\
	for i in $(RELEASE_BOOT_IMG); do upload images $$i; done ;\
	echo

	tools/addchangelog.pl perl-install tools/cvslog2changelog.pl | tools/mailchangelog.pl

upload_sparc:
	touch /tmp/mdkinst_done
	cp -a $(ROOTDEST)/images/* $(UPLOAD_SPARC_DEST)/images ; true
	cp -a $(ROOTDEST)/boot/* $(UPLOAD_SPARC_DEST)/boot; true
	cp -a $(ROOTDEST)/misc/* $(UPLOAD_SPARC_DEST)/misc; true
	rm -rf $(UPLOAD_SPARC_DEST)/Mandrake/mdkinst
	cp -a $(ROOTDEST)/Mandrake/mdkinst $(UPLOAD_SPARC_DEST)/Mandrake/mdkinst; true
	( cd $(ROOTDEST)/Mandrake/base; cp mdkinst_stage2.gz rescue_stage2.gz compss compssList compssUsers compssUsers.desktop $(UPLOAD_SPARC_DEST)/Mandrake/base ); true
	rm -f /tmp/mdkinst_done

# mkisofs -r -J -b images/cdrom.img -c images/boot.cat /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
# as distrib: mv ~/oxygen/oxygen/images ~/tmp/r
# as mandrake: ~distrib/bin/mkisofs -r -b images/cdrom.img -c images/boot.cat -o /home/ftp/linux-mandrake/pub/mirror/oxyiso/oxygen-3.iso ~distrib/tmp/r ~distrib/oxygen/oxygen
# as mandrake: remove old iso in /home/ftp/linux-mandrake/pub/mirror/oxyiso
# as mandrake: cd /home/ftp/linux-mandrake/pub/mirror/oxyiso ; md5sum *.iso > md5sum
# as distrib: mv ~/tmp/r/images ~/oxygen/oxygen
