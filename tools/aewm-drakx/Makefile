ARCH := $(shell arch | egrep "(x86_64|sparc64|s390x)")
ifneq ("x$(ARCH)", "x")
LIB_NAME = lib64
else
LIB_NAME = lib
endif

CFLAGS = -Wall -Os
LDFLAGS = -L/usr/X11R6/$(LIB_NAME) -lX11
CFILES = $(wildcard *.c)
OFILES = $(CFILES:%.c=%.o)
GOAL = aewm-drakx

$(GOAL): $(OFILES)

clean:
	rm -f $(GOAL) $(OFILES) TAGS *~
