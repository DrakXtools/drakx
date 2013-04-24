include ../Makefile.config

VERSION=2.0
PRODUCT=$(FAMILY)-images
KERNELS=$(shell rpm -qf /lib/modules/3.*)
IMAGES_DEST = $(ROOTDEST)/install/images
#COMPRESS = xz -v --check=crc32 -9e
ARCH=$(shell arch)
ifeq (x86_64, $(ARCH))
WORDSIZE = 64
else
WORSIZE=32
ARCH=i586
endif

all: images

images/:
	mkdir -p images

USE_LOCAL_STAGE1 = $(shell test -f ../mdk-stage1/stage1 && echo 1 || echo 0)

ifneq (0, $(USE_LOCAL_STAGE1))
STAGE1_BINS = ../mdk-stage1/dhcp-client ../mdk-stage1/probe-modules ../mdk-stage1/rescue-gui ../mdk-stage1/stage1 ../mdk-stage1/drvinst ../mdk-stage/lspcidrake
endif

images: images/hd_grub.img images/hd_grub.img images/boot.iso grub/$(ARCH)/install/images/all.cpio.xz grub/boot/alt0/$(WORDSIZE)/modules.cpio.xz grub/boot/firmware.cpio.xz

#../mdk-stage1/dhcp-client ../mdk-stage1/probe-modules ../mdk-stage1/rescue-gui ../mdk-stage1/stage1 ../mdk-stage1/drvinst ../mdk-stage1/lspcidrake:
$(STAGE1_BINS):
	make -C ../mdk-stage1 $(shell basename $@)

images/hd_grub.img:
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img.pl --compress "$(COMPRESS)" $@

grub/$(ARCH)/install/images/all.cpio.xz: list.xml guessmounts
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img $@

grub/boot/grub/grub.cfg: grub_data/grub.cfg grub_data/themes/moondrake/theme.txt grub_data/themes/moondrake/star_w.png grub_data/themes/moondrake/star_shade_w.png grub_data/themes/moondrake/tick.png make_boot_img all.kernels/.list
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img grub

images/boot.iso: grub/boot/grub/grub.cfg grub/boot/alt0/$(WORDSIZE)/modules.cpio.xz grub/$(ARCH)/install/images/all.cpio.xz grub/boot/firmware.cpio.xz
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img $@
	cd images; md5sum boot.iso > MD5SUM

grub/boot/alt0/$(WORDSIZE)/modules.cpio.xz: all.kernels/.list
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img $@

grub/boot/firmware.cpio.xz: grub/boot/alt0/$(WORDSIZE)/modules.cpio.xz
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img $@

all.kernels/.list: update_kernel ../kernel/list_modules.pm
	./update_kernel $(KERNELS)

dist: tar
tar:
	@rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@if [ -e "../.svn" ]; then \
		$(MAKE) dist-svn; \
	elif [ -e "../.git" ]; then \
		$(MAKE) dist-git; \
	else \
		echo "Unknown SCM (not SVN nor GIT)";\
		exit 1; \
	fi;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

dist-svn:
	mkdir -p $(PRODUCT)-$(VERSION) 
	svn export -q -rBASE . $(PRODUCT)-$(VERSION)/images
	svn export -q -rBASE ../kernel $(PRODUCT)-$(VERSION)/kernel
	svn export -q -rBASE ./tree $(PRODUCT)-$(VERSION)/tree
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfJ $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

dist-git:
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD images kernel Makefile.config | xz >images/$(PRODUCT)-$(VERSION).tar.xz;

clean:
	rm -rf images grub all.kernels modules.description
	find . -name "*~" -o -name ".#*" | xargs rm -f

install:
	install -d $(DESTDIR)$(IMAGES_DEST)
	rm -rf $(DESTDIR)$(IMAGES_DEST)/alternatives 
	cp -r images/* $(DESTDIR)$(IMAGES_DEST)
ifneq (,$(findstring $(ARCH), i386 x86_64))
	rm -rf $(DESTDIR)$(ROOTDEST)/grub
	cp -af grub $(DESTDIR)$(ROOTDEST)
endif
