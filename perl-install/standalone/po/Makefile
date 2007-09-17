include ../../Makefile.config

NAME = libDrakX-standalone
LOCALEDIR = $(DATADIR)/locale
PMSFILES = $(STANDALONEPMS_)
PMSFILES_HERE = $(wildcard $(PMSFILES:%=../%))
top_srcdir=..

MAIN_PO_FILES = ../../share/po/libDrakX.pot

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

$(NAME).pot: $(PMSFILES_HERE) POTFILES.in
	intltool-update --gettext-package desktopstuff --pot
	cd .. ; perl_checker -q --generate-pot po/.$@ $(PMSFILES)
	xgettext $(MAIN_PO_FILES:%=-x %) -o ..$@ .$@
	msgcat --use-first ..$@ desktopstuff.pot > $@
	rm -f desktopstuff.pot $(NAME)_tmp.pot .$@ ..$@

install: $(MOFILES)
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

POTFILES.in:
	(cd .. ; /bin/ls data/*.desktop.in data/*.directory.in) > POTFILES.in


clean:
	@rm -rf *.mo $(POFILES:%=%t)
