CFLAGS = -Wall -Os
CFILES = $(wildcard *.c)
OFILES = $(CFILES:%.c=%.o)
GOAL = serial_probe

$(GOAL): $(OFILES)

clean:
	rm -f $(GOAL) $(OFILES) *~
