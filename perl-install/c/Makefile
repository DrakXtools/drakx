.PHONY: clean

C_RPM = 1
C_DRAKX = 1

stuff: %: %.xs
	test -e Makefile_c || C_RPM=$(C_RPM) C_DRAKX=$(C_DRAKX) perl Makefile.PL
	$(MAKE) -f Makefile_c LD_RUN_PATH= || $(MAKE) -f Makefile_c LD_RUN_PATH=
	rm -f ../auto/c ; ln -s ../c/blib/arch/auto ../auto/c

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ *.o stuff.xs pcmcia_probe.c

stuff.xs: %: %.pm
	rm -f $@
	C_RPM=$(C_RPM) C_DRAKX=$(C_DRAKX) perl $< > $@
	chmod a-w $@
