/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 Mandrakesoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan (ewt@redhat.com)
 *
 * Copyright 1996 Red Hat Software 
 *
 */


/*
 * This contains stuff related to probing:
 * (1) any (actually only SCSI, NET, CPQ, USB Controllers) devices (autoprobe for PCI and USB)
 * (2) IDE media
 * (3) SCSI media
 * (4) ETH devices
 */


#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <sys/socket.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <pci/pci.h>
#include "stage1.h"

#include "log.h"
#include "frontend.h"
#include "modules.h"
#include "pci-resource/pci-ids.h"
#ifdef ENABLE_USB
#include "usb-resource/usb-ids.h"
#endif
#ifdef ENABLE_PCMCIA
#include "sysfs/libsysfs.h"
#include "pcmcia-resource/pcmcia-ids.h"
#endif

#include "probing.h"


struct media_info {
	char * name;
	char * model;
	enum media_type type;
};


static void warning_insmod_failed(enum insmod_return r)
{
	if (IS_AUTOMATIC && r == INSMOD_FAILED_FILE_NOT_FOUND)
		return;
	if (r != INSMOD_OK) {
		if (r == INSMOD_FAILED_FILE_NOT_FOUND)
			stg1_error_message("This floppy doesn't contain the driver.");
		else
			stg1_error_message("Warning, installation of driver failed. (please include msg from <Alt-F3> for bugreports)");
	}
}

#ifndef DISABLE_NETWORK
struct net_description_elem
{
	char * intf_name;
	char * intf_description;
};
static struct net_description_elem net_descriptions[50];
static int net_descr_number = 0;
static char * intf_descr_for_discover = NULL;
static char * net_intf_too_early_name[50]; /* for modules providing more than one net intf */
static int net_intf_too_early_number = 0;
static int net_intf_too_early_ptr = 0;

void prepare_intf_descr(const char * intf_descr)
{
	intf_descr_for_discover = strdup(intf_descr);
}

void net_discovered_interface(char * intf_name)
{
	if (!intf_descr_for_discover) {
		net_intf_too_early_name[net_intf_too_early_number++] = strdup(intf_name);
		return;
	}
	if (!intf_name) {
		if (net_intf_too_early_ptr >= net_intf_too_early_number) {
			log_message("NET: was expecting another network interface (broken net module?)");
			return;
		}
		net_descriptions[net_descr_number].intf_name = net_intf_too_early_name[net_intf_too_early_ptr++];
	}
	else
		net_descriptions[net_descr_number].intf_name = strdup(intf_name);
	net_descriptions[net_descr_number].intf_description = strdup(intf_descr_for_discover);
	intf_descr_for_discover = NULL;
	net_descr_number++;
}

char * get_net_intf_description(char * intf_name)
{
	int i;
	for (i = 0; i < net_descr_number ; i++)
		if (!strcmp(net_descriptions[i].intf_name, intf_name))
			return net_descriptions[i].intf_description;
	return strdup("unknown");
}
#endif

struct pcitable_entry *detected_devices = NULL;
int detected_devices_len = 0;

static void detected_devices_destroy(void)
{
	if (detected_devices)
		free(detected_devices);
}

static struct pcitable_entry *detected_device_new(void)
{
	static int detected_devices_maxlen = 0;
	if (detected_devices_len >= detected_devices_maxlen) {
		detected_devices_maxlen += 32;
		if (detected_devices == NULL)
 			detected_devices = malloc(detected_devices_maxlen * sizeof(*detected_devices));
		else
			detected_devices = realloc(detected_devices, detected_devices_maxlen * sizeof(*detected_devices));
		if (detected_devices == NULL)
			log_perror("detected_device_new: could not (re)allocate table. Let it crash, sorry");
	}
	return &detected_devices[detected_devices_len++];
}

/* FIXME: factorize with probe_that_type() */

static void add_detected_device(unsigned short vendor, unsigned short device, unsigned int subvendor, unsigned int subdevice, const char *name, const char *module)
{
	struct pcitable_entry *dev = detected_device_new();
	dev->vendor = vendor;
	dev->device = device;
	dev->subvendor = subvendor;
	dev->subdevice = subdevice;
	strncpy(dev->module, module, sizeof(dev->module) - 1);
	dev->module[sizeof(dev->module) - 1] = '\0';
	strncpy(dev->description, name, sizeof(dev->description) - 1);
	dev->description[sizeof(dev->description) - 1] = '\0';
	log_message("detected device (%04x, %04x, %04x, %04x, %s, %s)", vendor, device, subvendor, subdevice, name, module);
}

static int check_device_full(struct pci_module_map_full * pcidb_full, unsigned int len_full,
			     unsigned short vendor, unsigned short device,
			     unsigned short subvendor, unsigned short subdevice)
{
	int i;
	for (i = 0; i < len_full; i++)
		if (pcidb_full[i].vendor == vendor && pcidb_full[i].device == device) {
			if (pcidb_full[i].subvendor == subvendor && pcidb_full[i].subdevice == subdevice) {
				add_detected_device(vendor, device, subvendor, subdevice,
						    pcidb_full[i].name, pcidb_full[i].module);
				return 1;
			}
		}
	return 0;
}

static int check_device(struct pci_module_map * pcidb, unsigned int len,
			unsigned short vendor, unsigned short device,
			unsigned short subvendor, unsigned short subdevice)
{
	int i;
	for (i = 0; i < len; i++)
		if (pcidb[i].vendor == vendor && pcidb[i].device == device) {
			add_detected_device(vendor, device, subvendor, subdevice,
					    pcidb[i].name, pcidb[i].module);
			return 1;
		}
	return 0;
}

void probing_detect_devices()
{
	FILE * f = NULL;
	char buf[512]; /* XXX the better fix is to readjust on '\n' */
        static int already_detected_devices = 0;

	if (already_detected_devices)
		return;

	if (!(f = fopen("/proc/bus/pci/devices", "rb"))) {
		log_message("PCI: could not open proc file");
		return;
	}

	while (1) {
		unsigned int i;
		unsigned short vendor, device, subvendor, subdevice, devbusfn;
		if (!fgets(buf, sizeof(buf), f)) break;
		sscanf(buf, "%hx %x", &devbusfn, &i);
		device = i;
		vendor = i >> 16;
		{
			int bus = devbusfn >> 8;
			int device_p = (devbusfn & 0xff) >> 3;
			int function = (devbusfn & 0xff) & 0x07;
			char file[100];
			int sf;
			sprintf(file, "/proc/bus/pci/%02x/%02x.%d", bus, device_p, function);
			if ((sf = open(file, O_RDONLY)) == -1) {
				log_message("PCI: could not open file for full probe (%s)", file);
				continue;
			}
			if (read(sf, buf, 48) == -1) {
				log_message("PCI: could not read 48 bytes from %s", file);
				close(sf);
				continue;
			}
			close(sf);
			memcpy(&subvendor, buf+44, 2);
			memcpy(&subdevice, buf+46, 2);
		}


#ifndef DISABLE_PCIADAPTERS
#ifndef DISABLE_MEDIAS
		if (check_device_full(medias_pci_ids_full, medias_num_ids_full, vendor, device, subvendor, subdevice))
			continue;
		if (check_device(medias_pci_ids, medias_num_ids, vendor, device, subvendor, subdevice))
			continue;
#endif

#ifndef DISABLE_NETWORK
		if (check_device_full(network_pci_ids_full, network_num_ids_full, vendor, device, subvendor, subdevice))
			continue;
		if (check_device(network_pci_ids, network_num_ids, vendor, device, subvendor, subdevice))
			continue;
#endif
#endif

#ifdef ENABLE_USB
		if (check_device(usb_pci_ids, usb_num_ids, vendor, device, subvendor, subdevice))
			continue;
#endif

		/* device can't be found in built-in pcitables, but keep it */
		add_detected_device(vendor, device, subvendor, subdevice, "", "");
	}

	fclose(f);
	already_detected_devices = 1;
}

void probing_destroy(void)
{
	detected_devices_destroy();
}

#ifndef DISABLE_MEDIAS
static const char * get_alternate_module(const char * name)
{
	struct alternate_mapping {
		const char * a;
		const char * b;
	};
	static struct alternate_mapping mappings[] = {
                { "ahci", "ata_piix" },
        };
	int mappings_nb = sizeof(mappings) / sizeof(struct alternate_mapping);
        int i;

	for (i=0; i<mappings_nb; i++) {
		const char * alternate = NULL;
		if (streq(name, mappings[i].a))
			alternate = mappings[i].b;
		else if (streq(name, mappings[i].b))
			alternate = mappings[i].a;
		if (alternate) {
			log_message("found alternate module %s for driver %s", alternate, name);
			return alternate;
		}
	}
        return NULL;
}
#endif

void discovered_device(enum driver_type type, const char * description, const char * driver)
{


	enum insmod_return failed = INSMOD_FAILED;
#ifndef DISABLE_MEDIAS
	if (type == SCSI_ADAPTERS) {
		const char * alternate = NULL;
		wait_message("Loading driver for media adapter:\n \n%s", description);
		failed = my_insmod(driver, SCSI_ADAPTERS, NULL, 1);
		alternate = get_alternate_module(driver);
		if (!IS_NOAUTO && alternate) {
			failed = failed || my_insmod(alternate, SCSI_ADAPTERS, NULL, 1);
		}
		remove_wait_message();
		warning_insmod_failed(failed);
	}
#endif
#ifndef DISABLE_NETWORK
	if (type == NETWORK_DEVICES) {
		wait_message("Loading driver for network device:\n \n%s", description);
		prepare_intf_descr(description);
		failed = my_insmod(driver, NETWORK_DEVICES, NULL, 1);
		warning_insmod_failed(failed);
		remove_wait_message();
		if (intf_descr_for_discover) /* for modules providing more than one net intf */
			net_discovered_interface(NULL);
	}
#endif
#ifdef ENABLE_USB
	if (type == USB_CONTROLLERS)
                /* we can't allow additional modules floppy since we need usbkbd for keystrokes of usb keyboards */
		failed = my_insmod(driver, USB_CONTROLLERS, NULL, 0);
#endif
}

#ifdef ENABLE_USB
void probe_that_type(enum driver_type type, enum media_bus bus)
#else
void probe_that_type(enum driver_type type, enum media_bus bus __attribute__ ((unused)))
#endif
{
        static int already_probed_usb_controllers = 0;
        static int already_loaded_usb_scsi = 0;

	/* ---- PCI probe ---------------------------------------------- */
	{
		FILE * f = NULL;
		unsigned int len = 0;
		unsigned int len_full = 0;
		char buf[200];
		struct pci_module_map * pcidb = NULL;
		struct pci_module_map_full * pcidb_full = NULL;

		switch (type) {
#ifndef DISABLE_PCIADAPTERS
#ifndef DISABLE_MEDIAS
			static int already_probed_scsi_adapters = 0;
		case SCSI_ADAPTERS:
			if (already_probed_scsi_adapters)
				goto end_pci_probe;
			already_probed_scsi_adapters = 1;
			pcidb = medias_pci_ids;
			len   = medias_num_ids;
			pcidb_full = medias_pci_ids_full;
			len_full   = medias_num_ids_full;
			break;
#endif
#ifndef DISABLE_NETWORK
		case NETWORK_DEVICES:
			pcidb = network_pci_ids;
			len   = network_num_ids;
			pcidb_full = network_pci_ids_full;
			len_full   = network_num_ids_full;
			break;
#endif
#endif
#ifdef ENABLE_USB
		case USB_CONTROLLERS:
			if (already_probed_usb_controllers || IS_NOAUTO)
				goto end_pci_probe;
			already_probed_usb_controllers = 1;
			pcidb = usb_pci_ids;
			len   = usb_num_ids;
			break;
#endif
		default:
			goto end_pci_probe;
		}

		if (!(f = fopen("/proc/bus/pci/devices", "rb"))) {
			log_message("PCI: could not open proc file");
			goto end_pci_probe;
		}

		while (1) {
			unsigned int i;
			unsigned short vendor, device, subvendor, subdevice, class_, devbusfn;
			unsigned char class_prog;
			const char *name, *module;
			enum driver_type type_ = type;

			if (!fgets(buf, sizeof(buf), f)) break;
	
			sscanf(buf, "%hx %x", &devbusfn, &i);
			device = i;
			vendor = i >> 16;

			{
				int bus = devbusfn >> 8;
				int device_p = (devbusfn & 0xff) >> 3;
				int function = (devbusfn & 0xff) & 0x07;
				char file[100];
				int sf;
				sprintf(file, "/proc/bus/pci/%02x/%02x.%d", bus, device_p, function);
				if ((sf = open(file, O_RDONLY)) == -1) {
					log_message("PCI: could not open file for full probe (%s)", file);
					continue;
				}
				if (read(sf, buf, 48) == -1) {
					log_message("PCI: could not read 48 bytes from %s", file);
					close(sf);
					continue;
				}
				close(sf);
				memcpy(&class_prog, buf+9, 1);
				memcpy(&class_, buf+10, 2);
				memcpy(&subvendor, buf+44, 2);
				memcpy(&subdevice, buf+46, 2);
			}

			/* special rules below must be in sync with ldetect/pci.c */

			if (class_ == PCI_CLASS_SERIAL_USB) {
				/* taken from kudzu's pci.c */
				module = 
					class_prog == 0 ? "usb-uhci" : 
					class_prog == 0x10 ? "usb-ohci" :
					class_prog == 0x20 ? "ehci-hcd" : NULL;
				if (module) {
					name = "USB Controller";
					type_ = USB_CONTROLLERS;
					goto found_pci_device;
				}
			}
			if (class_ == PCI_CLASS_SERIAL_FIREWIRE) {
				/* taken from kudzu's pci.c */
				if (class_prog == 0x10) {
					module = strdup("ohci1394");
					name = "Firewire Controller";
					goto found_pci_device;
				}
			}

			for (i = 0; i < len_full; i++)
				if (pcidb_full[i].vendor == vendor && pcidb_full[i].device == device) {
					if (pcidb_full[i].subvendor == subvendor && pcidb_full[i].subdevice == subdevice) {
						name = pcidb_full[i].name;
						module = pcidb_full[i].module;
						goto found_pci_device;
					}
				}
			
			for (i = 0; i < len; i++)
				if (pcidb[i].vendor == vendor && pcidb[i].device == device) {
					name = pcidb[i].name;
					module = pcidb[i].module;
					goto found_pci_device;
				}

			continue;

		found_pci_device:
                        log_message("PCI: device %04x %04x %04x %04x is \"%s\", driver is %s", vendor, device, subvendor, subdevice, name, module);
			discovered_device(type_, name, module);
		}
	end_pci_probe:;
		if (f)
                        fclose(f);
	}


#ifdef ENABLE_USB
	/* ---- USB probe ---------------------------------------------- */
	if ((bus == BUS_USB || bus == BUS_ANY) && !(IS_NOAUTO)) {
		static int already_mounted_usbdev = 0;

		FILE * f = NULL;
		int len = 0;
		char buf[200];
		struct usb_module_map * usbdb = NULL;

		if (!already_probed_usb_controllers) {
			already_probed_usb_controllers = 1;
			probe_that_type(USB_CONTROLLERS, BUS_ANY);
		}

		if (!already_mounted_usbdev) {
			already_mounted_usbdev = 1;
			if (mount("none", "/proc/bus/usb", "usbfs", 0, NULL) &&
			    mount("none", "/proc/bus/usb", "usbdevfs", 0, NULL)) {
				log_message("USB: couldn't mount /proc/bus/usb");
				goto end_usb_probe;
			}
			wait_message("Detecting USB devices.");
			sleep(4); /* sucking background work */
			my_insmod("usbkbd", ANY_DRIVER_TYPE, NULL, 0);
			my_insmod("keybdev", ANY_DRIVER_TYPE, NULL, 0);
			remove_wait_message();
		}

		if (!(f = fopen("/proc/bus/usb/devices", "rb"))) {
			log_message("USB: could not open proc file");
			goto end_usb_probe;
		}

		switch (type) {
		case NETWORK_DEVICES:
			usbdb = usb_usb_ids;
			len   = usb_usb_num_ids;
			break;
		default:
			goto end_usb_probe;
		}

		while (1) {
			int i, vendor, id;

			if (!fgets(buf, sizeof(buf), f)) break;

			if (sscanf(buf, "P:  Vendor=%x ProdID=%x", &vendor, &id) != 2)
				continue;

			for (i = 0; i < len; i++) {
				if (usbdb[i].vendor == vendor && usbdb[i].id == id) {
					log_message("USB: device %04x %04x is \"%s\" (%s)", vendor, id, usbdb[i].name, usbdb[i].module);
					discovered_device(type, usbdb[i].name, usbdb[i].module);
				}
			}
		}
	end_usb_probe:;
		if (f)
                        fclose(f);
	}
#endif

#ifdef ENABLE_PCMCIA
	/* ---- PCMCIA probe ---------------------------------------------- */
	if ((bus == BUS_PCMCIA || bus == BUS_ANY) && !(IS_NOAUTO)) {
		struct pcmcia_alias * pcmciadb = NULL;
		unsigned int len = 0;
		char *base = "/sys/bus/pcmcia/devices";
		DIR *dir;
		struct dirent *dent;

		dir = opendir(base);
		if (dir == NULL)
			goto end_pcmcia_probe;

		switch (type) {
#ifndef DISABLE_MEDIAS
		case SCSI_ADAPTERS:
			pcmciadb = medias_pcmcia_ids;
			len      = medias_pcmcia_num_ids;
			break;
#endif
#ifndef DISABLE_NETWORK
		case NETWORK_DEVICES:
			pcmciadb = network_pcmcia_ids;
			len      = network_pcmcia_num_ids;
			break;
#endif
		default:
			goto end_pcmcia_probe;
                }

                for (dent = readdir(dir); dent != NULL; dent = readdir(dir)) {
			struct sysfs_attribute *modalias_attr;
			char keyfile[256];
			int i, id;

			if (dent->d_name[0] == '.')
				continue;

			log_message("PCMCIA: device found %s", dent->d_name);

			snprintf(keyfile, sizeof(keyfile)-1, "%s/%s/modalias", base, dent->d_name);
			modalias_attr = sysfs_open_attribute(keyfile);
			if (!modalias_attr)
				continue;
			if (sysfs_read_attribute(modalias_attr) != 0 || !modalias_attr->value) {
				sysfs_close_attribute(modalias_attr);
				continue;
			}

			log_message("PCMCIA: device found %s", modalias_attr->value);

			for (i = 0; i < len; i++) {
				if (!fnmatch(pcmciadb[i].modalias, modalias_attr->value, 0)) {
					char product[256];

					log_message("PCMCIA: device found %s (%s)", pcmciadb[i].modalias, pcmciadb[i].module);
					strcpy(product, "");
					for (id = 1; id <= 4; id++) {
						struct sysfs_attribute *product_attr;
						snprintf(keyfile, sizeof(keyfile)-1, "%s/%s/prod_id%d", base, dent->d_name, id);
						product_attr = sysfs_open_attribute(keyfile);
						if (!product_attr)
							continue;
						if (sysfs_read_attribute(product_attr) || !product_attr->value) {
							sysfs_close_attribute(product_attr);
							continue;
						}
						snprintf(product + strlen(product), sizeof(product)-strlen(product)-1, "%s%s", product[0] ? " " : "", product_attr->value);
						if (product[strlen(product)-1] == '\n')
							product[strlen(product)-1] = '\0';
						sysfs_close_attribute(product_attr);
					}

					if (!product[0])
						strcpy(product, "PCMCIA device");

					log_message("PCMCIA: device found %s (%s)", product, pcmciadb[i].module);
					discovered_device(type, product, pcmciadb[i].module);
				}
			}

			sysfs_close_attribute(modalias_attr);
		}
	end_pcmcia_probe:;
		if (dir)
			closedir(dir);
	}
#endif

        /* be sure to load usb-storage after SCSI adapters, so that they are in
           same order than reboot, so that naming is the same */
        if (type == SCSI_ADAPTERS && already_probed_usb_controllers && !already_loaded_usb_scsi) {
                already_loaded_usb_scsi = 1;
                /* we can't allow additional modules floppy since we need usbkbd for keystrokes of usb keyboards */
                my_insmod("usb-storage", SCSI_ADAPTERS, NULL, 0); 
                if (module_already_present("ieee1394"))
                        my_insmod("sbp2", SCSI_ADAPTERS, NULL, 0);
                wait_message("Detecting USB mass-storage devices.");
                sleep(10); /* sucking background work */
                remove_wait_message();
        }
}


static struct media_info * medias = NULL;

static void find_media(enum media_bus bus)
{
    	char b[50];
	char buf[5000];
	struct media_info tmp[50];
	int count = 0;
        int fd;

	if (medias)
		free(medias); /* that does not free the strings, by the way */

	if (bus == BUS_SCSI || bus == BUS_USB || bus == BUS_PCMCIA || bus == BUS_ANY) {
                log_message("looking for media adapters");
                probe_that_type(SCSI_ADAPTERS, bus);
        }
	/* ----------------------------------------------- */
	if (bus != BUS_IDE && bus != BUS_ANY)
		goto find_media_after_ide;
	log_message("looking for ide media");

    	strcpy(b, "/proc/ide/hd");
    	for (b[12] = 'a'; b[12] <= 't'; b[12]++) {
		int i;
		char ide_disk[] = "disk";
		char ide_cdrom[] = "cdrom";
		char ide_tape[] = "tape";
		char ide_floppy[] = "floppy";
		
		/* first, test if file exists (will tell if attached medium exists) */
		b[13] = '\0';
		if (access(b, R_OK))
			continue;

		tmp[count].name = strdup("hda");
		tmp[count].name[2] = b[12];

		/* media type */
		strcpy(b + 13, "/media");
		fd = open(b, O_RDONLY);
		if (fd == -1) {
			log_message("failed to open %s for reading", b);
			continue;
		}

		i = read(fd, buf, sizeof(buf));
		if (i == -1) {
			log_message("failed to read %s", b);
			continue;
		}
		buf[i] = '\0';
		close(fd);

		if (ptr_begins_static_str(buf, ide_disk))
			tmp[count].type = DISK;
		else if (ptr_begins_static_str(buf, ide_cdrom))
			tmp[count].type = CDROM;
		else if (ptr_begins_static_str(buf, ide_tape))
			tmp[count].type = TAPE;
		else if (ptr_begins_static_str(buf, ide_floppy))
			tmp[count].type = FLOPPY;
		else
			tmp[count].type = UNKNOWN_MEDIA;

		/* media model */
		strcpy(b + 13, "/model");
		fd = open(b, O_RDONLY);
		if (fd == -1) {
			log_message("failed to open %s for reading", b);
			continue;
		}

		i = read(fd, buf, sizeof(buf));
		if (i <= 0) {
			log_message("failed to read %s", b);
			tmp[count].model = strdup("(none)");
		}
		else {
			buf[i-1] = '\0'; /* eat the \n */
			tmp[count].model = strdup(buf);
		}
		close(fd);

		log_message("IDE/%d: %s is a %s", tmp[count].type, tmp[count].name, tmp[count].model);
		count++;
    	}

 find_media_after_ide:
	/* ----------------------------------------------- */
	if (bus != BUS_SCSI && bus != BUS_USB && bus != BUS_PCMCIA && bus != BUS_ANY)
		goto find_media_after_scsi;
	log_message("looking for scsi media");

	fd = open("/proc/scsi/scsi", O_RDONLY);
	if (fd != -1) {
                FILE * f;

		enum { SCSI_TOP, SCSI_HOST, SCSI_VENDOR, SCSI_TYPE } state = SCSI_TOP;
		char * start, * chptr, * next, * end;
		char scsi_disk_count = 'a';
		char scsi_cdrom_count = '0';
		char scsi_tape_count = '0';

		char scsi_no_devices[] = "Attached devices: none";
		char scsi_some_devices[] = "Attached devices:";
		char scsi_host[] = "Host: ";
		char scsi_vendor[] = "  Vendor: ";

		int i = read(fd, &buf, sizeof(buf)-1);
		if (i < 1) {
			close(fd);
			goto end_scsi;
		}
		close(fd);
		buf[i] = '\0';

		if (ptr_begins_static_str(buf, scsi_no_devices))
			goto end_scsi;
		
		start = buf;
		while (*start) {
			char tmp_model[50];
			char tmp_name[10];

			chptr = start;
			while (*chptr != '\n') chptr++;
			*chptr = '\0';
			next = chptr + 1;
			
			switch (state) {
			case SCSI_TOP:
				if (!ptr_begins_static_str(start, scsi_some_devices))
					goto end_scsi;
				state = SCSI_HOST;
				break;

			case SCSI_HOST:
				if (!ptr_begins_static_str(start, scsi_host))
					goto end_scsi;
				state = SCSI_VENDOR;
				break;

			case SCSI_VENDOR:
				if (!ptr_begins_static_str(start, scsi_vendor))
					goto end_scsi;

				/* (1) Grab Vendor info */
				start += 10;
				end = chptr = strstr(start, "Model:");
				if (!chptr)
					goto end_scsi;

				chptr--;
				while (*chptr == ' ')
					chptr--;
				if (*chptr == ':') {
					chptr++;
					*(chptr + 1) = '\0';
					strcpy(tmp_model,"(unknown)");
				} else {
					*(chptr + 1) = '\0';
					strcpy(tmp_model, start);
				}

				/* (2) Grab Model info */
				start = end;
				start += 7;
				
				chptr = strstr(start, "Rev:");
				if (!chptr)
					goto end_scsi;
				
				chptr--;
				while (*chptr == ' ') chptr--;
				*(chptr + 1) = '\0';
				
				strcat(tmp_model, " ");
				strcat(tmp_model, start);

				tmp[count].model = strdup(tmp_model);
				
				state = SCSI_TYPE;

				break;

			case SCSI_TYPE:
				if (strncmp("  Type:", start, 7))
					goto end_scsi;
				*tmp_name = '\0';

				if (strstr(start, "Direct-Access")) {
					sprintf(tmp_name, "sd%c", scsi_disk_count++);
					tmp[count].type = DISK;
				} else if (strstr(start, "Sequential-Access")) {
					sprintf(tmp_name, "st%c", scsi_tape_count++);
					tmp[count].type = TAPE;
				} else if (strstr(start, "CD-ROM")) {
					sprintf(tmp_name, "sr%c", scsi_cdrom_count++);
					tmp[count].type = CDROM;
				}

                                if (!(f = fopen("/proc/partitions", "rb")) || !fgets(buf, sizeof(buf), f) || !fgets(buf, sizeof(buf), f)) {
                                        log_message("Couldn't open /proc/partitions");
                                } else {
                                        while (fgets(buf, sizeof(buf), f)) {
                                                char name[100];
                                                int major, minor, blocks;
                                                memset(name, 0, sizeof(name));
                                                sscanf(buf, " %d %d %d %s", &major, &minor, &blocks, name);
                                                if (streq(name, tmp_name) && tmp[count].type == DISK && ((blocks == 1048575) || (blocks == 1440)))
                                                        tmp[count].type = FLOPPY;
                                        }
                                        fclose(f);
                                }

				if (*tmp_name) {
					tmp[count].name = strdup(tmp_name);
					log_message("SCSI/%d: %s is a %s", tmp[count].type, tmp[count].name, tmp[count].model);
					count++;
				}
				
				state = SCSI_HOST;
			}
			
			start = next;
		}
		
	end_scsi:;
	}

	/* ----------------------------------------------- */
	log_message("looking for Compaq Smart Array media");
	{
		char * procfiles[] = { "/proc/driver/cpqarray/ida0", "/proc/driver/cciss/cciss0", // 2.4 style
				       "/proc/array/ida", "/proc/cciss/cciss",                 // 2.2 style
				       NULL };
		static char cpq_descr[] = "Compaq RAID logical disk";
		char ** procfile = procfiles;
		FILE * f;
		while (procfile && *procfile && (f = fopen(*procfile, "rb"))) {
			while (fgets(buf, sizeof(buf), f)) {
				if (ptr_begins_static_str(buf, "ida/") || ptr_begins_static_str(buf, "cciss/")) {
					char * end = strchr(buf, ':');
					if (!end)
						log_message("Inconsistency in %s, line:\n%s", *procfile, buf);
					else {
						*end = '\0';
						tmp[count].name = strdup(buf);
						tmp[count].type = DISK;
						tmp[count].model = cpq_descr;
						log_message("CPQ: found %s", tmp[count].name);
						count++;
					}
				}
			}
			fclose(f);
			procfile++;
		}
	}

	/* ----------------------------------------------- */
	log_message("looking for DAC960");
	{
		FILE * f;
		if ((f = fopen("/tmp/syslog", "rb"))) {
			while (fgets(buf, sizeof(buf), f)) {
				char * start;
				if ((start = strstr(buf, "/dev/rd/"))) {
					char * end = strchr(start, ':');
					if (!end)
						log_message("Inconsistency in syslog, line:\n%s", buf);
					else {
						*end = '\0';
						tmp[count].name = strdup(start+5);
						tmp[count].type = DISK;
						start = end + 2;
						end = strchr(start, ',');
						if (end) {
							*end = '\0';
							tmp[count].model = strdup(start);
						} else
							tmp[count].model = "(unknown)";
						log_message("DAC960: found %s (%s)", tmp[count].name, tmp[count].model);
						count++;
					}
				}
			}
			fclose(f);
		}
	}
 find_media_after_scsi:

	/* ----------------------------------------------- */
	tmp[count].name = NULL;
	count++;

	medias = memdup(tmp, sizeof(struct media_info) * count);
}


/* Finds by media */
void get_medias(enum media_type media, char *** names, char *** models, enum media_bus bus)
{
	struct media_info * m;
	char * tmp_names[50];
	char * tmp_models[50];
	int count;

	find_media(bus);

	m = medias;

	count = 0;
	while (m && m->name) {
		if (m->type == media) {
			tmp_names[count] = strdup(m->name);
			tmp_models[count++] = strdup(m->model);
		}
		m++;
	}
	tmp_names[count] = NULL;
	tmp_models[count++] = NULL;

	*names = memdup(tmp_names, sizeof(char *) * count);
	*models = memdup(tmp_models, sizeof(char *) * count);
}


#ifndef DISABLE_NETWORK
static int is_net_interface_blacklisted(char *intf)
{
	/* see detect_devicess::is_lan_interface() */
	char * blacklist[] = { "lo", "ippp", "isdn", "plip", "ppp", "wifi", "sit", NULL };
	char ** ptr = blacklist;

	while (ptr && *ptr) {
		if (!strncmp(intf, *ptr, strlen(*ptr)))
			return 1;
		ptr++;
	}

	return 0;
}

char ** get_net_devices(void)
{
	char * tmp[50];
	static int already_probed = 0;
	FILE * f;
	int i = 0;

	if (!already_probed) {
		already_probed = 1; /* cut off loop brought by: probe_that_type => my_insmod => get_net_devices */
		probe_that_type(NETWORK_DEVICES, BUS_ANY);
	}

	/* use /proc/net/dev since SIOCGIFCONF doesn't work with some drivers (rt2500) */
	f = fopen("/proc/net/dev", "rb");
	if (f) {
		char line[128];

		/* skip the two first lines */
		fgets(line, sizeof(line), f);
		fgets(line, sizeof(line), f);

		while (1) {
			char *start, *end;
			if (!fgets(line, sizeof(line), f))
				break;
			start = line;
			while (*start == ' ')
				start++;
			end = strchr(start, ':');
			if (end)
				end[0] = '\0';
			if (!is_net_interface_blacklisted(start)) {
				log_message("found net interface %s", start);
				tmp[i++] = strdup(start);
			} else {
				log_message("found net interface %s, but blacklisted", start);
			}
		}

		fclose(f);
	} else {
		log_message("net: could not open devices file");
	}

	tmp[i++] = NULL;

	return memdup(tmp, sizeof(char *) * i);

}
#endif /* DISABLE_NETWORK */
