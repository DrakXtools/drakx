include ../Makefile.config

all: rescue.clp

install: rescue.clp
	cp -f $< $(STAGE2_DEST)

rescue.clp: list list.$(ARCH) drvinst guessmounts lsparts rescue-doc make_rescue_img
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_rescue_img

clean: 
	rm -f rescue.clp kernel_read_part
