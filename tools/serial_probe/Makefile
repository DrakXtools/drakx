CFLAGS = -Wall -Os
CFILES = $(wildcard *.c)
OFILES = $(CFILES:%.c=%.o)
GOAL = serial_probe

$(GOAL): $(OFILES)

serial.o: serial.c serial.h device.h kudzu.h
serial_probe.o: serial_probe.c serial.h device.h
serial_probe: serial_probe.o

clean:
	rm -f $(GOAL) $(OFILES) *~
