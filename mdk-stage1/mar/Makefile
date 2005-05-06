 #******************************************************************************
 #
 #    mar - The Mandrake Archiver
 #
 # $Id$
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2000 Mandrakesoft
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


TARGETS = libmar.a mar


all: $(TARGETS)

clean:
	rm -f *.o libmar.a mar


mar: mar-frontend.o mar-extract-only-standalone.o
	gcc -o mar mar-frontend.o mar-extract-only-standalone.o -lbz2
	$(STRIPCMD) $@

libmar.a: mar-extract-only.o
	ar -cru $@ $^
	ranlib $@

mar-extract-only.o: mar-extract-only.c mar-extract-only.h mar.h
	$(DIET) gcc $(CFLAGS) $(INCLUDES) -c mar-extract-only.c

mar-frontend.o: mar-frontend.c mar.h mar-extract-only.h
	gcc $(CFLAGS) $(GLIBC_INCLUDES) -c mar-frontend.c

mar-extract-only-standalone.o: mar-extract-only.c mar-extract-only.h mar.h
	gcc $(CFLAGS) $(GLIBC_INCLUDES) -o $@ -D_STANDALONE_ -c mar-extract-only.c
