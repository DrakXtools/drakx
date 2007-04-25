clean:
	rm -rf *~

check:
	perl modules.pl check > /dev/null
	@echo "unlisted drivers: "
	@for i in $$(zcat /usr/share/ldetect-lst/pcitable.gz|cut -f 2 -d \" |egrep -v '^#|ADSL:|Bad:|Card:|H[cs]f:|ISDN:|LT:'|sort|uniq|less);do fgrep -q $$i list_modules.pm|| echo -n "$$i ";done
	@echo
