ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe serial_probe
BASE        = $(ROOTDEST)/Mandrake/base
CFLAGS      = -Wall

.PHONY: clean install $(DIRS)

all: $(BASE)/depslist $(BASE)/filelist $(BASE)/compss $(DIRS) xhost+ install

$(DIRS):
	make -C $@

install:
	install make_mdkinst_stage2 gencompss $(ROOTDEST)/misc
	cd /usr/bin ; install packdrake $(ROOTDEST)/misc || { echo "packdrake is missing"; exit 1; }
	cd /usr/bin ; install gendepslist2 rpm2header genhdlist_cz2 $(ROOTDEST)/misc || { echo "install rpmtools first!" ; exit 1; }
	mkdir -p $(DEST)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/lib -lX11 -o $@

ddcprobe/ddcxinfos:
	$(MAKE) -C ddcprobe ddcxinfos

$(BASE)/compss $(BASE)/depslist.ordered: $(BASE)/hdlists $(BASE)/hdlist.cz
	genbasefiles $(BASE) `cat $< | perl -pe 's|^(\S*).*|'$(BASE)'/$$1|' `

$(BASE)/filelist: $(RPMS)
#	genfilelist $(ROOTDEST)/Mandrake/RPMS* >$@

$(BASE)/hdlist.cz: $(BASE)/hdlists $(RPMS)
	genhdlists --noclean --distrib $(ROOTDEST)

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ ddcprobe/ddcxinfos */*.o
