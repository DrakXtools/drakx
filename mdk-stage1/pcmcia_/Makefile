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

top_dir = ..

include $(top_dir)/Makefile.common


all: libpcmcia.a

clean:
	rm -f *.o libpcmcia.a

FLAGS = -D__linux__ -Wall -Werror -Os -fomit-frame-pointer -pipe -c -I.. -D_BSD_SOURCE


OBJS = probe.o cardmgr.o lex_config.o yacc_config.o


libpcmcia.a: $(OBJS)
	ar -cru $@ $^
	ranlib $@

$(OBJS): %.o: %.c
	$(DIET) gcc $(FLAGS) $(INCLUDES) -c $< -o $@
