ROOTDEST = /export

install: rescue_stage2.bz2
	cp -f $< $(ROOTDEST)/Mandrake/base

rescue_stage2.bz2: kernel_read_part list
	./make_rescue_img

clean: 
	rm -f rescue_stage2.bz2 kernel_read_part
