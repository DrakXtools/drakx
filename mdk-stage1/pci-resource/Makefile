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

pci-ids.h: /usr/share/ldetect-lst/pcitable update-pci-ids.pl ../../modules/network_modules.mar ../../modules/hd_modules.mar
	perl update-pci-ids.pl > $@ || rm -f $@

clean:
	rm -f pci-ids.h
