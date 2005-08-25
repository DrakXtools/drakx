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


all: pci-ids.h

pci-ids.h: /usr/share/ldetect-lst/pcitable.gz update-pci-ids.pl
	perl update-pci-ids.pl > $@ || { rm -f $@; exit 1; }

clean:
	rm -f pci-ids.h
