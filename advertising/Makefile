VERSION = 0.2
PRODUCT = drakx-installer-advertising

THEME = pwp
DESTDIR = $(ROOTDEST)/install/extra/advertising

install:
	rm -rf $(DESTDIR)
	install -d $(DESTDIR)
	install -m644 `cat list-$(THEME)` $(DESTDIR)
	install -m644 list-$(THEME) $(DESTDIR)/list

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	svn export -q . $(PRODUCT)-$(VERSION)
	tar cfj $(PRODUCT)-$(VERSION).tar.bz2 $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

clean:
	find . -name "*~" -o -name ".#*" | xargs rm -f
