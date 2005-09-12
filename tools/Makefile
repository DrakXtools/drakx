include ../Makefile.config

RPMS        = $(wildcard $(MAIN_RPMS_DIR)/*.rpm)
DIRS	    = serial_probe
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
	@install -d $(MISC_DEST)/auto $(MISC_DEST)/Distribconf
	@install mdkinst_stage2_tool drakx-in-chroot $(MISC_DEST)
	cp -rf `perldoc -l packdrake` $(MISC_DEST) || { echo "install packdrake first!" ; exit 1; }
	cp -rf `perldoc -l Packdrakeng` $(MISC_DEST) || { echo "install packdrake first!" ; exit 1; }
	cp -rf `perldoc -l Distribconf` $(MISC_DEST) || { echo "install rpmtools first!" ; exit 1; }
	cp -rf `perldoc -l Distribconf::Build` $(MISC_DEST)/Distribconf || { echo "install rpmtools first!" ; exit 1; }
	@cp -rf `perldoc -l URPM | sed s/URPM.pm//`URPM* $(MISC_DEST) || { echo "install perl-URPM first!" ; exit 1; }
	@cp -rf `perldoc -l URPM | sed s/URPM.pm//`auto/URPM $(MISC_DEST)/auto || { echo "install perl-URPM first!" ; exit 1; }
	@cd /usr/bin ; install packdrake $(MISC_DEST) || { echo "packdrake is missing"; exit 1; }
	@cd /usr/bin ; install gendistrib rpm2header $(MISC_DEST) || { echo "install rpmtools first!" ; exit 1; }
	@mkdir -p $(STAGE2_LIVE)/usr/bin

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/$(LIB_NAME) -lX11 -o $@

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ rpcinfo-flushed */*.o
