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


all: mar

clean:
	rm -f *.o mar

FLAGS = -Wall -Werror -Os -fomit-frame-pointer -c


mar: mar-frontend.o mar-extract-only.o
	gcc -o mar mar-frontend.o mar-extract-only.o -lz

mar-frontend.o: mar-frontend.c mar.h mar-extract-only.h
	gcc $(FLAGS) mar-frontend.c

mar-extract-only.o: mar-extract-only.c mar-extract-only.h mar.h
	gcc $(FLAGS) mar-extract-only.c
