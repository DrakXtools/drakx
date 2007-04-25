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


TARGETS = pppd

BINTARGET = ../../pppd


all: $(TARGETS)

clean:
	rm -f *.o *.a $(BINTARGET) pppd

FLAGS = -Wall -Wno-deprecated-declarations -Werror -Os -fomit-frame-pointer -DDO_BSD_COMPRESS=0 -D_linux_=1 -DHAVE_MMAP -DNO_DRAND48 -D_BSD_SOURCE -D_GNU_SOURCE
# (blino) for gcc-4.1.1, dereferencing type-punned pointer will break strict-aliasing rules, in options.c:711
FLAGS += -fno-strict-aliasing

INCS = -I../include -I.

ifeq (GLIBC, $(L))
LIBS = -static -lcrypt
endif


OBJS = main.o magic.o fsm.o lcp.o ipcp.o upap.o chap.o md5.o ccp.o auth.o options.o demand.o utils.o sys-linux.o ipxcp.o multilink.o tdb.o tty.o


pppd: $(OBJS)
	$(DIET) gcc -o $@ $^ $(LIBS)
	$(STRIPCMD) $@
	cp -f $@ $(BINTARGET)

$(OBJS): %.o: %.c
	$(DIET) gcc $(FLAGS) $(INCS) $(INCLUDES) -c $< -o $@
