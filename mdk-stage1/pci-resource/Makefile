 #******************************************************************************
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
 #*****************************************************************************


all: pci-ids.h

pci-ids.h: ../../perl-install/pci_probing/pcitable update-pci-ids.pl
	make -C ../../perl-install/pci_probing
	perl update-pci-ids.pl > $@

clean:
	rm -f pci-ids.h
