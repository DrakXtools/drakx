all: all.modules

all.modules: ../mdk-stage1/mar/mar update_kernel list_modules.pm
	./update_kernel

../mdk-stage1/mar/mar:
	make -C `dirname $@` mar

clean:
	rm -rf *~ modules.description all.modules all.modules64

check:
	perl modules.pl check > /dev/null
