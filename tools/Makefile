ROOTDEST    = /export
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
BASE        = $(ROOTDEST)/Mandrake/base

.PHONY: clean install

all: $(BASE)/depslist $(BASE)/hdlist

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
