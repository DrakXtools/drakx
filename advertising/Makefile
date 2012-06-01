VERSION = 2012.0
PRODUCT = drakx-installer-advertising

THEME = pwp
DESTDIR = $(ROOTDEST)/install/extra/advertising

install:
	rm -rf $(DESTDIR)
	install -d $(DESTDIR)
	install -m755 `cat list-$(THEME) | sed 's/png$$/pl/'` $(DESTDIR)
	install -m644 `cat list-$(THEME)` $(DESTDIR)
	install -m644 list-$(THEME) $(DESTDIR)/list

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	svn export -q . $(PRODUCT)-$(VERSION)
	tar cfJ $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

clean:
	find . -name "*~" -o -name ".#*" | xargs rm -f
