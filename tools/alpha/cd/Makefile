install:
	cp -f README README.milo $(ROOTDEST)
	install -d $(ROOTDEST)/etc
	cp -f aboot.cnf $(ROOTDEST)/etc

	install -d $(ROOTDEST)/boot
	cp -a up1000 $(ROOTDEST)/boot
	mv -f $(ROOTDEST)/boot/up1000/apb.* $(ROOTDEST)
