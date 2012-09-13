CC = gcc
CFLAGS = -Wall -Os
CFILES = $(wildcard *.c)
OFILES = $(CFILES:%.c=%.o)
GOAL = serial_probe

#$(GOAL): $(OFILES)

serial_probe: serial.c serial_probe.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -Os -fwhole-program -flto -Wl,-O2 -o $@ $^ $(LIBS)


#serial.o: serial.c serial.h device.h kudzu.h
#serial_probe.o: serial_probe.c serial.h device.h
#serial_probe: serial_probe.o

clean:
	rm -f $(GOAL) $(OFILES) *~
