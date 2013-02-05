 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandriva.com)
 #
 # Copyright 2001 Mandriva
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
	rm -f *.o $(TARGET) lex_config.c* yacc_config.cpp yacc_config.h

INCLUDES += -I$(top_dir)

# (blino) make sure yynewerror and yyerrlab are uselessly used
INCLUDES += -Dlint

OBJS = probe.o startup.o yacc_config.o lex_config.o

lex_config.cpp: lex_config.c
	ln -s $< $@

%.cpp %.h : %.y
	$(YACC) $(YFLAGS) $<
	mv y.tab.c $*.cpp
	mv y.tab.h $*.h

$(TARGET): $(OBJS) yacc_config.h
	ar -cru $@ $^
	ranlib $@

$(OBJS): %.o: %.cpp
	$(DIET) $(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

pcmcia_probe.o: probe.cpp
	$(DIET) $(CXX) -fPIC $(CXXFLAGS) $(INCLUDES) -c $< -o $@
