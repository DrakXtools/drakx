DIRS	    = serial_probe
CFLAGS      = -Wall

ARCH := $(shell arch | egrep "(x86_64|sparc64|s390x)")
ifneq ("x$(ARCH)", "x")
LIB_NAME = lib64
else
LIB_NAME = lib
endif

.PHONY: clean install $(DIRS)

all: $(DIRS) xhost+ rpcinfo-flushed

$(DIRS):
	make -C $@

install:
	install -d $(ROOTDEST)/misc
	install mdkinst_stage2_tool drakx-in-chroot $(ROOTDEST)/misc

xhost+: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/$(LIB_NAME) -lX11 -o $@

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ rpcinfo-flushed */*.o
