ROOTDEST = /export

install: rescue_stage2.gz
	cp -f $< $(ROOTDEST)/Mandrake/base

rescue_stage2.gz: kernel_read_part
	./make_rescue_img

clean: 
	rm -f rescue_stage2.gz kernel_read_part
