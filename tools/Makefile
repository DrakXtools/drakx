ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe pnp_serial
BASE        = $(ROOTDEST)/Mandrake/base
CFLAGS      = -Wall

.PHONY: clean install $(DIRS)

all: $(BASE)/depslist $(BASE)/hdlist $(DIRS) xhost+ install

$(DIRS):
	make -C $@

install:
	$(MAKE) gendepslist rpm2header
	install make_mdkinst_stage2 build_archive gendepslist rpm2header genhdlist $(ROOTDEST)/misc
	mkdir -p $(DEST)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/lib -lX11 -o $@

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
	rm -rf *~ gendepslist xhost+ rpm2header ddcprobe/ddcxinfos */*.o
