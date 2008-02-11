include ../Makefile.config

VERSION=1.27
PRODUCT=drakx-installer-images
KERNELS=$(shell rpm -qf /lib/modules/2.*)

IMAGES_DEST = $(ROOTDEST)/install/images

all: images

images: all.kernels
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_boot_img
	rm -rf images/alternatives 
	if [ `ls images/*.img-* 2>/dev/null | wc -l` -gt 0 ]; then	\
	  mkdir images/alternatives; cd images/alternatives; mv ../*.img-* .; md5sum *.img-* > MD5SUM; \
	fi
	cd images ; md5sum *.{img,iso}* > MD5SUM

all.kernels: update_kernel ../kernel/list_modules.pm
	./update_kernel $(KERNELS)

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	mkdir -p $(PRODUCT)-$(VERSION)
	svn export -q . $(PRODUCT)-$(VERSION)/images
	svn export -q ../kernel $(PRODUCT)-$(VERSION)/kernel
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfj $(PRODUCT)-$(VERSION).tar.bz2 $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

clean:
	rm -rf images isolinux all.kernels modules.description
	find . -name "*~" -o -name ".#*" | xargs rm -f

install:
	install -d $(IMAGES_DEST)
	rm -rf $(IMAGES_DEST)/alternatives 
	cp -r images/* $(IMAGES_DEST)
    ifneq (,$(findstring $(ARCH), i386 x86_64))
	rm -rf $(ROOTDEST)/isolinux
	cp -af isolinux $(ROOTDEST)
    endif
