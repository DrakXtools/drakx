.PHONY: clean

c_rewritten: %: %.xs
	test -e Makefile_c || perl Makefile.PL
	$(MAKE) -f Makefile_c LD_RUN_PATH= || $(MAKE) -f Makefile_c LD_RUN_PATH=
	rm -f ../auto/resize_fat ; ln -s ../resize_fat/blib/arch/auto ../auto/resize_fat

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ *.o
