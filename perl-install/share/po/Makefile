include ../../Makefile.config

PMSFILES = $(wildcard $(PMS:%=../../%))
PMSCFILES = $(PMSFILES:%=%_.c)
POFILES = $(shell ls *.po)
PERL2C = 

all: $(POFILES)

clean:
	rm -f empty.po tmp.* messages tmp.pot $(POFILES:%=%t) $(PMSCFILES)

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
	perl i18n_compssUsers 2>/dev/null >> $@

verif2: 
	perl -I ../.. -Mcommon -e 'foreach (qw($(PMSFILES))) { printf "package foo%d;\n", ++$$i; print common::cat_($$_) }' | perl -ne 'print if !/use (diagnostics|vars|strict)/' | OUTFILE=tmp.pm perl -I. -I../.. -Mb_dump_strings >/dev/null 2>/dev/null
	perl -pe 's|$$|\\n\\|' tmp.pm > tmp.pm_.c
	xgettext --keyword=_ -o tmp.po tmp.pm_.c 
	msgmerge DrakX.pot tmp.po > tmp.pot
	grep "^msgid" tmp.pot | sort > tmp.pot.light
	grep "^msgid" DrakX.pot | sort | diff - tmp.pot.light | grep "^>"

$(PMSCFILES): %_.c: %
	perl -pe 's|^(__?\()| $$1|; s,\Qs/#.*//,,; s|//|/""/|g; s,(^|[^\$$])#([^+].*),\1/*\2*/,; s|$$|\\n\\|' $< > $@

#	for i in *.po; do echo -n "$i "; msgfmt -v $i 2>&1; done | perl -e 'print map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, (split)[1] ] } <>'
