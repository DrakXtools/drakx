BOOT_IMG = gi_hd.img gi_cdrom.img gi_network.img gi_network_ks.img gi_pcmcia.img
BINS = install/install install/local-install install/installinit/init
DIRS = install install/installinit mouseconfig perl-install ddcprobe


.PHONY: $(DIRS) $(BOOT_IMG) $(FLOPPY_IMG) $(BINS) update_kernel

all: $(DIRS) $(BOOT_IMG)
	mkdir /export/images 2>/dev/null ; true
	cp -f $(BOOT_IMG) /export/images

clean:
	rm -rf $(BOOT_IMG) $(BINS) modules install_pcmcia_modules vmlinuz System.map
	rm -rf install/*/sbin/install install/*/sbin/init
	for i in $(DIRS); do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

$(DIRS):
	make -C $@

$(BOOT_IMG): $(BINS)
	if [ ! -e modules ]; then $(MAKE) update_kernel; fi
	./make_boot_img $@ $(@:gi_%.img=%)

$(BINS):
	$(MAKE) -C `dirname $@`

tar: clean
	cd .. ; tar cfy gi.tar.bz2 gi

update_kernel:
	cd install ; ln -sf ../kernel/cardmgr/* .
	./update_kernel

$(BOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

# mkisofs -R -b images/gi_cdrom.img -c images/.catalog /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
