include ../Makefile.config

all: rescue_stage2.bz2

install: rescue_stage2.bz2
	cp -f $< $(STAGE2_DEST)

rescue_stage2.bz2: kernel_read_part list list.$(ARCH) drvinst guessmounts lsparts rescue-doc make_rescue_img
	./make_rescue_img

clean: 
	rm -f rescue_stage2.bz2 kernel_read_part
