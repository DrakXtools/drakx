ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe pnp_serial
BASE        = $(ROOTDEST)/Mandrake/base
CFLAGS      = -Wall

.PHONY: clean install $(DIRS)

all: $(BASE)/depslist $(BASE)/filelist $(DIRS) xhost+ install

$(DIRS):
	make -C $@

install:
	install make_mdkinst_stage2 $(ROOTDEST)/misc
	cd /usr/bin ; install build_archive $(ROOTDEST)/misc || { echo "build_archive is missing"; exit 1; }
	cd /usr/bin ; install gendepslist2 rpm2header genhdlist_cz2 $(ROOTDEST)/misc || { echo "install rpmtools first!" ; exit 1; }
	mkdir -p $(DEST)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/lib -lX11 -o $@

ddcprobe/ddcxinfos:
	$(MAKE) -C ddcprobe ddcxinfos

$(BASE)/compss: $(BASE)/hdlists $(BASE)/hdlist.cz2
	./gencompss `cat $< | perl -pe 's|(.*)|'$(BASE)'/$$1|' ` > $@ 

$(BASE)/depslist: $(BASE)/hdlists $(BASE)/hdlist.cz2
	gendepslist2 -o $@ `cat $< | perl -pe 's|(.*)|'$(BASE)'/$$1|' `

$(BASE)/filelist: $(RPMS)
	genfilelist $(ROOTDEST)/Mandrake/RPMS* >$@

$(BASE)/hdlist.cz2:
	genhdlists --noclean --distrib $(ROOTDEST)

$(BASE)/hdlists: $(RPMS)
	genhdlists --noclean --distrib $(ROOTDEST)

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ ddcprobe/ddcxinfos */*.o
