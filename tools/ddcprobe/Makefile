CFLAGS=-Wall -O # -g -DDEBUG
LDFLAGS = -lm
TARGETS=ddcxinfos

ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))

ifeq (i386,$(ARCH))

ddcxinfos: lrmi.o vesamode.o vbe.o ddcxinfos.o

libvbe.a: lrmi.o vesamode.o vbe.o
	$(AR) cru $@ $^

#install: $(DESTDIR)/usr/include/vbe.h $(DESTDIR)/usr/lib/libvbe.a

$(DESTDIR)/usr/include/vbe.h:
	install -m 644 vbe.h $(DESTDIR)/usr/include/vbe.h

$(DESTDIR)/usr/lib/libvbe.a:
	install -m 644 libvbe.a $(DESTDIR)/usr/lib/libvbe.a

else
ddcxinfos: not_handled.c
	gcc -o $@ $<
endif

clean:
	$(RM) $(TARGETS) *.o core
