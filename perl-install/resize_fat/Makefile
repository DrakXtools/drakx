PRODUCT = libresize
TARSOURCE = $(PRODUCT).tar.bz2

.PHONY: clean tar

clean:
	rm -f *~ TAGS $(TARSOURCE)

tar: clean
	cp -f ../common.pm .
	cd .. ; tar cfy $(TARSOURCE) $(PRODUCT) ; mv $(TARSOURCE) $(PRODUCT)
	rm -f common.pm
