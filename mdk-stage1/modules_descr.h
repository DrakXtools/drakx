/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2001 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#ifndef _MODULES_DESCR_H_
#define _MODULES_DESCR_H_

struct module_descr {
	const char * module;
	char * descr;
};

struct module_descr modules_descriptions[] = {
#ifndef DISABLE_NETWORK
	/* description of network drivers that have not very explicit names */
	{ "ne",        "NE1000/NE2000/clones" },
	{ "ne2k-pci",  "PCI NE2000" },
	{ "depca",     "DEC DEPCA/DE100/DE101/DE200/DE201/DE202/DE210/DE422" },
	{ "dgrs",      "Digi RightSwitch SE-X" },
	{ "ewrk3",     "DEC DE203/DE204/DE205" },
	{ "lance",     "Allied Telesis AT1500, HP J2405A, NE2100/NE2500" },
	{ "sis900",    "SiS 900/7016/630E, Am79c901, RTL8201" },
	{ "via-rhine", "VIA VT86c100A Rhine-II, 3043 Rhine-I" },
	{ "tulip",     "DEC 21040-family based cards" },
	{ "wd",        "WD8003/WD8013" },
	{ "bmac",      "Macintosh integrated ethernet (G3)" },
	{ "gmac",      "Macintosh integrated ethernet (G4/iBook)" },
	{ "mace",      "Macintosh integrated ethernet (PowerMac)" },
#endif

#ifndef DISABLE_MEDIAS
	/* description of scsi drivers that have not very explicit names */
	{ "53c7,8xx",  "NCR53c810/700" },
	{ "sim710",    "NCR53c710" },
	{ "aic7xxx",   "Adaptec 7xxx family (AIC/AHA/etc)" },
	{ "atp870u",   "ACARD/ARTOP AEC-6710/6712" },
	{ "ncr53c8xx", "Symbios 53c family" },
	{ "sym53c8xx", "Symbios 53c family" },
	{ "sim710",    "NCR53C710 family" },
	{ "mesh",      "Macintosh integrated SCSI (NewWorld or internal SCSI)" },
	{ "mac53c94",  "Macintosh integrated SCSI (OldWorld or external SCSI)" },
#endif

#ifdef ENABLE_USB
	/* description of usb drivers that have not very explicit names */
	{ "usbnet",    "Netchip or Prolific USB-USB Bridge" },
	{ "pegasus",   "ADMtek AN986 (USB Ethernet chipset)" },
	{ "kaweth",    "KL5KUSB101 (USB Ethernet chipset)" },
	{ "catc",      "CATC EL1210A NetMate USB Ethernet" },
#endif
};

int modules_descriptions_num = sizeof(modules_descriptions) / sizeof(struct module_descr);


#endif
