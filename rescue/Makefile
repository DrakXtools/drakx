ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))


ROOTDEST = /export

install: rescue_stage2.bz2
	cp -f $< $(ROOTDEST)/Mandrake/base

rescue_stage2.bz2: kernel_read_part list list.$(ARCH) drvinst guessmounts lsparts rescue-doc make_rescue_img
	./make_rescue_img

clean: 
	rm -f rescue_stage2.bz2 kernel_read_part
