BINDIR = /usr/bin
LIBEXECDIR = /usr/libexec
BINDEST = $(PREFIX)$(BINDIR)
POLKITPOLICYDEST = $(PREFIX)/usr/share/polkit-1/actions

POLICY_IN := $(wildcard *.policy.in)
POLICY = $(POLICY_IN:.policy.in=.policy)
WRAPPERS = $(patsubst org.drakx.%.policy,%,$(POLICY))

all: $(WRAPPERS) $(POLICY)

clean:
	rm -f  $(WRAPPERS) $(POLICY)

%: org.drakx.%.policy.in
	@echo -e '#!/bin/sh\nif  [[ "$(id -u)" != "0" ]] ; then" >\n    exec $(BINDIR)/pkexec $(LIBEXECDIR)/$@ $$""*\nelse\n    exec $(LIBEXECDIR)/$@ $$""*\nfi\n' > $@

%.policy: %.policy.in
	intltool-merge --utf8 ../po $< $@ -x -u -c ../po/.intltool-merge-cache

install: all
	install -d $(BINDEST) $(POLKITPOLICYDEST)
	install -m755 $(WRAPPERS) $(BINDEST)
	install -m644 $(POLICY) $(POLKITPOLICYDEST)
