.PHONY: clean

MAKEIT = $(MAKE) -f Makefile_c LD_RUN_PATH=

stuff: %: %.xs
	test -e Makefile_c || perl Makefile.PL
	$(MAKEIT) || $(MAKEIT)
	rm -f ../auto/c ; ln -s ../c/blib/arch/auto ../auto/c

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ *.o stuff.xs probe.c

stuff.xs: %: %.pl
	rm -f $@
	perl $< > $@
	chmod a-w $@
