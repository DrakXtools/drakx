ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe serial_probe
BASE        = $(ROOTDEST)/Mandrake/base
CFLAGS      = -Wall

.PHONY: clean install $(DIRS)

all: $(BASE)/depslist.ordered $(BASE)/compss $(DIRS) xhost+ install

$(DIRS):
	make -C $@

install:
	install make_mdkinst_stage2 $(ROOTDEST)/misc
	cd /usr/bin ; install packdrake $(ROOTDEST)/misc || { echo "packdrake is missing"; exit 1; }
	cd /usr/bin ; install genbasefiles rpm2header genhdlist_cz2 $(ROOTDEST)/misc || { echo "install rpmtools first!" ; exit 1; }
	mkdir -p $(DEST)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/lib -lX11 -o $@

ddcprobe/ddcxinfos:
	$(MAKE) -C ddcprobe ddcxinfos

$(BASE)/compss $(BASE)/depslist.ordered: $(BASE)/hdlists $(BASE)/hdlist.cz
	gendistrib --nohdlists --distrib $(ROOTDEST)

$(BASE)/hdlist.cz: $(BASE)/hdlists $(RPMS)
	gendistrib --noclean --nobasefiles --distrib $(ROOTDEST)

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ ddcprobe/ddcxinfos */*.o
