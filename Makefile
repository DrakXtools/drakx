BOOT_IMG = hd.img cdrom.img network.img network_ks.img pcmcia.img pcmcia_ks.img
BINS = install/install install/full-install install/local-install install/installinit/init
DIRS = tools install install/installinit perl-install lnx4win
ROOTDEST = /export


.PHONY: dirs $(FLOPPY_IMG)

install: build
	for i in images misc Mandrake Mandrake/base; do install -d $(ROOTDEST)/$$i ; done
	cp -f $(BOOT_IMG) $(ROOTDEST)/images ; rm $(ROOTDEST)/images/*_ks.img
	make -C perl-install full_stage2

build: $(BOOT_IMG)

dirs:
	for i in $(DIRS); do make -C $$i; done

$(BOOT_IMG): dirs modules
	./make_boot_img $@ $(@:%.img=%)

tar: clean
	cd .. ; tar cfy gi.tar.bz2 gi

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

#	lftp -c "open -u devel mandrakesoft.com; cd ~/cooker/cooker/images ; mput $(ROOTDEST)/images/*.img"
	lftp -c "open -u devel mandrakesoft.com; cd ~/tmp ; put $(ROOTDEST)/Mandrake/mdkinst.tgz ; put /tmp/mdkinst_done ; cd ~/cooker/cooker/Mandrake/base ; put $(ROOTDEST)/Mandrake/base/mdkinst_stage2.gz ; put ~/gi/perl-install/compss ; put ~/gi/perl-install/compssList ; put ~/gi/perl-install/compssUsers ; cd ~/cooker/cooker/misc ; put ~/gi/tools/make_mdkinst_stage2 "
#	lftp -c "open -u devel mandrakesoft.com; cd ~/cooker/contrib/others/src ; put ../gi.tar.bz2"
	rm -f $(ROOTDEST)/Mandrake/mdkinst.tgz
	rm -f /tmp/mdkinst_done

# mkisofs -r -J -b images/cdrom.img -c images/boot.cat /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
# as distrib: mv ~/oxygen/oxygen/images ~/tmp/r
# as mandrake: mkisofs -r -b images/cdrom.img -c images/boot.cat -o /home/ftp/linux-mandrake/pub/mirror/oxyiso/oxygen-3.iso ~distrib/tmp/r ~distrib/oxygen/oxygen
# as mandrake: remove old iso in /home/ftp/linux-mandrake/pub/mirror/oxyiso
# as mandrake: cd /home/ftp/linux-mandrake/pub/mirror/oxyiso ; md5sum *.iso > md5sum
# as distrib: mv ~/tmp/r/images ~/oxygen/oxygen
