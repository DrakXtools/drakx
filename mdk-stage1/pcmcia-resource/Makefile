 #******************************************************************************
 #
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

TARGET=pcmcia-ids.h

all: $(TARGET)

$(TARGET):
	perl update-pcmcia-ids.pl > $@ || { rm -f $@; exit 1; }

clean:
	rm -f $(TARGET)
