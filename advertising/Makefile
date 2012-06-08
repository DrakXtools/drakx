include ../Makefile.config

VERSION = 2012.0
PRODUCT = $(FAMILY)-advertising

THEME = pwp
ADVERTISING = $(ROOTDEST)/install/extra/advertising

install:
	install -d $(DESTDIR)$(ADVERTISING)
	install -m755 `cat list-$(THEME) | sed 's/png$$/pl/'` $(DESTDIR)$(ADVERTISING)
	install -m644 `cat list-$(THEME)` $(DESTDIR)$(ADVERTISING)
	install -m644 list-$(THEME) $(DESTDIR)/$(ADVERTISING)/list

dist:
dist-svn:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	mkdir -p $(PRODUCT)-$(VERSION)/
	svn export -q -rBASE . $(PRODUCT)-$(VERSION)/advertising
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	tar cfJ $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

clean:
	find . -name "*~" -o -name ".#*" | xargs rm -f
