include ../../../Makefile.config

PRODUCT = dwd
DESTDIR = $(EXTRA_INSTALL_DEST)/advertising

install:
	rm -rf $(DESTDIR)
	install -d $(DESTDIR)
	install -m755 `cat list-$(PRODUCT) | sed 's/png$$/pl/'` $(DESTDIR)
	install -m644 `cat list-$(PRODUCT)` $(DESTDIR)
	install -m644 list-$(PRODUCT) $(DESTDIR)/list
