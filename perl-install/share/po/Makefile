PMSFILES = $(shell find .. -name "*.pm" | grep -v "^../po")
POFILES = $(wildcard *.po)
FROMPOFILES = $(POFILES:%.po=%.pm)

all: $(FROMPOFILES)

clean:
	rm -f $(FROMPOFILES)

$(FROMPOFILES): %.pm: %.po
	./po2perl < $< > $@

%.po: $(PMSFILES)
	touch $@
	for i in $(PMSFILES); do \
		sed -e 's/#\(.*\)/\/*\1*\//' -e 's/$$/\\n\\/' < $$i > $${i}c; \
		xgettext -j -F -Lc -n --omit-header --keyword=_ --keyword=__ -o $@ $${i}c; \
		rm $${i}c; \
	done

FORCE: