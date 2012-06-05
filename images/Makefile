include ../Makefile.config

VERSION=1.56
PRODUCT=$(FAMILY)-images
KERNELS=$(shell rpm -qf /lib/modules/3.*)
ROOTDEST = /usr/$(LIB)/$(FAMILY)
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
