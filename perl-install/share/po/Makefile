include ../../Makefile.config

PMSFILES = $(wildcard $(ALLPMS:%=../../%))
PMSCFILES = $(PMSFILES:%=%_.c)

# temporarly don't include ar.po,br.po,cy.po,ga.po,is.po,sl.po
# (too low translation percentage)
POFILES = $(shell ls *.po|grep -v '\(ar.po\|ga.po\|is.po\|sl.po\)')

MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

LOCALEDIR=$(DATADIR)/locale


all: help $(MOFILES)

help:
	@if [ ! -d doc ]; then \
		echo "Checking out doc stuff now ..."; \
		cvs co doc/manualB/{entities,manuals,modules}; \
		rm -rf doc/CVS; \
	else \
		echo "Updating doc stuff now ..."; \
		cvs update doc/manualB/{entities,manuals,modules}; \
	fi
	touch doc/manualB/entities/es/{button,icon,tab,text_field}_list.ent
	./help_xml2pm.pl

%.mo: %.po
	msgfmt -o $@ $<

$(PMSCFILES): %_.c: %
	./fake_c.pl $< > $@

$(POFILES): DrakX.pot
	perl -ne 'print unless /^# DO NOT BOTHER TO MODIFY HERE, SEE:|^#.*\Qdrakx-help.xml/ .. /^$$/' $@ > $@t
	if [ -e help-$@t ]; then perl -pe 's|^#~ ||' -i $@t ; msgmerge -C $@t help-$@t $< > $@; else msgmerge $@t $< > $@; fi
	rm $@t

DrakX.pot: $(PMSFILES)
	$(MAKE) $(PMSCFILES);
	xgettext -F -n --add-comments='-PO' --keyword=N --keyword=N_ -o $@ $(PMSCFILES)
	rm $(PMSCFILES)
	perl i18n_compssUsers 2>/dev/null >> $@

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf drakx-help.xml .memdump doc empty.po tmp.* messages tmp.pot *.mo $(POFILES:%=%t) $(PMSCFILES)

check:
	@grep -F '$$' DrakX.pot && { echo "bad translation strings (contains \$$) ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"; exit 1; } ||:

verif:
	perl -ne '/^\s*#/ or $$i += my @l = /\b__?\(/g; END { print "$$i\n" }' $(PMSFILES)
	perl -ne '$$i += my @l = /\.c:/g; END { print "$$i\n" }' DrakX.pot

verif2: 
#	perl -I ../.. -Mcommon -e 'foreach (qw($(PMSFILES))) { printf "package foo%d;\n", ++$$i; print common::cat_($$_) }' | perl -ne 'print if !/use (diagnostics|vars|strict)/' | OUTFILE=tmp.pm perl -I. -I../.. -Mb_dump_strings >/dev/null 2>/dev/null
	perl -pe 's|$$|\\n\\|' tmp.pm > tmp.pm_.c
	xgettext --keyword=_ -o tmp.po tmp.pm_.c 
	msgmerge DrakX.pot tmp.po > tmp.pot
	grep "^msgid" tmp.pot | sort > tmp.pot.light
	grep "^msgid" DrakX.pot | sort | diff - tmp.pot.light | grep "^>" || true


#	for i in *.po; do echo -n "$i "; msgfmt -v $i 2>&1; done | perl -e 'print map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, (split)[1] ] } <>'


%: %.sh
	#  fake built-in
