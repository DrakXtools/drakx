 #******************************************************************************
 #
 #    mdk-stage1 - the program that will load second-stage install
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
 # Portions from Erik Troan (ewt@redhat.com) Copyright 1996 Red Hat Software 
 #
 #*****************************************************************************

VERSION = 7.2cooker


ARCH := $(patsubst i%86,i386,$(shell uname -m))
ARCH := $(patsubst sparc%,sparc,$(ARCH))


 #- We can leave "-g" forever since stripping will remove everything
CFLAGS = -Os -g -Wall -Werror -fomit-frame-pointer
INCLUDES = -I.
DEFS = -D_GNU_SOURCE=1 -DVERSION=\"$(VERSION)\" -DUSE_LOGDEV

COMPILE = $(CC) $(DEFS) $(INCLUDES) $(CFLAGS)


 #- stage1 "loader"
INITSRC = minilibc.c init.c

 #- stage1 itself
STAGE1SRC = #stage1.c cdrom.c devices.c


ALLSRC = $(INITSRC) $(STAGE1SRC)


STATIC = -static

ifeq (i386, $(ARCH))
MINILIBC=minilibc.o
LDFLAGS = -nostdlib /usr/lib/crt1.o
STATIC=-static
else
ifeq (sparc, $(ARCH))
MINILIBC=minilibc.o /usr/lib/libc.a
LDFLAGS = -nostdlib /usr/lib/crt1.o
STATIC=-static
else
STATIC=-static
endif
endif


BINS = init


#ifeq (i386, $(ARCH))
#BINS += stage1-all stage1-cdrom stage1-network stage1-hd stage1-pcmcia
#endif
#
#ifeq (ia64, $(ARCH))
#BINS += stage1-all
#endif
#
#ifeq (alpha, $(ARCH))
#BINS += stage1-all
#endif
#
#ifeq (sparc, $(ARCH))
#BINS += stage1-all
#endif

DIRS = mar


all: dirs $(BINS)

dirs:
	@echo -e "*** BUILDING in all directories\n"
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n ;\
	done

.c.o:
	$(COMPILE) -c $<

init: init.o $(MINILIBC)
	$(CC) $(STATIC) $(LDFLAGS) -o $@ init.o $(MINILIBC)

stage1-network: stage1-network.o $(OBJS) $(NETOBJS)
	$(CC) -g $(STATIC) -o $@ $^ -lpopt     \
        -lkudzu_loader ../isys/libisys.a ../balkan/libbalkan.a \
	$(MODULELINKAGE) \
        -lpump -lbz2 -lz -lresolv -lnewt -lslang -lpci

clean: 
	@echo -e "*** CLEANING in all directories\n"
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done
	rm -f *.o .depend $(BINS)

deps:
	$(CPP) $(CFLAGS) -DHAVE_CONFIG_H -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif                                           
