BOOT_IMG = hd.img cdrom.img network.img network_ks.img pcmcia.img pcmcia_ks.img
BOOT_RDZ = $(BOOT_IMG:%.img=%.rdz)
BINS = install/install install/full-install install/local-install install/installinit/init
DIRS = tools install install/installinit perl-install lnx4win
ROOTDEST = /export
UPLOAD_DEST_ = ~/oxygen
UPLOAD_DEST = $(UPLOAD_DEST_)/oxygen
UPLOAD_DEST_CONTRIB = $(UPLOAD_DEST_)/contrib

AUTOBOOT = $(ROOTDEST)/dosutils/autoboot/mdkinst

.PHONY: dirs $(FLOPPY_IMG)

install: build autoboot
	for i in images misc Mandrake Mandrake/base; do install -d $(ROOTDEST)/$$i ; done
	cp -f $(BOOT_IMG) $(ROOTDEST)/images ; rm $(ROOTDEST)/images/*_ks.img
	make -C perl-install full_stage2

build: $(BOOT_IMG)

autoboot:
	install -d $(AUTOBOOT)
	cp -f vmlinuz $(AUTOBOOT)
	cp -f hd.rdz $(AUTOBOOT)/initrd.hd
	cp -f cdrom.rdz $(AUTOBOOT)/initrd.cd
	cp -f pcmcia.rdz $(AUTOBOOT)/initrd.pc
	cp -f network.rdz $(AUTOBOOT)/initrd.nt

dirs:
	for i in $(DIRS); do make -C $$i; done

$(BOOT_RDZ): dirs modules
	./make_boot_img $@ $(@:%.rdz=%)

$(BOOT_IMG): %.img: %.rdz
	./make_boot_img $@ $(@:%.img=%)

tar: clean
	rpm -qa > needed_rpms.lst
	cd .. ; tar cfy gi.tar.bz2 gi
	rm needed_rpms.lst

modules: kernel/lib/modules
	./update_kernel

$(BOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

clean:
	rm -rf $(BOOT_IMG) $(BINS) modules install_pcmcia_modules vmlinuz System.map
	rm -rf install/*/sbin/install install/*/sbin/init
	for i in $(DIRS); do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

upload: tar install
	touch /tmp/mdkinst_done
	cd $(ROOTDEST)/Mandrake ; tar cfz mdkinst.tgz mdkinst

#	lftp -c "open -u distrib mandrakesoft.com; cd $(UPLOAD_DEST)/images ; mput $(ROOTDEST)/images/*.img"
	lftp -c "open -u distrib mandrakesoft.com; cd ~/tmp ; put $(ROOTDEST)/Mandrake/mdkinst.tgz ; put /tmp/mdkinst_done ; cd $(UPLOAD_DEST)/Mandrake/base ; lcd $(ROOTDEST)/Mandrake/base ; put mdkinst_stage2.gz compss compssList compssUsers ; cd $(UPLOAD_DEST)/misc ; lcd ~/gi/tools/ ; put make_mdkinst_stage2 build_archive genhdlist" #,gendepslist,rpm2header"
	lftp -c "open -u distrib mandrakesoft.com; cd $(UPLOAD_DEST)/dosutils/autoboot/mdkinst ; put $(ROOTDEST)/dosutils/autoboot/mdkinst/vmlinuz ; mput $(ROOTDEST)/dosutils/autoboot/mdkinst/initrd.*"
	lftp -c "open -u distrib mandrakesoft.com; cd $(UPLOAD_DEST)/lnx4win ; lcd $(ROOTDEST)/lnx4win ; put initrd.gz vmlinuz"
#	lftp -c "open -u distrib mandrakesoft.com; cd $(UPLOAD_DEST_CONTRIB)/others/src ; put ../gi.tar.bz2"
#	rm -f $(ROOTDEST)/Mandrake/mdkinst.tgz
	rm -f /tmp/mdkinst_done

# mkisofs -r -J -b images/cdrom.img -c images/boot.cat /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
# as distrib: mv ~/oxygen/oxygen/images ~/tmp/r
# as mandrake: ~distrib/bin/mkisofs -r -b images/cdrom.img -c images/boot.cat -o /home/ftp/linux-mandrake/pub/mirror/oxyiso/oxygen-3.iso ~distrib/tmp/r ~distrib/oxygen/oxygen
# as mandrake: remove old iso in /home/ftp/linux-mandrake/pub/mirror/oxyiso
# as mandrake: cd /home/ftp/linux-mandrake/pub/mirror/oxyiso ; md5sum *.iso > md5sum
# as distrib: mv ~/tmp/r/images ~/oxygen/oxygen
