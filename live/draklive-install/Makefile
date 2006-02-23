NAME = draklive-install
VERSION := $(shell rpm -q --qf '%{VERSION}\n' --specfile $(NAME).spec | head -1)
RELEASE := $(shell rpm -q --qf '%{RELEASE}\n' --specfile $(NAME).spec | head -1)

rpm: dis
	rpm -tb ../$(NAME)-$(VERSION).tar.bz2

check:
	perl -cw $(NAME)

clean:
	make -C po clean
	find -name '*~' -exec rm {} \;

dis ../$(NAME)-$(VERSION).tar.bz2: clean check
	rm -rf $(NAME)-$(VERSION) ../$(NAME)-$(VERSION).tar*
	mkdir -p $(NAME)-$(VERSION)
	find . -not -name "$(NAME)-$(VERSION)"|cpio -pd $(NAME)-$(VERSION)/
	find $(NAME)-$(VERSION) -type d -name CVS -o -name .cvsignore -o -name unused |xargs rm -rf
	tar cf ../$(NAME)-$(VERSION).tar $(NAME)-$(VERSION)
	bzip2 -9f ../$(NAME)-$(VERSION).tar
	rm -rf $(NAME)-$(VERSION)
