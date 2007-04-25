include Makefile.config

ROOTDEST = /export
STAGE2_DEST = $(ROOTDEST)/install/stage2

DIRS = tools images perl-install/install rescue

.PHONY: dirs install

install: dirs rescue install_only

dirs:
	@for n in $(DIRS); do $(MAKE) -C $$n all || exit 1 ; done

install_only:
	make -C images install ROOTDEST=$(ROOTDEST)
	make -C tools install ROOTDEST=$(ROOTDEST)
	make -C perl-install/install install ROOTDEST=$(ROOTDEST)
	make -C rescue install STAGE2_DEST=$(STAGE2_DEST)
	make -C advertising install ROOTDEST=$(ROOTDEST)

	LC_ALL=C svn info ChangeLog  | egrep '^Revision|^Last Changed Date' > $(STAGE2_DEST)/VERSION

clean:
#	force taking new rpms from repository
	rm -rf images/RPMS
	for i in $(DIRS); do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

check:
	$(MAKE) -C perl-install check
