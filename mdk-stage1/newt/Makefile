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


all: libnewt.a libnewt-DIET.a

clean:
	rm -f *.o *.a

FLAGS = -Wall -Werror -Os -fomit-frame-pointer -DVERSION=\"0.50.19\" -c

INCS = -I../slang


OBJS = newt.o button.o form.o checkbox.o entry.o label.o listbox.o scrollbar.o textbox.o scale.o grid.o windows.o buttonbar.o checkboxtree.o
OBJS-DIET = $(subst .o,-DIET.o,$(OBJS))


libnewt.a: $(OBJS)
	ar -cru $@ $^
	ranlib $@

libnewt-DIET.a: $(OBJS-DIET)
	ar -cru $@ $^
	ranlib $@


$(OBJS): %.o: %.c
	gcc $(FLAGS) $(GLIBC_INCLUDES) $(INCS) -c $< -o $@

$(OBJS-DIET): %-DIET.o: %.c
	gcc $(FLAGS)  $(DIETLIBC_INCLUDES) $(INCS) -c $< -o $@

