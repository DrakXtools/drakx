NAME = draklive-install
localedir = ${prefix}/share/locale
PL_FILES = ../$(NAME) $(shell find .. -type f -name "*pm")

POFILES = $(shell for i in ../../../perl-install/share/po/*.po; do basename $$i; done)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

all: $(NAME).pot $(POFILES) $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

merge: $(NAME).pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

$(NAME).pot:
	xgettext -F -n --from-code --add-comments='I18N' \
	--keyword=_ --keyword=__ --keyword=N_ --keyword=N \
	-o $@ $(PL_FILES)

install: all
	for l in $(LANGS); do \
		install -d $(localedir)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(localedir)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) $(NAME).pot
