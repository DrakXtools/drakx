 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2001 MandrakeSoft
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 #
 #*****************************************************************************

top_dir = ..

include $(top_dir)/Makefile.common


all: libpcmcia.a libpcmcia-DIET.a

clean:
	rm -f *.o libpcmcia.a

FLAGS = -D__linux__ -Wall -Werror -Os -fomit-frame-pointer -pipe -c -I..


OBJS = probe.o cardmgr.o lex_config.o yacc_config.o

OBJS-DIET = $(subst .o,-DIET.o,$(OBJS))


libpcmcia.a: $(OBJS)
	ar -cru $@ $^
	ranlib $@

libpcmcia-DIET.a: $(OBJS-DIET)
	ar -cru $@ $^
	ranlib $@


$(OBJS): %.o: %.c
	gcc $(FLAGS) $(GLIBC_INCLUDES) -c $< -o $@

$(OBJS-DIET): %-DIET.o: %.c
	gcc $(FLAGS)  $(DIETLIBC_INCLUDES) -c $< -o $@

