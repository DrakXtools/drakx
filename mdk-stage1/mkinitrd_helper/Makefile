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


VERSION = 1.1.1

DEFS = -DVERSION=\"$(VERSION)\"


MKINITRD_HELPER_SRC = mkinitrd_helper.c
MKINITRD_HELPER_LIBS = ../insmod-busybox/libinsmod-DIET.a

MKINITRD_HELPER_OBJS = $(subst .c,.o,$(MKINITRD_HELPER_SRC))

BIN = mkinitrd_helper 

all: $(BIN)

clean:
	rm -f *.o $(BIN)

FLAGS = -Wall -Werror -Os -fomit-frame-pointer -c


$(MKINITRD_HELPER_OBJS): %.o: %.c
	$(CC) $(DEFS) $(DIETLIBC_INCLUDES) -I.. -c $< -o $@

mkinitrd_helper: $(MKINITRD_HELPER_OBJS) $(MKINITRD_HELPER_LIBS) $(DIETLIBC_LIBC)
	$(CC) $(DIETLIBC_LDFLAGS_STAGE1) -o $@ $^
	$(STRIPCMD) $@
