 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 # Olivier Blin (blino@mandriva.com)
 #
 # Copyright 2006 Mandriva
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 #
 #*****************************************************************************

# minimal sysfs library ripped from sysfsutils-2.0.0

top_dir = ..

include $(top_dir)/Makefile.common

TARGET = libsysfs.a

all: $(TARGET)

clean:
	rm -f *.o $(TARGET)

FLAGS = -D__linux__ -Wall -Werror -Wno-deprecated-declarations -Os -fomit-frame-pointer -pipe -c -I.. -D_BSD_SOURCE

OBJS = sysfs_attr.o sysfs_utils.o

$(TARGET): $(OBJS)
	ar -cru $@ $^
	ranlib $@

$(OBJS): %.o: %.c
	$(DIET) gcc $(FLAGS) $(INCLUDES) -c $< -o $@
