ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe pnp_serial
BASE        = $(ROOTDEST)/Mandrake/base

.PHONY: clean install $(DIRS)

all: $(BASE)/depslist $(BASE)/hdlist $(DIRS) install 

$(DIRS):
	make -C $@

install:
	$(MAKE) gendepslist rpm2header
	install make_mdkinst_stage2 gendepslist rpm2header genhdlist $(ROOTDEST)/misc

gendepslist: %: %.cc 
	$(CXX) -I/usr/include/rpm $(CFLAGS) $< -lrpm -ldb1 -lz -o $@

rpm2header: %: %.c
	$(CC) -I/usr/include/rpm $(CFLAGS) $< -lrpm -ldb1 -lz -o $@

ddcprobe/ddcxinfos:
	$(MAKE) -C ddcprobe ddcxinfos

$(BASE)/depslist: $(BASE)/hdlist gendepslist
	./gendepslist -h $@ $<

$(BASE)/hdlist: $(RPMS)
	$(MAKE) install
	./genhdlist $(ROOTDEST)

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ gendepslist rpm2header ddcprobe/ddcxinfos */*.o
