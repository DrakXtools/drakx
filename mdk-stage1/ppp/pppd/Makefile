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


TARGETS = pppd

ifeq (DIETLIBC, $(L))
TARGETS += pppd-DIET
endif

BINTARGET = ../pppd-bin


all: $(TARGETS)

clean:
	rm -f *.o *.a $(BINTARGET) pppd pppd-DIET

FLAGS = -Wall -Werror -Os -fomit-frame-pointer -DDO_BSD_COMPRESS=0 -D_linux_=1 -DHAVE_MMAP -DNO_DRAND48

INCS = -I../include -I.


OBJS = main.o magic.o fsm.o lcp.o ipcp.o upap.o chap.o md5.o ccp.o auth.o options.o demand.o utils.o sys-linux.o ipxcp.o multilink.o tdb.o tty.o
OBJS-DIET = $(subst .o,-DIET.o,$(OBJS))


pppd: $(OBJS)
	gcc -static -o $@ $^ -lcrypt
	$(STRIPCMD) $@
	cp -f $@ $(BINTARGET)

pppd-DIET: $(OBJS-DIET)
	gcc $(DIETLIBC_LDFLAGS_STAGE1) -o $@ $^ $(DIETLIBC_LIBC)
	$(STRIPCMD) $@
	cp -f $@ $(BINTARGET)

$(OBJS): %.o: %.c
	gcc $(FLAGS) $(INCS) $(GLIBC_INCLUDES) -c $< -o $@

$(OBJS-DIET): %-DIET.o: %.c
	gcc $(FLAGS) $(INCS) $(DIETLIBC_INCLUDES) -c $< -o $@

