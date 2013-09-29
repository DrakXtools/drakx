POLKITPOLICYDEST = $(PREFIX)/usr/share/polkit-1/actions

POLICY_IN := $(wildcard *.policy.in)
POLICY = $(POLICY_IN:.policy.in=.policy)

all: $(POLICY)

clean:
	rm -f $(POLICY)

install: all
	install -d $(POLKITPOLICYDEST)
	install -m644 $(POLICY) $(POLKITPOLICYDEST)

%.policy:   %.policy.in
	intltool-merge --utf8 ../../po $< $@ -x -u -c ../../po/.intltool-merge-cache
