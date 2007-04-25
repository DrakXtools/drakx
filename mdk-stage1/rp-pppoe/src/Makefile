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

top_dir = ../..

include $(top_dir)/Makefile.common


TARGETS = pppoe

BINTARGET = ../../pppoe


all: $(TARGETS)

clean:
	rm -f *.o *.a $(BINTARGET) pppoe

FLAGS = -Wall -Werror -Os -fomit-frame-pointer '-DPPPOE_PATH="/sbin/pppoe"' '-DPPPD_PATH="/sbin/pppd"' '-DVERSION="3.0-stg1"'

ifeq (GLIBC, $(L))
EXTRA_LDFLAGS = -static
endif

OBJS = pppoe.o if.o debug.o common.o ppp.o discovery.o

pppoe: $(OBJS)
	$(DIET) gcc -o $@ $^ $(EXTRA_LDFLAGS)
	$(STRIPCMD) $@
	cp -f $@ $(BINTARGET)

$(OBJS): %.o: %.c
	$(DIET) gcc $(FLAGS) $(INCLUDES) $(INCS) -c $< -o $@
