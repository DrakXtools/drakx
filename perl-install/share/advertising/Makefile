include ../../Makefile.config

PRODUCT = dwd

install:
	rm -rf $(ROOTDEST)/Mandrake/share/advertising
	install -d $(ROOTDEST)/Mandrake/share/advertising
	install -m755 $(PRODUCT)-*.pl $(ROOTDEST)/Mandrake/share/advertising
	install -m644 $(PRODUCT)-*.png $(ROOTDEST)/Mandrake/share/advertising
	install -m644 list* $(ROOTDEST)/Mandrake/share/advertising
