.PHONY: clean

main: %: %.xs
	test -e Makefile_c || perl Makefile.PL
	$(MAKE) -f Makefile_c LD_RUN_PATH= || $(MAKE) -f Makefile_c LD_RUN_PATH=
	rm -f ../auto/xf86misc ; ln -s ../xf86misc/blib/arch/auto ../auto/xf86misc

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ *.o
