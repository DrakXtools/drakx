PMSFILES = $(shell find .. -name "*.pm" | grep -v "^../po" | grep -v "^../c/")
PMSCFILES = $(PMSFILES:%=%_.c)
POFILES = $(shell ls *.po | grep -v empty.po)
FROMPOFILES = $(POFILES:%.po=%.pm)

all: $(FROMPOFILES)

clean:
	rm -f empty.po $(FROMPOFILES) $(POFILES:%=%t) $(PMSCFILES)

$(FROMPOFILES): %.pm: %.po
	./po2perl < $< > $@

$(POFILES): empty.po
	cp -f $@ $@t
	msgmerge $@t $< > $@
	rm $@t

empty.po: $(PMSFILES)
	$(MAKE) $(PMSCFILES);
	xgettext -F -n --omit-header --keyword=_ --keyword=__ -o empty.po $(PMSCFILES)
	rm $(PMSCFILES)

$(PMSCFILES): %_.c: %
	perl -pe 's|#(.*)|/*\1*\/|; s|$$|\\n\\|' $< > $@

