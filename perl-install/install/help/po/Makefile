NAME = DrakX-help
LOCALEDIR = ${prefix}/share/locale
PL_FILES = ../help.pm

MAIN_PO_FILES = ../../../share/po/libDrakX.pot ../../share/po/DrakX.pot

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

default: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

merge: $(NAME).pot
	for n in $(POFILES); do \
	  echo "Merging $$n"; \
	  msgmerge $$n $(NAME).pot > "$$n"t ; \
	  mv -f "$$n"t $$n ; \
	done

$(NAME).pot: $(PL_FILES)
	perl_checker -q --generate-pot .$@ $(PL_FILES)
	xgettext $(MAIN_PO_FILES:%=-x %) -o $@ .$@
	rm -f .$@

install: $(MOFILES)
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t)
