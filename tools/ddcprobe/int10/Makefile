CC	= gcc
INCS	=
CFLAGS	= -O -Wall
SRCS	= emu_vm86.c i10_int.c i10_io.c i10_pci.c i10_v86.c i10_vbios.c
OBJS	= $(SRCS:%.c=%.o)

TARGETLIB = ../libint10.a

all: $(TARGETLIB)

$(TARGETLIB): $(OBJS)
	@ar rv $(TARGETLIB) $(OBJS)

%.o: %.c
	$(CC) $(CFLAGS) $(INCS) -c $< -o $@

clean:
	@rm -f $(TARGETLIB)
	@rm -f $(OBJS) validate.o
