PMSFILES = $(shell find .. -name "*.pm" | grep -v "^../po" | grep -v "^../c/")
PMSCFILES = $(PMSFILES:%=%_.c)
POFILES = $(shell ls *.po)

all: $(POFILES)

clean:
	rm -f empty.po $(POFILES:%=%t) $(PMSCFILES)

$(POFILES): panoramix.pot
	cp -f $@ $@t
	msgmerge $@t $< > $@
	rm $@t

panoramix.pot: $(PMSFILES)
	$(MAKE) $(PMSCFILES);
	xgettext -F -n --keyword=_ --keyword=__ -o panoramix.pot $(PMSCFILES)
	rm $(PMSCFILES)

$(PMSCFILES): %_.c: %
	perl -pe 's|^(__?\()| $$1|; s|#(.*)|/*\1*\/|; s|$$|\\n\\|' $< > $@

