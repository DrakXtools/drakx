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

update_n_merge: $(NAME).pot merge

merge:
	for n in $(POFILES); do \
	  echo "Merging $$n"; \
	  msgmerge $$n $(NAME).pot > "$$n"t ; \
	  mv -f "$$n"t $$n ; \
	done

# there are better ways to do this, but..
merge_mageia_translations: $(NAME).pot
	@for n in $(POFILES); do \
		echo "Merging $$n translations from Mageia"; \
		sed -e '/^$$/q' "$$n" > "$$n.header"; \
		mv "$$n" "$$n.orig"; \
		git checkout --theirs mageia/master "$$n"; \
		sed -e 's#ageia#oondrake#g' -i "$$n"; \
		msgcat --use-first -o "$$n.temp" -t utf-8 -s "$$n.orig" "$$n"; \
		git checkout --theirs origin/master "$$n"; \
		msgcat --use-first -o "$$n.orig" "$$n.header" "$$n.temp"; \
		mv "$$n.orig" "$$n"; \
		rm "$$n.temp" "$$n.header"; \
		msgmerge "$$n" $^ > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

$(NAME).pot: $(PMSFILES_HERE) POTFILES.in
	intltool-update --gettext-package desktopstuff --pot
	cd .. ; perl_checker -q --generate-pot po/.$@ $(PMSFILES)
	xgettext $(MAIN_PO_FILES:%=-x %) -o ..$@ .$@
	msgcat --use-first .$@ desktopstuff.pot > $@
	rm -f desktopstuff.pot $(NAME)_tmp.pot .$@ ..$@

install: $(MOFILES)
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

POTFILES.in:
	(cd .. ; /bin/ls -1 menu/*.desktop.in polkit/*.policy.in; ) > POTFILES.in


clean:
	@rm -rf *.mo $(POFILES:%=%t) POTFILES.in
