 #******************************************************************************
 #
 #    mar - The Mandrake Archiver
 #
 # $Id$
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


all: libmar.a mar

clean:
	rm -f *.o libmar.a mar

FLAGS = -Wall -Werror -Os -fomit-frame-pointer -c


mar: mar-frontend.o mar-extract-only-standalone.o
	gcc -o mar mar-frontend.o mar-extract-only-standalone.o -lz

libmar.a: mar-extract-only.o
	ar -cru $@ $^
	ranlib $@

mar-frontend.o: mar-frontend.c mar.h mar-extract-only.h
	gcc $(FLAGS) mar-frontend.c

mar-extract-only.o: mar-extract-only.c mar-extract-only.h mar.h
	gcc $(FLAGS) mar-extract-only.c

mar-extract-only-standalone.o: mar-extract-only.c mar-extract-only.h mar.h
	gcc $(FLAGS) -o $@ -D_STANDALONE_ mar-extract-only.c
