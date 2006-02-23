NAME = draklive-install
localedir = ${prefix}/share/locale
PL_FILES = ../$(NAME) $(shell find .. -type f -name "*pm")

MERGE_POFILES = $(shell for i in ../../../perl-install/share/po/*.po; do basename $$i; done)
POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

all: $(NAME).pot $(POFILES) $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

merge: $(NAME).pot
	@for n in $(MERGE_POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

$(NAME).pot:
	perl_checker -q --generate-pot $@ $(PL_FILES)

install: all
	for l in $(LANGS); do \
		install -d $(localedir)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(localedir)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) $(NAME).pot
