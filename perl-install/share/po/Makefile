PMSFILES = $(shell find .. -name "*.pm" | grep -v "^../po" | grep -v "^../c/")
PMSCFILES = $(PMSFILES:%=%_.c)
POFILES = $(shell ls *.po)
FROMPOFILES = $(POFILES:%.po=%.pm)

all: $(FROMPOFILES)

clean:
	rm -f empty.po $(FROMPOFILES) $(POFILES:%=%t) $(PMSCFILES)

$(FROMPOFILES): %.pm: %.po
	./po2perl $< > $@

$(POFILES): panoramix.pot
	cp -f $@ $@t
	msgmerge $@t $< > $@
	rm $@t

panoramix.pot: $(PMSFILES)
	$(MAKE) $(PMSCFILES);
	xgettext -F -n --keyword=_ --keyword=__ -o panoramix.pot $(PMSCFILES)
	rm $(PMSCFILES)

$(PMSCFILES): %_.c: %
	perl -pe 's|#(.*)|/*\1*\/|; s|$$|\\n\\|' $< > $@

