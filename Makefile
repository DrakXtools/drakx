include Makefile.config


DIRS = tools images perl-install/install rescue

.PHONY: dirs install

install: dirs rescue install_only

dirs:
	@for n in $(DIRS); do $(MAKE) -C $$n all || exit 1 ; done

install_only:
	make -C images install DESTDIR=$(DESTDIR)
	make -C tools install $(DESTDIR)=$(DESTDIR)
	make -C perl-install/install install DESTDIR=$(DESTDIR)
	make -C rescue install DESTDIR=$(DESTDIR)
	make -C advertising install DESTDIR=$(DESTDIR)

fetchsubmodules:
	git submodule update --recursive --checkout

clean:
#	force taking new rpms from repository
	rm -rf images/RPMS
	for i in $(DIRS); do make -C $$i clean; done
	find . -name "*~" -o -name ".#*" | xargs rm -f

check:
	$(MAKE) -C perl-install check
