.PHONY: clean

stuff: %: %.xs
	test -e Makefile_c || C_RPM=1 perl Makefile.PL
	$(MAKE) -f Makefile_c
	rm ../auto/c ; ln -s ../c/blib/arch/auto ../auto/c

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ stuff.xs

stuff.xs: %: %.pm
	rm -f $@
	export C_RPM=1 ; perl $< > $@
	chmod a-w $@
