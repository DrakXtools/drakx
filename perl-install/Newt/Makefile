.PHONY: clean

Newt: %: %.xs
	test -e Makefile_c || perl Makefile.PL
	$(MAKE) -f Makefile_c LD_RUN_PATH= || $(MAKE) -f Makefile_c LD_RUN_PATH=
	rm -f ../auto/Newt ; ln -s ../Newt/blib/arch/auto/Newt ../auto

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ *.o
