NAME = DrakX
LOCALEDIR = ${prefix}/share/locale
PMSFILES = *.pm share/meta-task/compssUsers.pl*  ../../advertising/*.pl
PMSFILES_HERE = $(wildcard $(PMSFILES:%=../../%))

MAIN_PO_FILES = ../../../share/po/libDrakX.pot

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

default: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

update_n_merge: $(NAME).pot merge

merge: $(NAME).pot
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

$(NAME).pot: $(PMSFILES_HERE)
	cd ../.. ; perl_checker -q --generate-pot share/po/.$@ $(PMSFILES)
	xgettext $(MAIN_PO_FILES:%=-x %) -o $@ .$@
	rm -f .$@

install: $(MOFILES)
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t)
