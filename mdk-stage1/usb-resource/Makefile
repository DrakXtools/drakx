 #******************************************************************************
 #
 # $Id$
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


all: usb-ids.h

usb-ids.h: /usr/share/ldetect-lst/usbtable.gz update-usb-ids.pl
	perl update-usb-ids.pl > $@ || rm -f $@

clean:
	rm -f usb-ids.h
