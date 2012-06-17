include ../Makefile.config

VERSION=1.58
PRODUCT=$(FAMILY)-images
KERNELS=$(shell rpm -qf /lib/modules/3.*)
IMAGES_DEST = $(ROOTDEST)/install/images
COMPRESS = xz -v --check=crc32 -9e

all: images

images/:
	mkdir -p images

images: all.kernels/.list images/all.img images/hd_grub.img images/boot.iso isolinux
	rm -rf images/alternatives 
	if [ `ls images/*.img-* 2>/dev/null | wc -l` -gt 0 ]; then	\
	  mkdir images/alternatives; cd images/alternatives; mv ../*.img-* .; md5sum *.img-* > MD5SUM; \
	fi
	cd images; md5sum *.{img,iso}* > MD5SUM

ifeq (1, $(USE_LOCAL_STAGE1))
STAGE1_BINS = ../mdk-stage1/dhcp-client ../mdk-stage1/init ../mdk-stage1/probe-modules ../mdk-stage1/rescue-gui ../mdk-stage1/stage1
endif

images/all.img images/boot.iso: all.kernels/.list images/$@ $(STAGE1_BINS)
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img --compress "$(COMPRESS)" $@

images/hd_grub.img:
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img --compress "$(COMPRESS)" $@

isolinux: all.kernels/.list
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img --compress "$(COMPRESS)" $@

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
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfJ $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

dist-git:
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD images kernel Makefile.config | xz >images/$(PRODUCT)-$(VERSION).tar.xz;

clean:
	rm -rf images isolinux all.kernels modules.description
	find . -name "*~" -o -name ".#*" | xargs rm -f

install:
	install -d $(DESTDIR)$(IMAGES_DEST)
	rm -rf $(DESTDIR)$(IMAGES_DEST)/alternatives 
	cp -r images/* $(DESTDIR)$(IMAGES_DEST)
ifneq (,$(findstring $(ARCH), i386 x86_64))
	rm -rf $(DESTDIR)$(ROOTDEST)/isolinux
	cp -af isolinux $(DESTDIR)$(ROOTDEST)
endif
