include ../Makefile.config

VERSION=1.9
PRODUCT=drakx-installer-rescue

RESCUE = rescue.sqfs

all: $(RESCUE)

install: $(RESCUE)
	cp -f $< $(STAGE2_DEST)

$(RESCUE): list.xml drvinst guessmounts lsparts rescue-doc make_rescue_img
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_rescue_img

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	mkdir -p $(PRODUCT)-$(VERSION)/tools
	svn export -q -rBASE . $(PRODUCT)-$(VERSION)/rescue
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	cp ../tools/install-xml-file-list $(PRODUCT)-$(VERSION)/tools
	tar cfj $(PRODUCT)-$(VERSION).tar.bz2 $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

clean: 
	rm -f $(RESCUE) kernel_read_part
