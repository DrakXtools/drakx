CFLAGS=-Wall -O # -g -DDEBUG
TARGETS=dmidecode

ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))

ifeq (i386,$(ARCH))

dmidecode: dmidecode.o

else
dmidecode: not_handled.c
	gcc -o $@ $<
endif

clean:
	$(RM) $(TARGETS) *.o core
