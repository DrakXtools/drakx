CFLAGS=-Wall -O # -g -DDEBUG
TARGETS=ddcxinfos

ddcxinfos: lrmi.o vesamode.o vbe.o ddcxinfos.o

libvbe.a: lrmi.o vesamode.o vbe.o
	$(AR) cru $@ $^

#install: $(DESTDIR)/usr/include/vbe.h $(DESTDIR)/usr/lib/libvbe.a

$(DESTDIR)/usr/include/vbe.h:
	install -m 644 vbe.h $(DESTDIR)/usr/include/vbe.h

$(DESTDIR)/usr/lib/libvbe.a:
	install -m 644 libvbe.a $(DESTDIR)/usr/lib/libvbe.a

clean:
	$(RM) $(TARGETS) *.o core
