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

top_dir = ../..

include $(top_dir)/Makefile.common


TARGETS = pppoe

ifeq (DIETLIBC, $(L))
TARGETS += pppoe-DIET
endif

BINTARGET = ../pppoe-bin


all: $(TARGETS)

clean:
	rm -f *.o *.a $(BINTARGET) pppoe pppoe-DIET

FLAGS = -Wall -Werror -Os -fomit-frame-pointer '-DPPPOE_PATH="/sbin/pppoe"' '-DPPPD_PATH="/sbin/pppd"' '-DVERSION="3.0-stg1"'



OBJS = pppoe.o if.o debug.o common.o ppp.o discovery.o
OBJS-DIET = $(subst .o,-DIET.o,$(OBJS))


pppoe: $(OBJS)
	gcc -static -o $@ $^
	$(STRIPCMD) $@
	cp -f $@ $(BINTARGET)

pppoe-DIET: $(OBJS-DIET)
	gcc $(DIETLIBC_LDFLAGS_STAGE1) -o $@ $^ $(DIETLIBC_LIBC)
	$(STRIPCMD) $@
	cp -f $@ $(BINTARGET)

$(OBJS): %.o: %.c
	gcc $(FLAGS) $(GLIBC_INCLUDES) $(INCS) -c $< -o $@

$(OBJS-DIET): %-DIET.o: %.c
	gcc $(FLAGS) $(DIETLIBC_INCLUDES) $(INCS) -c $< -o $@

