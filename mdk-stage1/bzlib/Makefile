 #******************************************************************************
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


LIBNAME = libbzlib

OBJS = blocksort.o bzlib.o compress.o crctable.o decompress.o huffman.o randtable.o

DEFS =

INCS =


TARGETS = $(LIBNAME).a

all: $(TARGETS)

clean:
	rm -f *.o *.a

$(LIBNAME).a: $(OBJS)
	ar -cru $@ $^
	ranlib $@

$(OBJS): %.o: %.c
	$(DIET) $(CC) $(CFLAGS) $(DEFS) $(INCS) $(INCLUDES) -c $< -o $@
