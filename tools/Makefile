ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
LOCALFILES  = ddcprobe/ddcxinfos
BASE        = $(ROOTDEST)/Mandrake/base

.PHONY: clean install

all: $(BASE)/depslist $(BASE)/hdlist install

install:
	$(MAKE) gendepslist rpm2header ddcprobe/ddcxinfos
	install make_mdkinst_stage2 gendepslist rpm2header genhdlist $(ROOTDEST)/misc
	install -s $(LOCALFILES) $(DEST)/usr/bin

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
	rm -rf *~ gendepslist rpm2header
