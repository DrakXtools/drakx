all: all.kernels

all.kernels: ../mdk-stage1/mar/mar update_kernel list_modules.pm
	./update_kernel

../mdk-stage1/mar/mar:
	make -C `dirname $@` mar

clean:
	rm -rf *~ modules.description all.kernels

check:
	perl modules.pl check > /dev/null
	@echo "unlisted drivers: "
	@for i in $$(cut -f 2 -d \" /usr/share/ldetect-lst/pcitable|egrep -v '^#|ADSL:|Bad:|Card:|H[cs]f:|ISDN:|LT:'|sort|uniq|less);do fgrep -q $$i list_modules.pm|| echo -n "$$i ";done
	@echo
