include ../../Makefile.config

PRODUCT = dwd

install:
	rm -rf $(ROOTDEST)/Mandrake/share/advertising
	install -d $(ROOTDEST)/Mandrake/share/advertising
	install -m755 `cat list-$(PRODUCT) | sed 's/png$$/pl/'` $(ROOTDEST)/Mandrake/share/advertising
	install -m644 `cat list-$(PRODUCT)` $(ROOTDEST)/Mandrake/share/advertising
	install -m644 list-$(PRODUCT) $(ROOTDEST)/Mandrake/share/advertising/list
