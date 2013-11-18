include ../Makefile.config

CC          = gcc
CFLAGS      = -Wall -Os

.PHONY: clean install $(DIRS)

all: $(DIRS) rpcinfo-flushed

$(DIRS):
	make -C $@

install:
	install -d $(DESTDIR)$(ROOTDEST)/misc
	install mdkinst_stage2_tool drakx-in-chroot $(DESTDIR)$(ROOTDEST)/misc

rpcinfo-flushed: %: %.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< -ltirpc -o $@

xhost+: %: %.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< -lX11 -o $@

clean: 
	for i in $(DIRS); do $(MAKE) -C $$i clean; done
	rm -rf *~ xhost+ rpcinfo-flushed */*.o
