ROOTDEST    = /export
BASE        = $(ROOTDEST)/Mandrake/base

ALL = gendepslist rpm2header
.PHONY: clean install

install:
	$(MAKE) gendepslist rpm2header
	install make_mdkinst_stage2 gendepslist rpm2header genhdlist $(ROOTDEST)/misc

gendepslist: %: %.cc 
	$(CXX) -I/usr/include/rpm $(CFLAGS) $< -lrpm -ldb1 -lz -o $@

rpm2header: %: %.c
	$(CC) -I/usr/include/rpm $(CFLAGS) $< -lrpm -ldb1 -lz -o $@

$(BASE)/depslist: $(BASE)/hdlist gendepslist
	./gendepslist -h $@ $<

$(BASE)/hdlist: $(RPMS)
	$(MAKE) install
	./genhdlist $(ROOTDEST)

clean: 
	rm -rf *~ gendepslist rpm2header
