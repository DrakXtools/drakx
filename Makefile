BOOT_IMG = gi_hd.img gi_cdrom.img gi_network.img gi_network_ks.img gi_pcmcia.img
BINS = install/install install/local-install install/installinit/init



.PHONY: $(BOOT_IMG) $(FLOPPY_IMG) $(BINS) update_kernel

all: $(BOOT_IMG)
	mkdir /export/images 2>/dev/null ; true
	cp -f $(BOOT_IMG) /export/images

clean:
	rm -rf $(BOOT_IMG) $(BINS) modules vmlinuz

$(BOOT_IMG): $(BINS)
	if [ ! -e modules ]; then $(MAKE) update_kernel; fi
	#./make_boot_img $@ $(@:gi_%.img=%)
	./make_boot_img $@ $(@:gi_%.img=%)

$(BINS):
	$(MAKE) -C `dirname $@`


update_kernel:
	./update_kernel

$(BOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

# mkisofs -R -b images/gi_cdrom.img -c images/.catalog /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -
