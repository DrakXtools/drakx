CFLAGS = -Wall -Os
LDFLAGS = -L/usr/X11R6/lib -lX11
CFILES = $(wildcard *.c)
OFILES = $(CFILES:%.c=%.o)
GOAL = aewm-drakx

$(GOAL): $(OFILES)

clean:
	rm -f $(GOAL) $(OFILES) TAGS *~
