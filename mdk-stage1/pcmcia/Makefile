 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2001 Mandrakesoft
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 #
 #*****************************************************************************

# startup.c is based on pcmcia-socket-startup from pcmciautils-013

top_dir = ..

include $(top_dir)/Makefile.common

TARGET = libpcmcia.a
YFLAGS := -d

all: $(TARGET) pcmcia_probe.o

clean:
	rm -f *.o $(TARGET) lex_config.c yacc_config.c yacc_config.h

FLAGS = -D__linux__ -Wall -Werror -Wno-deprecated-declarations -Os -fomit-frame-pointer -pipe -c -I.. -D_BSD_SOURCE
# (blino) make sure yynewerror and yyerrlab are uselessly used
FLAGS += -Dlint
LFLAGS += --nounput


OBJS = probe.o startup.o yacc_config.o lex_config.o


%.c %.h : %.y
	$(YACC) $(YFLAGS) $<
	mv y.tab.c $*.c
	mv y.tab.h $*.h

$(TARGET): $(OBJS) yacc_config.h
	ar -cru $@ $^
	ranlib $@

$(OBJS): %.o: %.c
	$(DIET) gcc $(FLAGS) $(INCLUDES) -c $< -o $@

pcmcia_probe.o: probe.c
	$(DIET) gcc -fPIC $(FLAGS) $(INCLUDES) -c $< -o $@
