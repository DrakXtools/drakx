ROOTDEST    = /export
DEST        = $(ROOTDEST)/Mandrake/mdkinst
RPMS        = $(wildcard $(ROOTDEST)/Mandrake/RPMS/*.rpm)
DIRS	    = ddcprobe serial_probe
BASE        = $(ROOTDEST)/Mandrake/base
CFLAGS      = -Wall

ARCH := $(shell arch | egrep "(x86_64|sparc64|s390x)")
ifneq ("x$(ARCH)", "x")
LIB_NAME = lib64
else
LIB_NAME = lib
endif

.PHONY: clean install $(DIRS)

all: $(DIRS) xhost+ rpcinfo-flushed install

$(DIRS):
	make -C $@

install:
	@install -d $(ROOTDEST)/misc/auto
	@install make_mdkinst_stage2 $(ROOTDEST)/misc
	@cp -rf `perl -Mpackdrake -le 'print $$INC{"packdrake.pm"}'` $(ROOTDEST)/misc || { echo "install rpmtools first!" ; exit 1; }
	@cp -rf `perl -MURPM -le 'print $$INC{"URPM.pm"}' | sed s/URPM.pm//`URPM* $(ROOTDEST)/misc || { echo "install perl-URPM first!" ; exit 1; }
	@cp -rf `perl -MURPM -le 'print $$INC{"URPM.pm"}' | sed s/URPM.pm//`auto/URPM $(ROOTDEST)/misc/auto || { echo "install perl-URPM first!" ; exit 1; }
	@cd /usr/bin ; install packdrake $(ROOTDEST)/misc || { echo "packdrake is missing"; exit 1; }
	@cd /usr/bin ; install gendistrib rpm2header $(ROOTDEST)/misc || { echo "install rpmtools first!" ; exit 1; }
	@mkdir -p $(DEST)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/$(LIB_NAME) -lX11 -o $@

ddcprobe/ddcxinfos:
	$(MAKE) -C ddcprobe ddcxinfos

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ rpcinfo-flushed ddcprobe/ddcxinfos */*.o
