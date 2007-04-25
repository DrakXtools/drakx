include ../../Makefile.config

NAME = libDrakX
PMSFILES = $(filter-out install/% standalone/%, $(ALLPMS))
PMSFILES_HERE = $(wildcard $(PMSFILES:%=../../%))

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

LOCALEDIR=$(DATADIR)/locale


all: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

merge: $(NAME).pot
	for n in $(POFILES); do \
	  echo "Merging $$n"; \
	  msgmerge -C $$n $$n $(NAME).pot > "$$n"t ; \
	  mv -f "$$n"t $$n ; \
	done

$(NAME).pot: $(PMSFILES_HERE)
	cd ../.. ; perl_checker -q --generate-pot share/po/$@ $(PMSFILES)

install: $(MOFILES)
	for l in $(LANGS); do \
		$(SUDO) install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		$(SUDO) install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(NAME).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t)

verif:
	perl -ne '/^\s*#/ or $$i += my @l = /\b__?\(/g; END { print "$$i\n" }' $(PMSFILES_HERE)
	perl -ne '$$i += my @l = /\.c:/g; END { print "$$i\n" }' DrakX.pot

verif2: 
#	perl -I ../.. -Mcommon -e 'foreach (qw($(PMSFILES))) { printf "package foo%d;\n", ++$$i; print common::cat_($$_) }' | perl -ne 'print if !/use (diagnostics|vars|strict)/' | OUTFILE=tmp.pm perl -I. -I../.. -Mb_dump_strings >/dev/null 2>/dev/null
	perl -pe 's|$$|\\n\\|' tmp.pm > tmp.pm_.c
	xgettext --keyword=_ -o tmp.po tmp.pm_.c 
	msgmerge DrakX.pot tmp.po > tmp.pot
	grep "^msgid" tmp.pot | sort > tmp.pot.light
	grep "^msgid" DrakX.pot | sort | diff - tmp.pot.light | grep "^>" || true


#	for i in *.po; do echo -n "$i "; msgfmt -v $i 2>&1; done | perl -e 'print map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [ $_, (split)[1] ] } <>'


%: %.sh
	#  fake built-in
