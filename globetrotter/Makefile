PACKAGE=mandrake-globetrotter
PKGVERSION:=$(shell rpm -q --qf '%{VERSION}\n' --specfile $(PACKAGE).spec|head -n 1)
RELEASE:=$(shell rpm -q --qf '%{RELEASE}\n' --specfile $(PACKAGE).spec|head -n 1)
TAG := $(shell echo "V$(PKGVERSION)_$(RELEASE)" | tr -- '-.' '__')

DIRS=share/po
PREFIX  = 

SBINDIR = $(PREFIX)/usr/sbin
LIBDIR = $(PREFIX)/usr/lib
LIBDEST = $(LIBDIR)/libDrakX
DATADIR = $(PREFIX)/usr/share

LANG_FILES = pixmaps/langs
DISTFILES = hwprofile *.spec share/po/*.po share/po/Makefile share/po/i18n_compssUsers Makefile Makefile.config *.pm runstage2 $(LANG_FILES)

.PHONY: all install clean

all:
	rm -f share/po/DrakX.pot # force rebuild of po's
	make -C share/po mofiles


localcopy: clean
	cd .. ; rm -rf $(PACKAGE)-$(PKGVERSION) ; cp -af globetrotter $(PACKAGE)-$(PKGVERSION)
	# include pixmaps for language selector:
	mkdir ../$(PACKAGE)-$(PKGVERSION)/{pixmaps,share}
	cp -af ../perl-install/pixmaps/langs ../$(PACKAGE)-$(PKGVERSION)/pixmaps/langs
	# include drakx modules for first time wizard	:
	# cp -af ../perl-install/share/po ../$(PACKAGE)-$(PKGVERSION)/share/
	mkdir ../$(PACKAGE)-$(PKGVERSION)/share/po
	# cp -af ../perl-install/share/po/{fr.po,Makefile,i18n_compssUsers} ../$(PACKAGE)-$(PKGVERSION)/share/po
	cp -af ../perl-install/share/po/{*.po,Makefile,i18n_compssUsers} ../$(PACKAGE)-$(PKGVERSION)/share/po
	# enable fast build:
	perl -pi -e 's!^.*msgmerge.*\n!!' ../$(PACKAGE)-$(PKGVERSION)/share/po/Makefile
	cp -af ../perl-install/{help,pkgs,install*}.pm ../$(PACKAGE)-$(PKGVERSION)/
	echo 'ALLPMS  = *.pm' > ../$(PACKAGE)-$(PKGVERSION)/Makefile.config
	@make nuke_perl


install:
	install -d $(LIBDEST) $(DATADIR)/libDrakX/pixmaps/langs $(SBINDIR)
	install -m 644 *.pm $(LIBDEST)
	install -m 755 runstage2 $(SBINDIR)/mdkmove
	cp -f pixmaps/langs/lang-*.png $(DATADIR)/libDrakX/pixmaps/langs
	$(MAKE) -C share/po install PREFIX=$(PREFIX) SUDO= DATADIR=$(DATADIR) NAME=libDrakX2
#	%make -C po install SUDO= NAME=libDrakX2 LOCALEDIR=$(DEST)/usr/share/locale_special


rpm: localrpm
localrpm: localdist buildrpm

srpm: localsrpm
localsrpm: spec_test localdist buildsrpm

localdist: cleandist localcopy tar

cleandist:
	rm -rf ../$(PACKAGE)-$(PKGVERSION) ../$(PACKAGE)-$(PKGVERSION).tar.bz2

spec_test:
	@if [[ -z "$(PKGVERSION)"  ]]; then echo "unable to get spec version"; exit 3;fi
	@if [[ -z "$(RELEASE)"  ]]; then echo "unable to get spec release"; exit 2;fi

tar:
	cd ../$(PACKAGE)-$(PKGVERSION) && rm -rf  debug.log `find -name CVS`
	cd ..; tar cfj $(PACKAGE)-$(PKGVERSION).tar.bz2 $(patsubst %,$(PACKAGE)-$(PKGVERSION)/%,$(DISTFILES))
	#cd ..; rm -rf $(PACKAGE)-$(PKGVERSION)

buildrpm:
	rpm -ta ../$(PACKAGE)-$(PKGVERSION).tar.bz2

buildsrpm:
	rpm -ts --nodeps ../$(PACKAGE)-$(PKGVERSION).tar.bz2

# rules to build a distributable rpm

dist: cleandist export tar

export:
	cd ..; cvs export -d $(PACKAGE)-$(PKGVERSION) -r $(TAG) $(PACKAGE)
	cd ../$(PACKAGE)-$(PKGVERSION)
	cd ..;
	@make nuke_perl

nuke_perl:
	find ../$(PACKAGE)-$(PKGVERSION) -name '*.pm' | xargs perl -pi -e 's/\s*use\s+(diagnostics|strict|vars|warnings).*//g'

img:
	/usr/bin/lilo-bmp2mdk mode:0x103 progress:397,190,14,6,64+8 clear:600,800,64+8 pos:0,0 < BOOTGTROTTER-install-lilo-8bis.bmp > isolinux_boot.msg

.PHONY: log changelog

log: changelog

changelog:
	cvs2cl --accum -W 400 -U ../../soft/common/username
