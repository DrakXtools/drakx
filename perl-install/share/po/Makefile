include ../../Makefile.config

PMSFILES = $(wildcard $(PMS:%=../../%))
PMSCFILES = $(PMSFILES:%=%_.c)
POFILES = $(shell ls *.po)

all: $(POFILES)

clean:
	rm -f empty.po messages $(POFILES:%=%t) $(PMSCFILES)

verif:
	perl -ne '/^\s*#/ or $$i += my @l = /\b__?\(/g; END { print "$$i\n" }' $(PMSFILES)
	perl -ne '$$i += my @l = /\.c:/g; END { print "$$i\n" }' DrakX.pot

$(POFILES): DrakX.pot
	cp -f $@ $@t
	msgmerge $@t $< > $@
	rm $@t

DrakX.pot: $(PMSFILES)
	$(MAKE) $(PMSCFILES);
	xgettext -F -n --add-comments='-PO' --keyword=_ --keyword=__ -o $@ $(PMSCFILES)
	rm $(PMSCFILES)
	./i18n_compssUsers 2>/dev/null >> $@

$(PMSCFILES): %_.c: %
	perl -pe 's|^(__?\()| $$1|; s,(^|[^\$$])#([^+].*),\1/*\2*\/,; s|$$|\\n\\|' $< > $@

#	for i in *.po; do echo -n "$i "; msgfmt -v $i 2>&1; done | perl -e 'print map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, (split)[1] ] } <>'
