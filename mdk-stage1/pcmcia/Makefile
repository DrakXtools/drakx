 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2000 MandrakeSoft
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

FLAGS = -Wall -Werror -Os -fomit-frame-pointer -pipe -c -I..

libpcmcia.a: pcmcia_probe.o cardmgr.o lex_config.o yacc_config.o
	ar -cru $@ $^
	ranlib $@

.c.o:
	gcc $(FLAGS) $(GLIBC_INCLUDES) $<

