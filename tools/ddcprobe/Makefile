ARCH	:= $(patsubst i%86,i386,$(shell uname -m))
ARCH	:= $(patsubst sparc%,sparc,$(ARCH))
ARCH	:= $(patsubst amd64,x86_64,$(ARCH))

ifeq (i386,$(ARCH))
HAS_VBE	= y
endif
ifeq (x86_64,$(ARCH))
HAS_VBE = y
endif
ifeq (ia64,$(ARCH))
HAS_VBE = y
endif

CC	= gcc
CFLAGS	= -O -Wall # -g -DDEBUG
INCS	= -I.
LDFLAGS	= -lm
ifeq (y,$(HAS_VBE))
LDFLAGS	+= -L. -lint10 -lx86emu
OBJS	= ddcxinfos.o vesamode.o vbe.o
LIBS	= libint10.a libx86emu.a
DEFS	+= -DHAVE_VBE
endif
ifeq (ppc,$(ARCH))
OBJS	= ddcxinfos.o of.o minifind.o vbe.o vesamode.o
endif
ifeq (,$(OBJS))
OBJS	= not_handled.o
endif
CPPFLAGS= $(DEFS)
TARGETS	= ddcxinfos

all: $(TARGETS)

ddcxinfos: $(OBJS) $(LIBS)
	$(CC) -o $@ $(OBJS) $(CFLAGS) $(LDFLAGS)

libx86emu.a: x86emu/*.c
	$(MAKE) -C x86emu

libint10.a: libx86emu.a int10/*.c
	$(MAKE) -C int10

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(INCS) -c $< -o $@

clean:
	$(MAKE) -C int10 clean
	$(MAKE) -C x86emu clean
	$(RM) $(TARGETS) $(LIBS) *.o core
