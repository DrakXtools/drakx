ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe serial_probe aewm-drakx
BASE        = $(ROOTDEST)/Mandrake/base
CFLAGS      = -Wall

.PHONY: clean install $(DIRS)

all: $(DIRS) xhost+ rpcinfo-flushed install

$(DIRS):
	make -C $@

install:
	@install -d $(ROOTDEST)/misc/auto
	@install make_mdkinst_stage2 $(ROOTDEST)/misc
	@cd /usr/bin ; install packdrake $(ROOTDEST)/misc || { echo "packdrake is missing"; exit 1; }
	@cd /usr/bin ; install gendistrib rpm2header $(ROOTDEST)/misc || { echo "install rpmtools first!" ; exit 1; }
	@eval `perl -V:installvendorarch`; cd $$installvendorarch ; cp -rf packdrake.pm URPM* $(ROOTDEST)/misc || { echo "install rpmtools and perl-URPM first!" ; exit 1; }
	@eval `perl -V:installvendorarch`; cd $$installvendorarch/auto ; cp -rf URPM $(ROOTDEST)/misc/auto || { echo "install perl-URPM first!" ; exit 1; }
	@mkdir -p $(DEST)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/lib -lX11 -o $@

ddcprobe/ddcxinfos:
	$(MAKE) -C ddcprobe ddcxinfos

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ rpcinfo-flushed ddcprobe/ddcxinfos */*.o
