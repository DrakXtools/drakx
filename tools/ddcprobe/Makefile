CC	= gcc
CFLAGS	= -O -Wall # -g -DDEBUG
INCS	= -I.
LDFLAGS	= -lm -L. -lint10 -lx86emu
OBJS	= ddcxinfos.o vesamode.o vbe.o
LIBS	= libint10.a libx86emu.a
TARGETS	= ddcxinfos

all: $(TARGETS)

ddcxinfos: $(OBJS) $(LIBS)
	$(CC) -o $@ $(OBJS) $(CFLAGS) $(LDFLAGS)

libx86emu.a:
	$(MAKE) -C x86emu

libint10.a: libx86emu.a
	$(MAKE) -C int10

%.o: %.c
	$(CC) $(CFLAGS) $(INCS) -c $< -o $@

clean:
	$(MAKE) -C int10 clean
	$(MAKE) -C x86emu clean
	$(RM) $(TARGETS) $(LIBS) *.o core
